import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Inputs `ASwitchedOffTweakRunsNothingTests` did not feed `TweakHost`**: a flag stored with a wrong type,
/// the same switch pressed twice, off while never on, the entry switched off and on again, and a stored
/// sidebar that names the entry twice or a tweak as if it were an entry.
@MainActor
final class TweakHostUnfedInputsTests: XCTestCase {

    private final class Calls { var log: [String] = [] }
    private final class FakeModel {}
    private final class FakeEngine: ModuleEngine {
        let calls: Calls
        init(_ calls: Calls) { self.calls = calls }
        func activate() { calls.log.append("activate") }
        func deactivate() { calls.log.append("deactivate") }
    }
    private final class Fake: TweakDescriptor {
        static var id: ModuleID { ModuleID("fake") }
        static var name: String { "fake" }
        static var summary: String { "" }
        static var glyph: ShellGlyph { .settings }
        let calls: Calls
        init(_ calls: Calls) { self.calls = calls }
        func makeTweak(store: NamespacedStore) -> ModuleParts<FakeModel> {
            calls.log.append("make")
            return ModuleParts(engine: FakeEngine(calls), model: FakeModel())
        }
        func rows(_ model: FakeModel) -> [AnyView] { [] }
        func stop(_ model: FakeModel) { calls.log.append("stop") }
    }

    private let flagKey = "module.tweak.fake.enabled"

    private func host(_ calls: Calls, _ backing: InMemoryKeyValueStore = InMemoryKeyValueStore()) -> TweakHost {
        TweakHost(registry: [Fake(calls)], backing: backing)
    }

    func testSwitchingOnTwiceBuildsOneEngine() {
        let calls = Calls()
        let h = host(calls)
        h.setEnabled(h.descriptors[0], true)
        h.setEnabled(h.descriptors[0], true)
        XCTAssertEqual(calls.log, ["make", "activate"], "the subject did not happen first, or a second build orphaned the first")
    }

    func testSwitchingOffWhileNeverOnRunsNothingAndStoresFalse() {
        let calls = Calls()
        let backing = InMemoryKeyValueStore()
        let h = host(calls, backing)
        h.setEnabled(h.descriptors[0], false)
        XCTAssertEqual(calls.log, [])
        XCTAssertEqual(backing.object(forKey: flagKey) as? Bool, false, "the off was not saved")
        h.setEnabled(h.descriptors[0], true)
        XCTAssertEqual(calls.log, ["make", "activate"], "an off first left the tweak unable to start")
    }

    func testAFlagOfAWrongTypeIsOffAndBuildsNothing() {
        for (label, wrong) in [("string yes", "yes" as Any), ("string true", "true"), ("int 2", 2),
                               ("real 0.5", 0.5), ("array", [true]), ("data", Data([1]))] {
            let calls = Calls()
            let backing = InMemoryKeyValueStore()
            backing.raw = [flagKey: wrong]
            XCTAssertNotNil(backing.object(forKey: flagKey), "\(label): nothing was planted")
            let h = host(calls, backing)
            h.activateEnabled()
            XCTAssertEqual(calls.log, [], "\(label): a flag that is not a boolean switched the tweak on")
            XCTAssertFalse(h.isEnabled(h.descriptors[0]), label)
        }
    }

    func testAWrongTypeFlagIsOverwrittenByTheNextSwitch() {
        let calls = Calls()
        let backing = InMemoryKeyValueStore()
        backing.raw = [flagKey: "yes"]
        let h = host(calls, backing)
        h.setEnabled(h.descriptors[0], true)
        XCTAssertEqual(backing.object(forKey: flagKey) as? Bool, true)
        XCTAssertEqual(calls.log, ["make", "activate"])
    }

    /// What `UserDefaults` itself hands back for a plist `<integer>1</integer>` and `<real>1</real>` is an
    /// `NSNumber`, which `as? Bool` accepts: found, not fixed, so this pins the answer a person editing the
    /// plist by hand gets. Only 0 and 1 bridge.
    func testRealUserDefaultsHandsBackNumbersThatBridgeToBool() throws {
        // A suite named by an absolute path keeps its file in a scratch directory that is swept, not under
        // ~/Library/Preferences, where a named suite leaves an empty plist after `removePersistentDomain`.
        let suite = scratchDirectory("tweak-flag").appendingPathComponent("suite").path
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let calls = Calls()
        let h = TweakHost(registry: [Fake(calls)], backing: defaults)
        defaults.set(2, forKey: flagKey)
        XCTAssertFalse(h.isEnabled(h.descriptors[0]), "2 is not a boolean")
        defaults.set("yes", forKey: flagKey)
        XCTAssertFalse(h.isEnabled(h.descriptors[0]))
        defaults.set(1, forKey: flagKey)
        XCTAssertTrue(h.isEnabled(h.descriptors[0]), "integer 1 from the plist")
        defaults.set(0, forKey: flagKey)
        XCTAssertFalse(h.isEnabled(h.descriptors[0]))
    }

    private static let entryID = "test-tweaks-entry-2"
    private final class Entry: StandInDescriptor {
        static let id = ModuleID(TweakHostUnfedInputsTests.entryID)
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

    /// The entry off and on again: the tweak that was on comes back once, and one that was switched off while
    /// the entry was off does not.
    func testTheEntryOffAndOnAgainBringsBackExactlyWhatWasOn() {
        let calls = Calls()
        let h = host(calls)
        let entry = Entry(h)
        h.setEnabled(h.descriptors[0], true)
        h.stopAll()
        calls.log = []
        ModuleHost.shared.setEnabled(entry, true)
        XCTAssertEqual(calls.log, ["make", "activate"], "the subject did not happen first")
        ModuleHost.shared.setEnabled(entry, false)
        XCTAssertEqual(calls.log, ["make", "activate", "stop", "deactivate"])
        calls.log = []
        ModuleHost.shared.setEnabled(entry, true)
        XCTAssertEqual(calls.log, ["make", "activate"], "back on: not rebuilt, or built twice")
        XCTAssertEqual(h.live.count, 1)
        // off while the entry is on, then the entry off and on: stays off
        h.setEnabled(h.descriptors[0], false)
        ModuleHost.shared.setEnabled(entry, false)
        calls.log = []
        ModuleHost.shared.setEnabled(entry, true)
        XCTAssertEqual(calls.log, [], "a tweak switched off came back with the entry")
    }

    func testSwitchingATweakOnWhileTheEntryIsOffStartsItAnyway() {
        // The page is unreachable with the entry off, but the host itself has no such gate: pinned, not endorsed.
        let calls = Calls()
        let h = host(calls)
        h.setEnabled(h.descriptors[0], true)
        XCTAssertEqual(h.live.count, 1)
        h.stopAll()
    }

    // MARK: - Sidebar

    func testAStoredSidebarListingTheEntryTwiceAndATweakIdKeepsOneEntryAndNoTweak() throws {
        let id = TweaksDescriptor.id.rawValue
        let registry = SidebarLayoutStore.registry()
        let s = NamespacedStore.scratch()
        let util = SidebarLayout.Section(id: "a", seed: "utilities", name: nil,
                                         modules: [id, "tweak.display-corners", "display-corners", id])
        let other = SidebarLayout.Section(id: "b", seed: nil, name: "mine", modules: [id, "tweak.fake"])
        SidebarLayoutStore.write(SidebarLayout(sections: [util, other]), to: s)
        let all = SidebarLayoutStore.read(from: s, registry: registry).sections.flatMap(\.modules)
        XCTAssertEqual(all.filter { $0 == id }.count, 1, "the entry is drawn more than once")
        XCTAssertFalse(all.contains { $0.hasPrefix("tweak.") || $0 == "display-corners" }, "a tweak id became a row")
        XCTAssertEqual(Set(all), Set(registry.map(\.0)), "a registered entry was lost")
        XCTAssertEqual(all.count, registry.count)
        let first = SidebarLayoutStore.read(from: s, registry: registry).sections.first
        XCTAssertEqual(first?.modules.first, id, "the first placement is the one kept")
    }
}
