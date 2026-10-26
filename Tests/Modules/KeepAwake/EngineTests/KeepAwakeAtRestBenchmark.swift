import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// What `KeepAwakeEngine` does per minute while nothing is happening.
final class KeepAwakeAtRestBenchmark: XCTestCase {
    var backing: InMemoryKeyValueStore!
    var store: NamespacedStore!
    var settings: KeepAwakeSettings!
    var assertions: FakeAssertions!
    var displayInfo: FakeDisplayInfo!
    var displayObserver: FakeDisplayObserver!
    var power: FakePower!
    var apps: FakeApps!
    var pointer: FakePointer!
    var clamshell: FakeClamshell!
    var clock: FakeClock!
    var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        settings = KeepAwakeSettings(store: store)
        assertions = FakeAssertions()
        displayInfo = FakeDisplayInfo()
        displayObserver = FakeDisplayObserver()
        power = FakePower()
        apps = FakeApps()
        pointer = FakePointer()
        clamshell = FakeClamshell()
        clock = FakeClock()
        engine = KeepAwakeEngine(settings: settings, store: store, assertions: assertions,
                                  displayInfo: displayInfo, displayObserver: displayObserver,
                                  power: power, apps: apps, pointer: pointer,
                                  clamshell: clamshell, clock: clock)
    }

    // MARK: - 1. Is anything armed with no session and no rule?

    /// `activate()` with every automation rule off and no session running —
    /// the state a Keep Awake install with nothing configured sits in for
    /// however long the Mac stays up. `FakeClock.schedule` records every timer
    /// the engine asks for; none of the three (`scheduleExpiry`,
    /// `scheduleJiggle`, `scheduleBatteryWatch`) should fire from `activate()`
    /// alone; a background scan gate elsewhere in this house
    /// (`ScanRoot`/`WatchScope`) is exactly the shape a poll here would take,
    /// and this module has none — its three observers are edge-triggered
    /// (`NSApplication.didChangeScreenParametersNotification`, an IOKit power
    /// callback, `NSWorkspace` launch/terminate). This is a fact about the
    /// engine's own logic, not the machine. It fails the moment a rewrite adds a
    /// polling timer at rest.
    func testActivateWithNothingConfiguredSchedulesNoTimer() {
        engine.activate()
        XCTAssertEqual(clock.scheduledCount, 0,
                       "activate() with no session and no automation rule armed a timer — "
                       + "something is now polling at rest")
    }

    /// The same, once a rule is configured but not yet satisfied: the engine
    /// still has nothing to count down, so nothing should be scheduled until a
    /// condition actually holds.
    func testAnUnsatisfiedRuleSchedulesNoTimerEither() {
        store.set(true, for: "autoExternalDisplay")
        displayInfo.flags = [true] // built-in only — no external display
        engine.activate()
        XCTAssertEqual(clock.scheduledCount, 0,
                       "a configured-but-unmet rule armed a timer while nothing is holding sleep")
    }

    /// A session with no deadline (`startSession(minutes: 0)`) still schedules
    /// the battery watch — that one is real, level-triggered work, checking a
    /// number every 30 s while a session that could run unattended for hours is
    /// live. Recorded here as the true positive the two tests above are
    /// contrasted against: this file is not asserting "nothing is ever
    /// scheduled", only that nothing is scheduled for no reason.
    func testAnIndefiniteSessionDoesScheduleTheBatteryWatch() {
        engine.startSession(minutes: 0)
        XCTAssertGreaterThan(clock.scheduledCount, 0,
                             "an indefinite session should arm the battery guard")
    }

    // MARK: - 2. AppTriggerRules.decode: how often

    /// `KeepAwakeSettings.appTriggers` is a computed property — it decodes the
    /// stored JSON on every read, with nothing cached between calls, and
    /// `appCondition()` reads it once per `recompute()`. `recompute()` runs from
    /// every one of the three observer callbacks, including `apps` firing for
    /// *any* app launching or quitting — not only a watched one. This does not
    /// count decode calls directly (nothing in the engine exposes that without
    /// a fake standing in for `AppTriggerRules` itself, which would be simpler
    /// than the thing it replaces and prove nothing about the real path); it
    /// fires the real observer three times in a row on an app that is already
    /// running and checks the real settings type answers correctly each time —
    /// proof `appCondition()` re-reads and re-decodes rather than caching a
    /// first answer.
    func testAppConditionReEvaluatesOnEveryAppEvent() {
        let triggers = (0..<5).map { AppTrigger(bundleID: "com.example.app\($0)") }
        settings.setAppTriggers(triggers)
        apps.ids = ["com.example.app0"]
        engine.activate() // wires `apps.startObserving`, which `apps.fire()` needs

        for _ in 0..<3 { apps.fire() }
        XCTAssertTrue(engine.activeConditions.contains(.app))

        // And the reverse: the same observer, the same settings, answering
        // "no" the moment the running set changes — which only a *repeated*
        // decode (not one cached from the first `fire()`) can do.
        apps.ids = []
        apps.fire()
        XCTAssertFalse(engine.activeConditions.contains(.app),
                       "the app condition did not track a change after its first read — "
                       + "something cached the first decode")
    }
}
