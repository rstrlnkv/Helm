import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The rules ceilings guard one of the two readers, and the file can pick which
/// reader it goes to.
///
/// `AppTriggerRules.readable` refuses a value over `maxRules`, over
/// `maxBundleIDLength` or over `maxEncodedBytes` — deliberately refuses rather
/// than truncates, because a page drawing rules that hold nothing is the one
/// outcome nobody can see. `migrating(from:)` read the *older* key, mapped every
/// bundle id it found and answered with all of them: 50 001 rules and ids a
/// million characters long, on `recompute`'s path, which runs from three
/// observers.
///
/// And reaching it takes no cunning — an absent or empty `autoAppRules` is
/// exactly what an older file looks like, so the whole ceiling was one missing
/// key away from not existing.
final class AMigrationIsNotAWayPastTheCeilingsTests: XCTestCase {

    private func store() -> NamespacedStore {
        NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
    }

    // MARK: - The function

    func testTooManyIdsAreRefusedRatherThanMigrated() {
        let many = (0..<(AppTriggerRules.maxRules + 1)).map { "com.example.app\($0)" }
        XCTAssertNil(AppTriggerRules.migrating(from: many),
                     "the older key migrated more rules than this module will read from the "
                     + "current one")
    }

    func testAnIdLongerThanTheCeilingIsRefusedRatherThanMigrated() {
        let long = String(repeating: "a", count: AppTriggerRules.maxBundleIDLength + 1)
        XCTAssertNil(AppTriggerRules.migrating(from: [long]),
                     "a bundle id past the ceiling migrated intact")
    }

    /// The floor of the same rule: everything a person can actually have keeps
    /// migrating, or this guard has taken somebody's apps away.
    func testAnOrdinaryOlderListStillMigrates() {
        let rules = AppTriggerRules.migrating(from: ["com.apple.Safari", "com.microsoft.VSCode"])
        XCTAssertEqual(rules?.map(\.bundleID), ["com.apple.Safari", "com.microsoft.VSCode"])
        XCTAssertEqual(rules?.first?.condition, .always,
                       "the older key had no conditions, so every rule migrates as «always»")
    }

    /// The list at exactly the ceiling is legal — a refusal one short of the
    /// number the constant names would be an off-by-one nobody could see.
    func testTheCeilingItselfIsAllowed() {
        let exactly = (0..<AppTriggerRules.maxRules).map { "com.example.app\($0)" }
        XCTAssertEqual(AppTriggerRules.migrating(from: exactly)?.count, AppTriggerRules.maxRules)
    }

    /// **The third ceiling is not checked on this path, and that is arithmetic
    /// rather than an opinion.** `maxEncodedBytes` exists to refuse a value before
    /// `JSONDecoder` has paid for it, and there is nothing to decode here — the
    /// plist reader has already parsed the array. What makes its absence safe is
    /// that the two ceilings which *are* checked bound the encoded size to about
    /// half of it. Any of the three moving is the moment that stops being true.
    func testTheTwoCheckedCeilingsKeepTheThirdOutOfReach() throws {
        let widest = (0..<AppTriggerRules.maxRules).map { index in
            String(repeating: "a", count: AppTriggerRules.maxBundleIDLength - 4)
                + String(format: "%04d", index)
        }
        let rules = try XCTUnwrap(AppTriggerRules.migrating(from: widest),
                                  "the worst legitimate older file must still migrate")
        XCTAssertEqual(rules.count, AppTriggerRules.maxRules)
        XCTAssertEqual(rules[0].bundleID.count, AppTriggerRules.maxBundleIDLength)
        XCTAssertLessThanOrEqual(AppTriggerRules.encode(rules).utf8.count,
                                 AppTriggerRules.maxEncodedBytes,
                                 "the worst file the two checked ceilings allow encodes past the "
                                 + "third one, so the migration path needs its own byte check")
    }

    func testTheOlderKeyIsStillDeduplicated() {
        XCTAssertEqual(AppTriggerRules.migrating(from: ["a", "a", "b"])?.map(\.bundleID),
                       ["a", "b"])
    }

    // MARK: - Where the refusal has to arrive

    /// A refusal is only worth anything if it reaches the banner. Answering `[]`
    /// would be «no apps chosen» — the state a fresh install is in — and the
    /// person whose rules had just stopped working would see a page in perfect
    /// health.
    func testAnOverlongOlderListReachesTheBannerRatherThanReadingAsNoApps() {
        let s = store()
        s.set((0..<(AppTriggerRules.maxRules + 1)).map { "com.example.app\($0)" },
              for: KeepAwakeSettings.Key.autoApps)
        let settings = KeepAwakeSettings(store: s)
        XCTAssertTrue(settings.appRulesUnreadable,
                      "the file holds more rules than this module reads and the page says "
                      + "nothing about it")
        XCTAssertTrue(settings.appTriggers.isEmpty,
                      "and the engine holds none of them — the refusal fails toward the Mac "
                      + "sleeping, which is the direction this module fails in")
    }

    /// The control beside it: the ordinary older file still migrates through the
    /// same path, and the banner stays away.
    func testAnOrdinaryOlderFileMigratesWithNoBanner() {
        let s = store()
        s.set(["com.apple.Safari"], for: KeepAwakeSettings.Key.autoApps)
        let settings = KeepAwakeSettings(store: s)
        XCTAssertFalse(settings.appRulesUnreadable)
        XCTAssertEqual(settings.appTriggers.map(\.bundleID), ["com.apple.Safari"])
    }

    /// And an absent older key is not a refusal either: no apps chosen is a
    /// legitimate thing for a file to say, and a banner on every fresh install
    /// would be the worse fault.
    func testAnEmptyFileIsNotARefusal() {
        let settings = KeepAwakeSettings(store: store())
        XCTAssertFalse(settings.appRulesUnreadable)
        XCTAssertTrue(settings.appTriggers.isEmpty)
    }
}
