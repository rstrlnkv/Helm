import HelmContract
import HelmRuntime
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **A tweak that is off builds nothing and runs nothing, and one that is stopped leaves nothing behind.**
///
/// A tweak reaches the machine in `activate()` (a window, a timer, an event tap), so the whole promise of the
/// Tweaks page is in `TweakHost`: a fresh store builds no engine, one switch builds and starts exactly one,
/// and every way out (its own switch, the entry's switch, `shutdown`) calls the model's `stop` and then the
/// engine's `deactivate()` and drops both. Written against recording fakes, because a real tweak here would be
/// whatever it does to this Mac while the suite runs.
///
/// The last row drives the entry through `ModuleHost`, which is what stops a tweak when somebody switches the
/// Tweaks entry off or hides it in the composer: deleting `TweaksEngine.deactivate`'s call to `stopAll` leaves
/// every other row green and this one red.
@MainActor
final class ASwitchedOffTweakRunsNothingTests: XCTestCase {

    /// Everything the fakes were asked, in order, across both tweaks.
    private final class Calls {
        var log: [String] = []
    }

    private final class FakeModel {}

    private final class FakeEngine: ModuleEngine {
        let name: String
        let calls: Calls
        init(_ name: String, _ calls: Calls) { self.name = name; self.calls = calls }
        func activate() { calls.log.append("activate \(name)") }
        func deactivate() { calls.log.append("deactivate \(name)") }
    }

    private class FakeTweak: TweakDescriptor {
        class var key: String { "" }
        static var id: ModuleID { ModuleID(key) }
        static var name: String { key }
        static var summary: String { "" }
        static var glyph: ShellGlyph { .settings }
        let calls: Calls
        init(_ calls: Calls) { self.calls = calls }
        func makeTweak(store: NamespacedStore) -> ModuleParts<FakeModel> {
            calls.log.append("make \(Self.key)")
            return ModuleParts(engine: FakeEngine(Self.key, calls), model: FakeModel())
        }
        func card(_ model: FakeModel) -> AnyView { AnyView(EmptyView()) }
        func stop(_ model: FakeModel) { calls.log.append("stop \(Self.key)") }
    }
    private final class Alpha: FakeTweak { override class var key: String { "alpha" } }
    private final class Beta: FakeTweak { override class var key: String { "beta" } }

    private func host(_ calls: Calls, backing: InMemoryKeyValueStore = InMemoryKeyValueStore()) -> TweakHost {
        TweakHost(registry: [Alpha(calls), Beta(calls)], backing: backing)
    }

    func testAFreshStoreBuildsAndActivatesNothing() {
        let calls = Calls()
        let host = host(calls)
        host.activateEnabled()
        XCTAssertEqual(calls.log, [], "a tweak nobody switched on was built")
        XCTAssertTrue(host.live.isEmpty)
    }

    func testSwitchingOnActivatesOnceAndASecondPassBuildsNothing() {
        let calls = Calls()
        let host = host(calls)
        host.setEnabled(host.descriptors[0], true)
        XCTAssertEqual(calls.log, ["make alpha", "activate alpha"], "the subject did not happen first")
        host.activateEnabled()
        host.activateEnabled()
        XCTAssertEqual(calls.log, ["make alpha", "activate alpha"],
                       "a pass over an enabled, live tweak built a second engine and orphaned the first")
    }

    func testSwitchingOffStopsTheModelThenTheEngineThenDropsBoth() {
        let calls = Calls()
        let host = host(calls)
        host.setEnabled(host.descriptors[0], true)
        calls.log = []
        host.setEnabled(host.descriptors[0], false)
        XCTAssertEqual(calls.log, ["stop alpha", "deactivate alpha"])
        XCTAssertNil(host.live["alpha"])
        XCTAssertFalse(host.isEnabled(host.descriptors[0]))
    }

    func testStoppingTwiceIsSafeAndWritesNoFlag() {
        let calls = Calls()
        let backing = InMemoryKeyValueStore()
        let host = host(calls, backing: backing)
        host.setEnabled(host.descriptors[0], true)
        host.stopAll()
        calls.log = []
        host.stopAll()
        XCTAssertEqual(calls.log, [], "a second stop ran a stop or a deactivate again")
        XCTAssertTrue(host.isEnabled(host.descriptors[0]), "stopping is not switching off: the flag moved")
        host.activateEnabled()
        XCTAssertNotNil(host.live["alpha"], "the next pass does not build the same set again")
    }

    func testTwoTweaksKeepSeparateFlagsUnderTheirOwnNamespaces() {
        let calls = Calls()
        let backing = InMemoryKeyValueStore()
        let host = host(calls, backing: backing)
        host.setEnabled(host.descriptors[1], true)
        XCTAssertFalse(host.isEnabled(host.descriptors[0]))
        XCTAssertTrue(host.isEnabled(host.descriptors[1]))
        XCTAssertEqual(TweakHost.namespace(for: host.descriptors[1]), "tweak.beta")
        XCTAssertEqual(backing.object(forKey: "module.tweak.beta.enabled") as? Bool, true,
                       "the flag is not where the namespace says it is")
        XCTAssertEqual(host.live.keys.sorted(), ["beta"])
    }

    // MARK: - The entry

    private static let entryID = "test-tweaks-entry"

    /// The Tweaks entry as `ModuleHost` sees it, over the fake tweaks.
    private final class Entry: StandInDescriptor {
        static let id = ModuleID(ASwitchedOffTweakRunsNothingTests.entryID)
        let host: TweakHost
        init(_ host: TweakHost) { self.host = host }
        func makeModule(store: NamespacedStore) -> ModuleParts<TweakHost> {
            ModuleParts(engine: TweaksEngine(host: host), model: host)
        }
        func stop(_ model: TweakHost) {}
    }

    override func tearDown() {
        ModuleHost.shared.shutdown()
        UserDefaults.standard.removeObject(forKey: "module.\(Self.entryID).enabled")
        super.tearDown()
    }

    /// The entry's switch is the one that matters most: every tweak stops with it, and with `shutdown`.
    func testSwitchingTheEntryOffStopsEveryTweak() {
        let calls = Calls()
        let tweaks = host(calls)
        let entry = Entry(tweaks)
        for d in tweaks.descriptors { tweaks.setEnabled(d, true) }
        tweaks.stopAll()   // as a launch finds them: on in the store, nothing built
        calls.log = []

        ModuleHost.shared.setEnabled(entry, true)
        XCTAssertEqual(tweaks.live.keys.sorted(), ["alpha", "beta"],
                       "the entry came up and started no tweak, so the stop below proves nothing")
        calls.log = []
        ModuleHost.shared.setEnabled(entry, false)
        XCTAssertTrue(tweaks.live.isEmpty, "the entry went off with tweaks still running")
        XCTAssertEqual(calls.log, ["stop alpha", "deactivate alpha", "stop beta", "deactivate beta"])
    }

    func testShutdownStopsEveryTweakToo() {
        let calls = Calls()
        let tweaks = host(calls)
        for d in tweaks.descriptors { tweaks.setEnabled(d, true) }
        tweaks.stopAll()
        ModuleHost.shared.setEnabled(Entry(tweaks), true)
        XCTAssertEqual(tweaks.live.count, 2)
        ModuleHost.shared.shutdown()
        XCTAssertTrue(tweaks.live.isEmpty, "the app quit with tweaks still running")
    }
}
