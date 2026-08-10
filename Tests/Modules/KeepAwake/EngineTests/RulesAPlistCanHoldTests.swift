import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The rules, as a file can hold them rather than as the picker writes them.
///
/// `SettingsFromAPlistThatCanSayAnythingTests` covers the strings that are not
/// rules at all. These are strings that *are* rules and that the app's own
/// controls cannot produce: a bundle id repeated, a bundle id that is empty,
/// five hundred of them, and ids with the characters a bundle id may legally
/// contain. Two writers reach this key without the picker — a hand-edited
/// plist, and `AppTriggerRules.migrating(from:)`, which turns the older
/// `autoApps` string list into rules and does nothing about what is in it.
final class RulesAPlistCanHoldTests: XCTestCase {

    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        settings = KeepAwakeSettings(store: store)
    }

    private func plant(_ key: String, _ value: Any) {
        backing.raw["module.keep-awake." + key] = value
    }

    // MARK: - One rule per app

    /// `AppTrigger` is `Identifiable` with `id { bundleID }`, and the settings
    /// page draws the list as
    ///
    ///     ForEach(Array(appTriggers.enumerated()), id: \.element.bundleID)
    ///
    /// A repeated id there is not a cosmetic problem: SwiftUI says outright that
    /// duplicate ids in a `ForEach` give undefined results, and this is the list
    /// whose rows carry a per-row condition menu and a remove button that works
    /// by index. The rules also compose as an OR, so the second copy can only
    /// ever loosen the first — «only when plugged in» and «always» for one app
    /// means «always», drawn as two rows that disagree.
    ///
    /// The older key is the writer that makes this ordinary rather than exotic:
    /// `autoApps` is a plain `[String]`, and nothing between it and
    /// `migrating(from:)` has ever looked at it twice.
    func testTheSameAppTwiceComesBackAsOneRule() {
        plant("autoApps", ["com.apple.Safari", "com.apple.Safari"])

        let ids = settings.appTriggers.map(\.bundleID)

        XCTAssertEqual(ids.count, Set(ids).count,
                       "\(ids) — the page draws one row per bundle id and keys them by it")
    }

    /// The same through the current key, where the two copies disagree about
    /// when they apply. Whichever survives, there must be one row for one app.
    func testTwoRulesForOneAppComeBackAsOne() {
        let encoded = AppTriggerRules.encode([
            AppTrigger(bundleID: "com.example.render", needsPower: true),
            AppTrigger(bundleID: "com.example.render"),
        ])
        plant("autoAppRules", encoded)

        let ids = settings.appTriggers.map(\.bundleID)

        XCTAssertEqual(ids.count, Set(ids).count, "\(settings.appTriggers)")
    }

    /// The control: two rules for two apps are two rules, so nothing above can
    /// be satisfied by a reader that keeps one rule and drops the rest.
    func testTwoRulesForTwoAppsAreStillTwoRules() {
        plant("autoAppRules", AppTriggerRules.encode([
            AppTrigger(bundleID: "com.example.render"),
            AppTrigger(bundleID: "com.example.encode"),
        ]))

        XCTAssertEqual(settings.appTriggers.count, 2)
    }

    // MARK: - A rule that names nothing

    /// An empty bundle id is a rule that can never fire and a row with no name
    /// on the page. It must at least stay inert: nothing running can match it,
    /// and it must not become a rule that matches everything the day
    /// `isSatisfied` is written with a prefix or a contains.
    func testARuleWithAnEmptyBundleIDHoldsNothing() {
        let empty = [AppTrigger(bundleID: "")]

        XCTAssertFalse(AppTriggerRules.isHolding(empty, running: [],
                                                 externalDisplay: true, onPower: true))
        XCTAssertFalse(AppTriggerRules.isHolding(empty, running: ["com.apple.Safari"],
                                                 externalDisplay: true, onPower: true),
                       "a rule naming no app held the Mac awake for an app it does not name")
    }

    // MARK: - Ids as they are really spelled

    /// A bundle id is a string, and the ids in the wild carry hyphens, digits
    /// and — for anything shipped outside the ASCII world — worse. The store
    /// keeps them as JSON inside one string, so this is a guard on the day
    /// somebody makes that encoding cheaper by joining on a comma.
    func testAnIdWithSpacesEmojiOrCyrillicSurvivesTheRoundTrip() {
        let awkward = ["com.example.My App",
                       "com.example.приложение",
                       "com.example.🚀",
                       "com.example.a\tb",
                       "com.example.a,b",
                       ".hidden",
                       "com.example.a/b"]
        let rules = awkward.map { AppTrigger(bundleID: $0) }

        let back = AppTriggerRules.decode(AppTriggerRules.encode(rules))

        XCTAssertEqual(back.map(\.bundleID), awkward)
        XCTAssertTrue(AppTriggerRules.isHolding(back, running: ["com.example.🚀"],
                                                externalDisplay: false, onPower: false),
                      "an id that came back changed can never match a running app again")
    }

    // MARK: - Enormous

    /// Five hundred rules, with the only match at the end. Nothing about the
    /// module says a list has a length, and «the first N are read» is the shape
    /// of defect that hides in a list nobody makes by hand.
    func testTheFiveHundredthRuleStillHoldsTheMac() {
        var rules = (0..<499).map { AppTrigger(bundleID: "com.example.filler\($0)") }
        rules.append(AppTrigger(bundleID: "com.example.render"))
        plant("autoAppRules", AppTriggerRules.encode(rules))

        XCTAssertEqual(settings.appTriggers.count, 500)
        XCTAssertFalse(settings.appRulesUnreadable, "five hundred rules read as an unreadable file")
        XCTAssertTrue(AppTriggerRules.isHolding(settings.appTriggers,
                                                running: ["com.example.render"],
                                                externalDisplay: false, onPower: false))
    }

    /// And an engine over the same store answers the same, so the length is a
    /// fact about the module and not only about the decoder.
    func testAnEngineWithFiveHundredRulesStillHoldsTheMac() {
        var rules = (0..<499).map { AppTrigger(bundleID: "com.example.filler\($0)") }
        rules.append(AppTrigger(bundleID: "com.example.render"))
        plant("autoAppRules", AppTriggerRules.encode(rules))
        let apps = FakeApps()
        apps.ids = ["com.example.render"]
        let engine = KeepAwakeEngine(settings: settings, store: store,
                                     assertions: FakeAssertions(),
                                     displayInfo: FakeDisplayInfo(),
                                     displayObserver: FakeDisplayObserver(),
                                     power: FakePower(), apps: apps, pointer: FakePointer(),
                                     clamshell: FakeClamshell(), clock: FakeClock())

        engine.activate()

        XCTAssertTrue(engine.isActive)
        XCTAssertTrue(engine.activeConditions.contains(.app))
    }
}
