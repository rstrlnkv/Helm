import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

final class KeepAwakeEngineTests: XCTestCase {
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

    func test_startSession_indefinite_activates_and_prevents_sleep() {
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.isActive)
        XCTAssertTrue(assertions.held)
        XCTAssertEqual(assertions.lastDisplay, settings.keepDisplayOn)
    }

    func test_stopSession_releases() {
        engine.startSession(minutes: 0)
        engine.stopSession()
        XCTAssertFalse(engine.isActive)
        XCTAssertFalse(assertions.held)
    }

    func test_auto_external_display_activates_and_deactivates() {
        store.set(true, for: "autoExternalDisplay")
        displayInfo.flags = [true, false] // built-in + external
        engine.activate()
        XCTAssertTrue(engine.isActive)
        XCTAssertTrue(engine.activeConditions.contains(.externalDisplay))

        displayInfo.flags = [true] // external removed
        displayObserver.fire()
        XCTAssertFalse(engine.isActive)
    }

    func test_auto_power_activates_and_deactivates() {
        store.set(true, for: "autoPower")
        power.snap = (onBattery: false, percent: 100)
        engine.activate()
        XCTAssertTrue(engine.isActive)
        XCTAssertTrue(engine.activeConditions.contains(.power))

        power.snap = (onBattery: true, percent: 100)
        power.fire()
        XCTAssertFalse(engine.isActive)
    }

    func test_manual_off_suppresses_auto_until_conditions_clear() {
        store.set(true, for: "autoPower")
        power.snap = (onBattery: false, percent: 100)
        engine.activate()
        XCTAssertTrue(engine.isActive)

        engine.stopSession()
        XCTAssertFalse(engine.isActive) // suppressed even though auto condition still holds

        power.snap = (onBattery: true, percent: 100) // auto condition clears
        power.fire()
        XCTAssertFalse(engine.isActive) // still inactive; suppression cleared internally

        power.snap = (onBattery: false, percent: 100) // auto condition holds again
        power.fire()
        XCTAssertTrue(engine.isActive) // suppression was cleared, so auto re-activates
    }

    func test_clamshell_engage_and_disengage() {
        store.set(true, for: "clamshellEnabled")
        clamshell.sudoersInstalled = true

        engine.startSession(minutes: 0)
        XCTAssertEqual(clamshell.disableSleepCalls, [true])
        XCTAssertTrue(engine.clamshellActive)
        XCTAssertEqual(backing.raw["module.keep-awake.clamshellGuard"] as? Bool, true)

        engine.stopSession()
        XCTAssertEqual(clamshell.disableSleepCalls, [true, false])
        XCTAssertFalse(engine.clamshellActive)
        XCTAssertEqual(backing.raw["module.keep-awake.clamshellGuard"] as? Bool, false)
    }

    func test_clamshell_async_install_completing_after_stop_does_not_disable_sleep() {
        store.set(true, for: "clamshellEnabled")
        clamshell.sudoersInstalled = false // forces the async installSudoers path

        engine.activate()
        engine.startSession(minutes: 0)
        XCTAssertNotNil(clamshell.installCompletion, "install should have been requested")
        XCTAssertTrue(clamshell.disableSleepCalls.isEmpty, "must not disable sleep before install completes")

        engine.stopSession()

        // Sudoers install completes AFTER the session already ended.
        clamshell.installCompletion?(true)

        XCTAssertFalse(clamshell.disableSleepCalls.contains(true),
                        "must never disable sleep once the session has ended")
        XCTAssertFalse(engine.clamshellActive)
        XCTAssertFalse(store.bool("clamshellGuard", default: false))
    }

    func test_clamshell_recovery_on_activate() {
        store.set(true, for: "clamshellGuard")
        clamshell.pmset = "SleepDisabled 1"

        engine.activate()
        XCTAssertEqual(clamshell.disableSleepCalls, [false])
        XCTAssertEqual(backing.raw["module.keep-awake.clamshellGuard"] as? Bool, false)
    }

    func test_battery_guard_deactivates() {
        store.set(true, for: "batteryGuardEnabled")
        store.set(20, for: "batteryGuardPercent")
        engine.activate()
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.isActive)

        power.snap = (onBattery: true, percent: 15)
        power.fire()
        XCTAssertFalse(engine.isActive)
    }

    func test_timer_expiry_deactivates_with_no_auto_condition() {
        engine.startSession(minutes: 10)
        XCTAssertTrue(engine.isActive)

        clock.fire(after: 600)
        XCTAssertFalse(engine.isActive)
    }
}
