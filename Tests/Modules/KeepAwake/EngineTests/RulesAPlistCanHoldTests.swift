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

    /// A list at the module's ceiling, with the only match at the end. «The
    /// first N are read» is the shape of defect that hides in a list nobody makes
    /// by hand, and it is what these two are for.
    ///
    /// **This used to be five hundred, and the number moved for a reason.** The
    /// value is unbounded input read on every recompute — 4.7 MB of it decodes to
    /// 50 001 rules at 57 ms an event — so `AppTriggerRules.maxRules` refuses past
    /// 200 now and the refusal goes to the banner. What is asserted here is the
    /// half that must not change with it: everything up to the ceiling is read,
    /// and the last rule matters as much as the first
    /// (`AFileWithMoreRulesThanAnybodyChoseTests` holds both boundaries).
    func testTheTwoHundredthRuleStillHoldsTheMac() {
        var rules = (0..<199).map { AppTrigger(bundleID: "com.example.filler\($0)") }
        rules.append(AppTrigger(bundleID: "com.example.render"))
        plant("autoAppRules", AppTriggerRules.encode(rules))

        XCTAssertEqual(settings.appTriggers.count, 200)
        XCTAssertFalse(settings.appRulesUnreadable, "a list at the ceiling is not a broken file")
        XCTAssertTrue(AppTriggerRules.isHolding(settings.appTriggers,
                                                running: ["com.example.render"],
                                                externalDisplay: false, onPower: false))
    }

    /// And an engine over the same store answers the same, so the length is a
    /// fact about the module and not only about the decoder.
    func testAnEngineWithTwoHundredRulesStillHoldsTheMac() {
        var rules = (0..<199).map { AppTrigger(bundleID: "com.example.filler\($0)") }
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

    // MARK: - A value under the rules key that is not a string at all

    /// **The banner covers a rules *string* nothing can read, and not a rules
    /// *value* nothing can read.**
    ///
    /// `appRulesUnreadable` is `!encoded.isEmpty && readable(encoded) == nil`, and
    /// `encoded` comes from `store.string(…)` — an `as? String` over whatever the
    /// file holds. So a plist whose `autoAppRules` is an *array* answers with the
    /// empty string, which reads as «nothing was ever written»: every app rule is
    /// dead, the page draws its empty state, and the new banner says nothing. That
    /// is the exact silence the banner shipped to break, one plist type over.
    ///
    /// Not exotic, either. `autoApps` — the key this module still reads for
    /// migration — *is* a `[String]`, so an array under a rules key is what this
    /// app's own older format looks like; a hand edit, a restored backup or a
    /// half-finished migration all produce it.
    func testARulesValueThatIsNotAStringIsReportedAsUnreadable() {
        for value in [["com.apple.Safari"] as Any, 42 as Any, Data() as Any] {
            backing.raw.removeValue(forKey: "module.keep-awake.autoAppRules")
            plant("autoAppRules", value)

            // The subject: this really is a file with something under the rules
            // key, and no rule is being honoured.
            XCTAssertNotNil(backing.raw["module.keep-awake.autoAppRules"],
                            "precondition: the fixture wrote nothing")
            XCTAssertTrue(settings.appTriggers.isEmpty,
                          "precondition: \(type(of: value)) under the rules key holds nothing")

            XCTAssertTrue(settings.appRulesUnreadable,
                          "the file holds a \(type(of: value)) where the rules go, every app "
                          + "rule is dead, and the page reports «no apps chosen» — the same "
                          + "silence the banner exists to break")
        }
    }

    /// The controls, and they are the half a fix must not break: a store that has
    /// never held rules, and one that holds none *on purpose*, are not errors.
    /// «Unreadable» drawn for either of those is a banner on every fresh install.
    func testAnAbsentOrEmptyRulesValueIsNotAnError() {
        XCTAssertFalse(settings.appRulesUnreadable,
                       "a store with no rules key at all is a fresh install")

        plant("autoAppRules", "")
        XCTAssertFalse(settings.appRulesUnreadable, "an empty string is not a broken file")

        plant("autoAppRules", "[]")
        XCTAssertFalse(settings.appRulesUnreadable,
                       "«no apps chosen» is a legitimate thing for the file to say")

        plant("autoAppRules", "{not rules at all")
        XCTAssertTrue(settings.appRulesUnreadable,
                      "the flag no longer reports the case it was written for, so the check "
                      + "above passes for a flag that reports nothing")
    }
}
