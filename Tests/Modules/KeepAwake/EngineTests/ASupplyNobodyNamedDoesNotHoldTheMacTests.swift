import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// A power source the system will not name must not hold somebody's Mac awake.
///
/// The port's mains answer used to be a `Bool` folded out of the battery
/// reading: `guard let reading = current() else { return true }`. Two things
/// followed from that `true`, and they are opposite ends of the same defect.
///
/// `powerCondition()` read a source it could not read at all as **on** power and
/// started holding the Mac — against its own comment, which said nil for an
/// incomplete dictionary «still has to mean not-on-power, because ending a
/// session early is this module's safe failure». And
/// `BatteryGuard.shouldDeactivateWithNoReading(enabled:isOnMains:)`, whose whole
/// reason for being is the `!isOnMains` branch, could never take it: with no
/// reading the fold answered `true` every time, so the one thing that ever ends
/// an unattended session was unreachable on the path written for it. Its test
/// passed, because `FakePower` could plant a state the real port could not
/// produce.
///
/// So the port answers `PowerSource.Supply?` now — mains, battery, or nothing
/// named — and this module folds «nothing named» to not-on-mains. The scan folds
/// it the other way at its own call site, which is why the fold is not inside
/// the port (`PowerSource.isOnMains(_:)`).
///
/// The controls matter as much as the refusals: a named mains supply still holds
/// the Mac, on a laptop and on a desktop both, or these tests would pass on a
/// module whose power rule never fires at all.
final class ASupplyNobodyNamedDoesNotHoldTheMacTests: XCTestCase {

    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var power: FakePower!
    private var apps: FakeApps!
    private var displayInfo: FakeDisplayInfo!
    private var engine: KeepAwakeEngine!

    private let render = "com.example.render"

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        settings = KeepAwakeSettings(store: store)
        power = FakePower()
        apps = FakeApps()
        apps.ids = [render]
        displayInfo = FakeDisplayInfo()
        engine = KeepAwakeEngine(settings: settings, store: store,
                                 assertions: FakeAssertions(), displayInfo: displayInfo,
                                 displayObserver: FakeDisplayObserver(),
                                 power: power, apps: apps, pointer: FakePointer(),
                                 clamshell: FakeClamshell(), clock: FakeClock())
    }

    /// IOKit answered, and what it said was not a supply this app knows: a UPS,
    /// a dictionary with no state key, a string a later macOS invents. There is
    /// no capacity either, which is the ordinary companion of that.
    private func aSupplyNobodyNamed() {
        power.snap = nil
        power.says(nil)
    }

    private func aDesktopOnMains() {
        power.snap = nil
        power.says(.mains)
        displayInfo.flags = [false]
    }

    /// The rule tests below switch the floor off, and it is not tidying.
    ///
    /// `batteryVetoes` is a veto over *everything*, and with no charge and no
    /// named supply it fires on any Mac that has a battery — so on the machine
    /// this suite usually runs on, «the rule did not hold» would have been true
    /// whatever `powerCondition` decided. That is a test passing for a reason
    /// that has nothing to do with what it is about, and the control below is
    /// what caught it. With the floor off, the power fold is the only thing left
    /// that can refuse.
    private func withoutTheBatteryFloor() {
        store.set(false, for: KeepAwakeSettings.Key.batteryGuardEnabled)
    }

    // MARK: - The rule must not fire on a reading nobody has

    func testThePowerRuleDoesNotHoldTheMacOnAnUnnamedSupply() {
        withoutTheBatteryFloor()
        aSupplyNobodyNamed()
        store.set(true, for: KeepAwakeSettings.Key.autoPower)

        engine.activate()

        XCTAssertFalse(engine.isActive,
                       "the system would not say what is running this Mac and «keep awake while "
                       + "plugged in» took that for a yes — the engine's own comment says an "
                       + "unreadable source has to mean not-on-power")
        XCTAssertFalse(engine.activeConditions.contains(.power))
    }

    /// The control, and it is the half the fix may not cost: a desktop names its
    /// supply, so the rule that was dead on every desktop stays alive.
    func testThePowerRuleStillHoldsADesktopWhoseSupplyIsNamed() {
        withoutTheBatteryFloor()
        aDesktopOnMains()
        store.set(true, for: KeepAwakeSettings.Key.autoPower)

        engine.activate()

        XCTAssertTrue(engine.isActive)
        XCTAssertTrue(engine.activeConditions.contains(.power))
    }

    func testAnAppRuleNarrowedToPowerDoesNotHoldTheMacOnAnUnnamedSupply() {
        withoutTheBatteryFloor()
        aSupplyNobodyNamed()
        var trigger = AppTrigger(bundleID: render)
        trigger.set(.power)
        settings.setAppTriggers([trigger])

        engine.activate()

        XCTAssertFalse(engine.isActive,
                       "«only when plugged in» was satisfied by a supply nothing could name")
    }

    /// The same rule on the same unreadable supply, unqualified: it holds,
    /// because nothing about it asks a question the power source can answer.
    /// Without this the refusal above could be «app rules are broken».
    func testAnUnqualifiedAppRuleStillHoldsOnTheSameMac() {
        withoutTheBatteryFloor()
        aSupplyNobodyNamed()
        settings.setAppTriggers([AppTrigger(bundleID: render)])

        engine.activate()

        XCTAssertTrue(engine.isActive)
        XCTAssertTrue(engine.activeConditions.contains(.app))
    }

    // MARK: - And the guard the fold had made unreachable

    /// A laptop with an indefinite session, whose power source stops answering.
    /// `BatteryGuard.shouldDeactivateWithNoReading` is reached with a mains
    /// answer of *false* for the first time — in production it only ever got
    /// `true`.
    ///
    /// A Mac with a battery is the precondition (`batteryVetoes` opens on
    /// `MacHardware.hasBattery`), as it is for the two files this one sits
    /// beside.
    func testAnIndefiniteSessionEndsWhenNothingCanNameTheSupply() throws {
        try XCTSkipUnless(MacHardware.hasBattery,
                          "the veto is gated on this machine having a battery")
        engine.activate()
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.isActive, "precondition: the Mac is being held awake")

        aSupplyNobodyNamed()
        power.fire()

        XCTAssertFalse(engine.isActive,
                       "no charge, no named supply, and a session with no deadline: the floor is "
                       + "the only thing that ever ends one, and the fold to «on mains» is what "
                       + "switched it off")
        XCTAssertTrue(engine.batteryStopped, "and the screens say why")
    }

    /// The other side of the same guard, which the fold got right by accident: a
    /// desktop names mains, has no charge to read, and must keep its session.
    func testADesktopKeepsItsSessionWhenThereIsNoChargeToRead() {
        engine.activate()
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.isActive, "precondition")

        aDesktopOnMains()
        power.fire()

        XCTAssertTrue(engine.isActive,
                      "a Mac with no battery has nothing to run out of, and the guard has "
                      + "nothing to say about it")
        XCTAssertFalse(engine.batteryStopped)
    }
}
