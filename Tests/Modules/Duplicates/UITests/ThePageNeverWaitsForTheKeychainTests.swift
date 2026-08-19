import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// **The page is built on the thread that draws, so building it must be free.**
///
/// `DuplicatesViewModel` is `@MainActor` and its `init` read the keep policy —
/// which verifies a seal, which needs the key, which comes from the login
/// keychain. On an ad-hoc build the cdhash changes with every build, no access
/// list an earlier one wrote still names this one, and the answer is a modal
/// authorization dialog rather than data: the same arrangement measured as
/// `HelmApp_2026-08-19-235500_MacBook.hang`, 19,09 s of a settings window that
/// could not answer a mouse-up, one target over.
///
/// So the policy starts at the standard belief and arrives from a task the
/// initialiser holds. Held rather than fired and forgotten, for the reason
/// Autopilot's model records: a load nobody can await is a load every test races.
@MainActor
final class ThePageNeverWaitsForTheKeychainTests: XCTestCase {

    private var store: NamespacedStore!

    override func setUp() async throws {
        store = duplicatesStore(folder: "\(home)/Downloads")
    }

    /// The production wiring, spelled the way the module spells it: the probe
    /// stands in for the login keychain and `SealKeyCache` for what is in front
    /// of it, so «warm» here means what it means in the app.
    private func model(over keys: SealKeyPort) -> DuplicatesViewModel {
        DuplicatesViewModel(vm: ModuleViewModel(transport: OneAnswerTransport(groups: [])),
                            store: store, settings: SettingGuard(keys: keys))
    }

    // MARK: - Cold

    /// The guard the defect walked past: building the page asks the keychain
    /// nothing at all.
    func testBuildingThePageAsksTheKeychainNothing() {
        let probe = SealKeyProbe()

        _ = model(over: SealKeyCache(probe))

        XCTAssertEqual(probe.reads, 0, """
            the page's own construction went to the keychain, which on an ad-hoc build is a modal \
            authorization dialog — and this initialiser runs on the thread that draws
            """)
    }

    /// And the hang itself, with a keychain that is **still deciding**: the page
    /// is built and answers while the port is parked mid-call.
    ///
    /// A port that answers instantly cannot be in the state this is about — the
    /// subject is over before the code under test is reached — so the probe is
    /// held on its gate, which is what that gate is for. The valve keeps a page
    /// that *does* wait from hanging the suite: it fails a deadline instead.
    func testThePageIsBuiltWhileTheKeychainIsStillDeciding() async {
        let gate = DispatchSemaphore(value: 0)
        let probe = SealKeyProbe(gate: gate)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { gate.signal() }

        let started = Date()
        let dvm = model(over: SealKeyCache(probe))
        let built = Date().timeIntervalSince(started)

        XCTAssertLessThan(built, 1, """
            building the page waited for the keychain — on an ad-hoc build that wait is a modal \
            authorization dialog, and this is the thread that draws
            """)
        XCTAssertEqual(dvm.policy, .standard, "and it answers while the keychain is still deciding")
        await dvm.firstLoad?.value
    }

    /// And what it shows meanwhile is the standard belief, **with a policy really
    /// stored**: an empty store answers `.standard` however the page is written,
    /// so a page that had read the plist inside `init` would pass that.
    func testThePageOpensOnTheStandardBeliefWhileTheKeyIsStillCold() {
        let probe = SealKeyProbe()
        DuplicatesSettings.setKeepPolicy(.byDate, in: store, guardedBy: SettingGuard(keys: probe))

        XCTAssertEqual(model(over: SealKeyCache(probe)).policy, .standard)
    }

    // MARK: - Warm

    /// And the stored policy still arrives, once the key is in hand.
    ///
    /// **The page's own cache starts cold**, which is what makes this about the
    /// page: sealing through a guard that shares the model's cache would warm it
    /// before the model existed, and the assertion below then held with the
    /// warming deleted — measured, on the mutant that dropped `warmKey()`.
    func testTheStoredPolicyArrivesOnceTheKeyIsInHand() async {
        let probe = SealKeyProbe()
        DuplicatesSettings.setKeepPolicy(.byDate, in: store, guardedBy: SettingGuard(keys: probe))
        let dvm = model(over: SealKeyCache(probe))

        await dvm.firstLoad?.value

        XCTAssertEqual(dvm.policy, .byDate,
                       "the page never caught up with what the engine has stored")
    }

    /// The round trip happens, and it happens somewhere else. Both halves: a
    /// check that the keychain was not asked on the main thread passes by itself
    /// when the keychain was never asked at all.
    func testTheKeyIsFetchedOffTheThreadThatDraws() async {
        let probe = SealKeyProbe()
        let dvm = model(over: SealKeyCache(probe))

        await dvm.firstLoad?.value

        XCTAssertGreaterThan(probe.reads, 0,
                             "the key was never fetched, so the assertion below is about nothing")
        XCTAssertFalse(probe.wasAskedOnTheMainThread, """
            the round trip was made on the thread that draws — suspending is not the same as \
            handing the work to another thread
            """)
    }

    // MARK: - And the page reads the cheap one

    /// **Read from the source, because the type system cannot say this.** Both
    /// readings answer a `KeepPolicy` and both compile anywhere in this target;
    /// what separates them is that one can take 19 seconds, and everything in
    /// this target is `@MainActor`.
    ///
    /// A **write** is allowed and is not this defect: `choose` and `chooseFolder`
    /// seal what somebody just pressed, and there is no control to press until
    /// the page has been up — the key is warm by construction. The same exception
    /// `TheSettingsPageNeverWaitsForTheKeychainTests` makes, one target over.
    func testNothingOnThePageReadsTheBlockingPolicy() throws {
        var offences: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources/Modules/Duplicates/UI") {
            for (index, line) in try RepoSource.lines(of: path).enumerated() {
                let code = RepoSource.code(line)
                guard code.contains("DuplicatesSettings.keepPolicy("),
                      !code.contains("DuplicatesSettings.keepPolicyIfWarm(") else { continue }
                offences.append("\(path):\(index + 1): \(code.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(offences, [], """
            the policy is read through the reading that can go to the keychain, on the thread that \
            draws — `keepPolicyIfWarm` is the one that answers «not yet» instead of standing \
            behind a modal authorization dialog
            """)
    }

    /// And the scan above can only fail if the spelling it hunts for is one this
    /// target still uses — a rule whose subject has been renamed passes for ever.
    func testThePageDoesReadWhatIsInForce() throws {
        var readers: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources/Modules/Duplicates/UI")
        where try RepoSource.text(of: path).contains("DuplicatesSettings.keepPolicyIfWarm(") {
            readers.append(path)
        }
        XCTAssertFalse(readers.isEmpty, """
            nothing on this page reads what is in force any more, so the popup shows a belief of \
            its own and the scan above is looking for a spelling that is gone
            """)
    }

    /// A keychain that cannot answer — locked at login — leaves the page on the
    /// standard belief rather than waiting for one. It is the answer the engine
    /// applies in the same state, so the screen and the sweep still agree.
    func testAKeychainThatCannotAnswerLeavesTheStandardBelief() async {
        let silent = SilentSealKey()
        let dvm = model(over: SealKeyCache(silent))

        await dvm.firstLoad?.value

        XCTAssertGreaterThan(silent.reads, 0, "nothing ever asked, so the refusal never happened")
        XCTAssertEqual(dvm.policy, .standard)
    }
}
