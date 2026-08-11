import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// No power reading at all, on a Mac that has a battery.
///
/// `power.snapshot()` is nil for two different reasons — a machine with no
/// battery, and an IOKit dictionary that came back incomplete — which is why
/// `PowerInfoPort` carries `isOnMains` separately; `powerCondition` and the app
/// rules were each dead on every desktop until it did. The battery guard was
/// left reading `snapshot()` alone and answering **no veto** for nil, so on a
/// laptop running on battery with an unreadable charge the one thing that ever
/// ends an unattended session was silently switched off. The floor exists
/// because `defaultDurationMinutes` ships as «indefinitely».
///
/// The two questions are separable and both are asked here: nil *and not on
/// mains* is battery power with an unknown charge, and this module's safe
/// failure is letting the Mac sleep. Nil *on mains* vetoes nothing — that is a
/// desktop, or a laptop that is plugged in, and refusing to hold it awake
/// because a dictionary was short would be the guard firing where it has no
/// business.
///
/// The second half of the file is the log line that accounts for it. It said
/// `percent ?? 0` — «battery guard stopped the session at 0%» — which is a
/// number nobody measured, in the only record of an unattended stop, and 0 % is
/// the reading that means the Mac is about to die.
///
/// A Mac with a battery is a precondition of the engine-level checks, as it is
/// for `TheBatteryGuardIsNotAPersonTests`: `batteryVetoes` opens on
/// `MacHardware.hasBattery`, which is a fact about this machine. The pure
/// decision below is asked of `BatteryGuard` directly and holds on any hardware.
final class AChargeNobodyCanReadIsNotZeroTests: XCTestCase {

    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var power: FakePower!
    private var apps: FakeApps!
    private var assertions: FakeAssertions!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        settings = KeepAwakeSettings(store: store)
        power = FakePower()
        apps = FakeApps()
        assertions = FakeAssertions()
        engine = KeepAwakeEngine(settings: settings, store: store, assertions: assertions,
                                 displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(),
                                 power: power, apps: apps, pointer: FakePointer(),
                                 clamshell: FakeClamshell(), clock: FakeClock())
    }

    /// IOKit answered, and the answer had nothing in it.
    private func withNoReading(onMains: Bool) {
        power.snap = nil
        power.onMains = onMains
    }

    // MARK: - The decision, where it has a test on any Mac

    func testNoReadingOnBatteryPowerStopsTheSession() {
        XCTAssertTrue(BatteryGuard.shouldDeactivateWithNoReading(enabled: true, isOnMains: false),
                      "the charge cannot be read and the Mac is not plugged in, so nothing "
                      + "knows how long it has left — and this module's safe failure is sleep")
    }

    func testNoReadingOnMainsStopsNothing() {
        XCTAssertFalse(BatteryGuard.shouldDeactivateWithNoReading(enabled: true, isOnMains: true),
                       "a desktop, or a laptop on the charger: there is no battery to run out "
                       + "and the guard has nothing to say")
    }

    func testAGuardThatIsSwitchedOffStopsNothingEither() {
        XCTAssertFalse(BatteryGuard.shouldDeactivateWithNoReading(enabled: false, isOnMains: false),
                       "the person switched the floor off, and an unreadable charge is not a "
                       + "reason to act as though they had not")
    }

    // MARK: - The engine acting on it

    func testASessionOnAnUnreadableBatteryIsStopped() {
        engine.activate()
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.isActive, "precondition: the Mac is being held awake")

        withNoReading(onMains: false)
        power.fire()

        XCTAssertFalse(engine.isActive,
                       "the charge is unreadable on battery power and the session goes on for "
                       + "ever — the floor is the only thing that ever ends an indefinite one")
        XCTAssertTrue(engine.batteryStopped, "and the screens say why")
    }

    /// The control, and it is the half the fix must not break.
    func testASessionOnAnUnreadableReadingWhilePluggedInIsLeftAlone() {
        engine.activate()
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.isActive, "precondition: the Mac is being held awake")

        withNoReading(onMains: true)
        power.fire()

        XCTAssertTrue(engine.isActive,
                      "an incomplete IOKit dictionary on a plugged-in Mac ended a session the "
                      + "person asked for, and nothing about a battery was true")
        XCTAssertFalse(engine.batteryStopped)
    }

    // MARK: - What the log says about a number it has not got

    func testTheLogDoesNotInventAChargeItCouldNotRead() throws {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()

        engine.activate()
        engine.startSession(minutes: 0)
        withNoReading(onMains: false)
        power.fire()

        // The subject first: an absence is trivially absent from a line nobody
        // wrote, and this whole check is about the wording of one line.
        let lines = guardLines()
        XCTAssertEqual(lines.count, 1, "precondition: the guard accounted for the stop once")
        let line = try XCTUnwrap(lines.first)
        // The charge, not the floor: the line carries the floor as a percentage
        // too, so a bare «0%» is in «floor 20%» whatever the reading was — the
        // first spelling of this check could not fail.
        XCTAssertFalse(line.contains("at 0%"),
                       "«\(line)» — the charge could not be read and the log names 0%, "
                       + "which is both a measurement nobody took and the one figure that "
                       + "means the Mac is about to go out")
    }

    /// The control for the line: a charge that *was* read is still in it, so the
    /// check above cannot be satisfied by a line that stopped carrying figures.
    func testTheLogStillNamesAChargeItDidRead() throws {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()

        engine.activate()
        engine.startSession(minutes: 0)
        power.snap = (onBattery: true, percent: 5)
        power.onMains = false
        power.fire()

        let lines = guardLines()
        XCTAssertEqual(lines.count, 1)
        let line = try XCTUnwrap(lines.first)
        XCTAssertTrue(line.contains("at 5%"), "«\(line)» has lost the reading it had")
    }

    private func guardLines() -> [String] {
        HelmLog.shared.recentEntries()
            .filter { $0.category == "keepawake" && $0.message.contains("battery guard") }
            .map(\.message)
    }
}
