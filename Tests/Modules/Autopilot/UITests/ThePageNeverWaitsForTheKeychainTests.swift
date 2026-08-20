import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The mark, standing in for the keychain item that holds it.
///
/// The twin of the engine target's `TestRuleSequence`, and separate for the only
/// reason two test targets duplicate anything here: a stand-in for a *module's*
/// port cannot live in `HelmTestSupport`, which may reach `HelmRuntime` and no
/// module (`FakePresetFolders` carries the same note).
///
/// It keeps both of that file's capabilities rather than being a `UInt64` in a
/// box: a keychain that will not answer and one that answers but will not be
/// written are different states, and a double that could not be in them is one
/// no test of them could exist under.
private final class UITestRuleSequence: RuleSequencePort, @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64?
    private let available: Bool
    private let writable: Bool

    init(at: UInt64? = nil, available: Bool = true, writable: Bool = true) {
        self.value = at
        self.available = available
        self.writable = writable
    }

    func highWater() -> RuleSequence {
        lock.withLock {
            guard available else { return .unavailable }
            return value.map(RuleSequence.at) ?? .absent
        }
    }

    @discardableResult
    func raise(to seq: UInt64) -> Bool {
        lock.withLock {
            guard writable else { return false }
            value = seq
            return true
        }
    }
}

/// **The page is built on the thread that draws, and Autopilot's seal key is the
/// one seal guard in the app with no `SealKeyCache` in front of it.**
///
/// Every verdict about the stored rules needs that key, and on this ad-hoc
/// signed bundle asking for it is a modal authorization dialog rather than data:
/// the cdhash changes with every build, so no access list an earlier one wrote
/// still names this one. The same arrangement was measured twice in one day —
/// `HelmApp_2026-08-19-235500_MacBook.hang`, 19,09 s of a settings window that
/// could not answer a mouse-up (4dcc5fb6), and then Duplicates' page building
/// its view model inside `init` (23dae882) — and CLAUDE.md's rule is that «init
/// means **any** init», which a SwiftUI page's initialiser is one layout pass
/// away from.
///
/// `AutopilotLaunchTests` holds the engine's two halves, construction and
/// `activate`. This holds the third door, the one those two cannot see: the page.
/// `AutopilotSettingsPage.init` builds `AutopilotViewModel`, which is
/// `@MainActor`, and everything it asks for — the folders, the status, the
/// history — is a command the engine answers by reading the rule set.
///
/// **The port is held mid-answer**, which is what makes any of this mean
/// anything: a keychain that replies instantly is over before the code under
/// test is reached, and every assertion about drawing while it is still deciding
/// would be vacuous. `SealKeyProbe` is that port, and it records *which thread*
/// asked — the question here, rather than how many times.
@MainActor
final class ThePageNeverWaitsForTheKeychainTests: XCTestCase {

    private var home: URL!
    private var downloads: URL!
    private var backing: InMemoryKeyValueStore!
    private var transport: LocalTransport!
    private var gate: DispatchSemaphore!
    private var probe: SealKeyProbe!
    private var helm: AutopilotEngine!

    override func setUpWithError() throws {
        home = scratchDirectory("page-keychain")
        downloads = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        backing = InMemoryKeyValueStore()
        transport = LocalTransport()
        gate = DispatchSemaphore(value: 0)
        probe = SealKeyProbe(gate: gate)
        helm = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: backing),
            transport: transport, home: home.path,
            keys: probe, sequence: UITestRuleSequence())
    }

    override func tearDown() {
        helm?.deactivate()
        // Nothing may be left parked on the gate. More signals than callers is
        // free; one fewer leaves a thread inside `key()` for the life of the
        // process, and a suite that leaks threads is a suite that leaves
        // something behind.
        for _ in 0..<8 { gate?.signal() }
    }

    private func model() -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: transport),
                           presetFolders: FakePresetFolders(home: home.path),
                           home: home.path)
    }

    /// The whole of it, in the order `ModuleHost` and SwiftUI do it: the engine
    /// is built and activated on the main thread, and then the page builds its
    /// view model there too — all while the keychain is parked mid-answer.
    ///
    /// Nothing here is a stopwatch assertion that a fast machine could pass by
    /// luck: the port *cannot* answer until this test lets it, so a main thread
    /// that waited for it would still be waiting at the deadline.
    func testTheEngineStartsAndThePageIsBuiltWhileTheKeychainIsStillDeciding() async {
        // The valve. A main thread that *does* wait for this port would wait for
        // ever, and a suite that hangs reports nothing at all — so the gate
        // opens by itself after two seconds and the deadline below is what
        // fails. Only a page that waited pays those two seconds.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [gate] in gate?.signal() }
        let started = Date()
        helm.activate()
        let rvm = model()
        let built = Date().timeIntervalSince(started)

        XCTAssertLessThan(built, 1, """
            starting the module and building its page waited for the keychain — on an ad-hoc \
            build that wait is a modal authorization dialog, and this is the thread that draws
            """)
        XCTAssertTrue(probe.waitUntilAsked(), """
            the premise: nothing ever asked for the key, so «it was not asked on the main thread» \
            is true of a run in which nothing happened at all
            """)
        XCTAssertFalse(probe.wasAskedOnTheMainThread, """
            the seal key was read on the thread that draws — the arrangement measured as \
            HelmApp_2026-08-19-235500_MacBook.hang, in the module that reads it most
            """)
        // And the page holds the screen it opens on while the answer is still
        // outstanding, rather than a refusal it has not earned.
        XCTAssertEqual(rvm.screen, .noFolders)
        XCTAssertNil(rvm.refusal, """
            a keychain that has not answered yet was drawn as one that refused, which is the \
            «not yet» and «forged» that SealKeyPort.keyIfWarm exists to keep apart
            """)

        gate.signal()
        await rvm.firstLoad?.value
    }

    /// And the same question asked of the load itself, not only of construction.
    ///
    /// The first load is the page's own task, and it is `@MainActor`: every hop
    /// inside it comes back to the thread that draws. What must never come back
    /// with it is the keychain round trip — the transport's `send` is
    /// nonisolated, so the engine answers on the cooperative pool, and this is
    /// the assertion that says so rather than a comment claiming it.
    func testTheFirstLoadReachesTheKeychainFromSomewhereElse() async {
        // Opened before anything starts: this one is about *which* thread asks,
        // not about answering while the answer is outstanding, and a gate still
        // shut would let a regression hang the suite instead of failing it.
        gate.signal()
        helm.activate()
        let rvm = model()

        await rvm.firstLoad?.value

        XCTAssertGreaterThan(probe.reads, 0, "the premise: the load really did need the key")
        XCTAssertFalse(probe.wasAskedOnTheMainThread,
                       "the page's own load carried the keychain onto the thread that draws")
    }

    /// The key is fetched **once for the process**, whichever of the four
    /// readers of the rule set gets there first.
    ///
    /// `SealedRules` holds it under `keyLock` rather than through `SealKeyCache`,
    /// which is the same promise made in a different place — so it is worth
    /// stating as a promise. A second round trip is a second dialog on every
    /// installed build.
    func testTheKeyIsFetchedOncePerProcess() async {
        gate.signal()
        helm.activate()
        let rvm = model()
        await rvm.firstLoad?.value
        await rvm.load()
        await rvm.loadHistory()

        XCTAssertEqual(probe.reads, 1, """
            the keychain was asked \(probe.reads) times for a key that is created once and never \
            rewritten — every ask past the first is another modal dialog
            """)
    }
}
