import XCTest
@testable import Module_KeepAwake_Engine

/// An app can hold the Mac awake outright, or only when it is also plugged in
/// or driving an external display — "keep Final Cut awake, but only while I am
/// at the desk".
final class AppTriggerTests: XCTestCase {
    private let plain = AppTrigger(bundleID: "com.apple.FinalCut")
    private var needsDisplay: AppTrigger {
        AppTrigger(bundleID: "com.apple.FinalCut", needsExternalDisplay: true)
    }
    private var needsPower: AppTrigger {
        AppTrigger(bundleID: "com.apple.FinalCut", needsPower: true)
    }
    private var needsBoth: AppTrigger {
        AppTrigger(bundleID: "com.apple.FinalCut", needsExternalDisplay: true, needsPower: true)
    }

    // MARK: - Holding

    func testNoRulesNeverHold() {
        XCTAssertFalse(AppTriggerRules.isHolding([], running: ["com.apple.FinalCut"],
                                                 externalDisplay: true, onPower: true))
    }

    func testAppMustBeRunning() {
        XCTAssertFalse(AppTriggerRules.isHolding([plain], running: [],
                                                 externalDisplay: true, onPower: true))
    }

    func testUnqualifiedRuleHoldsWheneverTheAppRuns() {
        XCTAssertTrue(AppTriggerRules.isHolding([plain], running: ["com.apple.FinalCut"],
                                                externalDisplay: false, onPower: false))
    }

    func testDisplayQualifierIsRequired() {
        XCTAssertFalse(AppTriggerRules.isHolding([needsDisplay], running: ["com.apple.FinalCut"],
                                                 externalDisplay: false, onPower: true))
        XCTAssertTrue(AppTriggerRules.isHolding([needsDisplay], running: ["com.apple.FinalCut"],
                                               externalDisplay: true, onPower: false))
    }

    func testPowerQualifierIsRequired() {
        XCTAssertFalse(AppTriggerRules.isHolding([needsPower], running: ["com.apple.FinalCut"],
                                                 externalDisplay: true, onPower: false))
        XCTAssertTrue(AppTriggerRules.isHolding([needsPower], running: ["com.apple.FinalCut"],
                                               externalDisplay: false, onPower: true))
    }

    /// Both qualifiers on one rule mean both must hold, not either.
    func testBothQualifiersMustHold() {
        XCTAssertFalse(AppTriggerRules.isHolding([needsBoth], running: ["com.apple.FinalCut"],
                                                 externalDisplay: true, onPower: false))
        XCTAssertTrue(AppTriggerRules.isHolding([needsBoth], running: ["com.apple.FinalCut"],
                                               externalDisplay: true, onPower: true))
    }

    /// Rules are independent: one satisfied rule is enough.
    func testAnySatisfiedRuleHolds() {
        let rules = [needsDisplay, AppTrigger(bundleID: "com.apple.Xcode")]
        XCTAssertTrue(AppTriggerRules.isHolding(rules, running: ["com.apple.Xcode"],
                                               externalDisplay: false, onPower: false))
    }

    // MARK: - Storage

    func testRoundTrip() {
        let rules = [needsBoth, AppTrigger(bundleID: "com.apple.Xcode")]
        XCTAssertEqual(AppTriggerRules.decode(AppTriggerRules.encode(rules)), rules)
    }

    func testGarbageDecodesToNothing() {
        XCTAssertEqual(AppTriggerRules.decode("not json"), [])
        XCTAssertEqual(AppTriggerRules.decode(""), [])
    }

    /// Upgrading from the plain bundle-id list must not lose anyone's apps.
    func testMigrationFromThePlainList() {
        let migrated = AppTriggerRules.migrating(from: ["a", "b"])
        XCTAssertEqual(migrated, [AppTrigger(bundleID: "a"), AppTrigger(bundleID: "b")])
        XCTAssertFalse(migrated.contains { $0.needsExternalDisplay || $0.needsPower })
    }

    // MARK: - The four states one control offers

    func testConditionReadsBackFromTheFlags() {
        XCTAssertEqual(plain.condition, .always)
        XCTAssertEqual(needsDisplay.condition, .externalDisplay)
        XCTAssertEqual(needsPower.condition, .power)
        XCTAssertEqual(needsBoth.condition, .displayAndPower)
    }

    func testSettingAConditionRoundTrips() {
        for condition in AppTrigger.Condition.allCases {
            var trigger = AppTrigger(bundleID: "x")
            trigger.set(condition)
            XCTAssertEqual(trigger.condition, condition)
        }
    }

    /// Choosing "always" must clear both qualifiers, not leave one behind.
    func testAlwaysClearsEveryQualifier() {
        var trigger = needsBoth
        trigger.set(.always)
        XCTAssertFalse(trigger.needsExternalDisplay)
        XCTAssertFalse(trigger.needsPower)
    }
}
