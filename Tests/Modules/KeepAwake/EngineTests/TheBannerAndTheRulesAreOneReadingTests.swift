import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The banner and the rules were two readings of one value, and in the migration
/// case they said opposite things.
///
/// `appTriggers` asked `store.string(autoAppRules)` — an `as? String` — got the
/// empty string for a value of the wrong type, read that as «nothing was ever
/// written» and fell back to migrating the older `autoApps` list.
/// `appRulesUnreadable` asked `store.object(autoAppRules)`, found something that
/// was not a string and answered yes. So a plist holding an *array* under the
/// rules key, on a Mac that also still has the legacy list — which is a
/// hand-edited file, a restored backup or a half-finished migration — got two
/// rules holding the Mac awake and a banner over them saying no app was holding
/// anything. Measured on that fixture: two rules honoured, «the stored app rules
/// could not be read; no app is holding sleep» in the log.
///
/// One reading now, `appRulesReading`, with the migration fallback inside it and
/// both accessors derived from it. Unreadable means **no rules and the banner**:
/// the module fails toward the Mac sleeping and says so, which is the honest pair
/// (and the path the size cap in `AppTriggerRules.readable` routes into).
final class TheBannerAndTheRulesAreOneReadingTests: XCTestCase {

    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!

    private let mail = "com.example.mail"
    private let render = "com.example.render"

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        settings = KeepAwakeSettings(store: store)
    }

    private func plant(_ key: String, _ value: Any) {
        backing.raw["module.keep-awake." + key] = value
    }

    /// The exact file: an array where the rules go, and the older key still full.
    private func aHalfFinishedMigration() {
        plant("autoAppRules", [mail, render])
        plant("autoApps", [mail, render])
    }

    // MARK: - The two answers may not disagree

    func testAWrongTypedRulesValueLeavesNoRulesToHonour() {
        aHalfFinishedMigration()

        XCTAssertTrue(settings.appRulesUnreadable, "precondition: the file really is unreadable")
        XCTAssertTrue(settings.appTriggers.isEmpty,
                      "\(settings.appTriggers.map(\.bundleID)) — the banner says no app is "
                      + "keeping the Mac awake and two rules are doing exactly that")
    }

    /// The same file through the engine, which is where it costs something: the
    /// Mac is held awake by rules the screen has just disowned.
    func testTheEngineHoldsNothingForAFileItHasDisowned() {
        aHalfFinishedMigration()
        let apps = FakeApps()
        apps.ids = [mail, render]
        let engine = KeepAwakeEngine(settings: settings, store: store,
                                     assertions: FakeAssertions(),
                                     displayInfo: FakeDisplayInfo(),
                                     displayObserver: FakeDisplayObserver(),
                                     power: FakePower(), apps: apps, pointer: FakePointer(),
                                     clamshell: FakeClamshell(), clock: FakeClock())

        engine.activate()

        XCTAssertFalse(engine.isActive,
                       "the module warned that no app rule could be read and then held the Mac "
                       + "awake on two of them")
        XCTAssertTrue(engine.holdingApps.isEmpty)
    }

    /// The promise stated as itself, over every shape of unreadable value: if the
    /// banner is drawn, there are no rules being honoured behind it. This is the
    /// one that would catch a third reader added later.
    func testAnUnreadableFileNeverHasRulesBehindTheBanner() {
        for value in [[mail] as Any, 42 as Any, Data() as Any, "{not rules at all" as Any] {
            backing.raw.removeValue(forKey: "module.keep-awake.autoAppRules")
            plant("autoAppRules", value)
            plant("autoApps", [mail, render])

            XCTAssertTrue(settings.appRulesUnreadable,
                          "precondition: \(type(of: value)) is not rules")
            XCTAssertTrue(settings.appTriggers.isEmpty,
                          "a \(type(of: value)) under the rules key, and \(settings.appTriggers.count) "
                          + "rules honoured under a banner saying none could be read")
        }
    }

    // MARK: - The controls, which the consolidation may not cost

    /// The migration itself. `autoApps` with no rules key at all is somebody
    /// updating from a version that only stored bundle ids, and their apps must
    /// go on holding the Mac.
    func testTheLegacyListStillMigrates() {
        plant("autoApps", [mail, render])

        XCTAssertEqual(settings.appTriggers.map(\.bundleID), [mail, render])
        XCTAssertFalse(settings.appRulesUnreadable, "an old file is not a broken one")
    }

    /// An empty string is «this key has been written and holds nothing», which is
    /// also a migration case: it is what the encoder never writes and a cleared
    /// value looks like.
    func testAnEmptyRulesStringStillMigrates() {
        plant("autoAppRules", "")
        plant("autoApps", [mail])

        XCTAssertEqual(settings.appTriggers.map(\.bundleID), [mail])
        XCTAssertFalse(settings.appRulesUnreadable)
    }

    /// Rules that read, with a legacy list beside them: the rules win and the
    /// old list is not appended to them.
    func testReadableRulesAreWhatIsHonoured() {
        plant("autoAppRules", AppTriggerRules.encode([AppTrigger(bundleID: render)]))
        plant("autoApps", [mail])

        XCTAssertEqual(settings.appTriggers.map(\.bundleID), [render])
        XCTAssertFalse(settings.appRulesUnreadable)
    }

    /// And «no apps chosen», which must never draw a banner: it is what every
    /// fresh install says.
    func testChoosingNoAppsIsNotABrokenFile() {
        XCTAssertTrue(settings.appTriggers.isEmpty)
        XCTAssertFalse(settings.appRulesUnreadable, "a store with no rules key is a fresh install")

        plant("autoAppRules", "[]")

        XCTAssertTrue(settings.appTriggers.isEmpty)
        XCTAssertFalse(settings.appRulesUnreadable)
    }
}
