import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The setting end to end: a timed session started while an app rule is
/// already holding the Mac, and what is left when the timer runs out.
final class ATimerCanEndTheAutomationItSatOnTests: XCTestCase {
    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var apps: FakeApps!
    private var clock: FakeClock!
    private var assertions: FakeAssertions!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        apps = FakeApps()
        clock = FakeClock()
        assertions = FakeAssertions()
        apps.ids = ["com.example.render"]
        store.set(AppTriggerRules.encode([AppTrigger(bundleID: "com.example.render")]),
                  for: KeepAwakeSettings.Key.autoAppRules)
        engine = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                 assertions: assertions, displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(), power: FakePower(),
                                 apps: apps, pointer: FakePointer(),
                                 clamshell: FakeClamshell(), clock: clock)
    }

    /// Today's behaviour, which the setting must not change when it is off:
    /// the timer ends and the app goes on holding the Mac awake.
    func testWithTheSettingOffTheAppGoesOnHoldingTheMacAwake() {
        engine.activate()
        XCTAssertTrue(engine.isActive, "the rule alone should be holding it")
        engine.startSession(minutes: 30)
        clock.fire(after: 30 * 60)
        XCTAssertTrue(engine.isActive)
        XCTAssertTrue(engine.activeConditions.contains(.app))
    }

    func testWithTheSettingOnTheTimerEndsTheRuleToo() {
        store.set(true, for: KeepAwakeSettings.Key.timerEndsAutomation)
        engine.activate()
        engine.startSession(minutes: 30)
        clock.fire(after: 30 * 60)
        XCTAssertFalse(engine.isActive, "the timer was asked to end the automation as well")
        XCTAssertFalse(assertions.held)
        XCTAssertTrue(apps.ids.contains("com.example.render"),
                      "and the app has not gone anywhere — that is the point")
    }

    /// «Until the trigger fires again»: the app quitting and coming back is a
    /// new trigger, and it lifts the suppression.
    func testTheRuleHoldsAgainWhenTheAppComesBack() {
        store.set(true, for: KeepAwakeSettings.Key.timerEndsAutomation)
        engine.activate()
        engine.startSession(minutes: 30)
        clock.fire(after: 30 * 60)
        XCTAssertFalse(engine.isActive)

        apps.ids = []
        apps.fire()
        XCTAssertFalse(engine.isActive)

        apps.ids = ["com.example.render"]
        apps.fire()
        XCTAssertTrue(engine.isActive, "the trigger fired again")
    }

    /// A Mac that went to sleep with the rule's app still running is the one
    /// state this module cannot leave unexplained, so the state it publishes
    /// has to carry it.
    func testTheSuppressionIsPublished() {
        store.set(true, for: KeepAwakeSettings.Key.timerEndsAutomation)
        engine.activate()
        engine.startSession(minutes: 30)
        clock.fire(after: 30 * 60)
        XCTAssertTrue(engine.suppressed)
    }

    /// And `resumeAutomation` is the way back, without starting a session of
    /// its own: the rule takes over again because the rule was true all along.
    func testResumeAutomationGivesTheRuleBack() {
        store.set(true, for: KeepAwakeSettings.Key.timerEndsAutomation)
        engine.activate()
        engine.startSession(minutes: 30)
        clock.fire(after: 30 * 60)
        XCTAssertFalse(engine.isActive)

        engine.resumeAutomation()
        XCTAssertTrue(engine.isActive)
        XCTAssertTrue(engine.activeConditions.contains(.app))
        XCTAssertNil(engine.endDate, "resuming is not a new timed session")
    }
}
