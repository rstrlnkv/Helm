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
        KeepAwakeSettings.useTestSeal()
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

    override func tearDown() {
        KeepAwakeSettings.restoreLidSeal()
        super.tearDown()
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
        KeepAwakeSettings(store: store).setClamshellEnabled(true)
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
        KeepAwakeSettings(store: store).setClamshellEnabled(true)
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

    // MARK: - The one entrance the hotkey and the panel switch both use

    /// `toggleSession` had no test at all, and it is what `KeepAwakeCommand
    /// .toggle` runs — the global hotkey, and the switch at the top of the
    /// panel tile. Everything under it was covered and the door itself was not.
    func test_toggle_starts_a_session_at_the_default_duration() {
        store.set(25, for: "defaultDurationMinutes")

        engine.toggleSession()

        XCTAssertTrue(engine.isActive)
        let end = try? XCTUnwrap(engine.endDate)
        XCTAssertEqual(end.map { Int($0.timeIntervalSince(clock.now()) / 60) }, 25)
    }

    /// Zero minutes means "until I say otherwise", which is the shipped default
    /// — so the toggle must not invent a deadline for it.
    func test_toggle_with_the_shipped_default_starts_an_indefinite_session() {
        engine.toggleSession()

        XCTAssertTrue(engine.isActive)
        XCTAssertNil(engine.endDate)
    }

    func test_toggle_again_stops_the_session() {
        engine.toggleSession()
        XCTAssertTrue(engine.isActive, "precondition")

        engine.toggleSession()

        XCTAssertFalse(engine.isActive)
        XCTAssertFalse(assertions.held)
        XCTAssertNil(engine.endDate)
    }
}

/// Turning the module off has to take its observers with it.
///
/// `IOPSPowerInfo` hands IOKit an unretained pointer to itself and adds a run
/// loop source that nothing ever removed. `ModuleHost.disable` drops the
/// engine, the engine owns the port, the port deallocates — and the main run
/// loop still holds the source, so the next power event dereferences freed
/// memory. Unplug the charger after switching Keep Awake off.
///
/// The crash itself is not unit-testable; what is testable is the one thing
/// that prevents it, which is that the engine asks the port to stop.
final class PowerObserverTeardownTests: XCTestCase {

    func testDeactivateStopsWatchingThePowerSource() {
        let power = FakePower()
        let store = NamespacedStore(namespace: "keep-awake",
                                    backing: InMemoryKeyValueStore())
        let engine = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                     assertions: FakeAssertions(),
                                     displayInfo: FakeDisplayInfo(),
                                     displayObserver: FakeDisplayObserver(),
                                     power: power, apps: FakeApps(),
                                     pointer: FakePointer(), clamshell: FakeClamshell(),
                                     clock: FakeClock())
        engine.activate()
        XCTAssertTrue(power.observing, "the engine watches the power source while it is on")

        engine.deactivate()

        XCTAssertFalse(power.observing,
                       "the run loop still holds a source pointing at a port that is about "
                       + "to be freed")
    }
}

/// An observer started twice is not two observers.
///
/// `ScreenParamsObserver` kept no token and removed nothing, so every enable of
/// the module left another `didChangeScreenParameters` block registered for the
/// life of the process. `WorkspaceAppPort`, twenty lines below it in the same
/// file, holds its tokens and says why — "switching the module off and on
/// stacked another pair each time" — and the port protocol's comment claimed
/// `NotificationCenter` observers needed no such thing.
final class DisplayObserverStackingTests: XCTestCase {

    func testStartingTwiceLeavesOneObserver() {
        let observer = ScreenParamsObserver()
        let calls = Counter()
        observer.startObserving { calls.bump() }
        observer.startObserving { calls.bump() }

        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // The block runs on the main queue; drain it.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(calls.value, 1, "each enable of the module left another observer behind")
    }
}

/// A counter a `@Sendable` block may touch.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
