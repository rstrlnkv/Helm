import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// «Only when plugged in», on a Mac that has no battery to be plugged in for.
///
/// The power rule was dead on every desktop Mac, and the fix has shipped:
/// `snapshot()` is nil for two different reasons — no battery at all, and an
/// IOKit dictionary that came back incomplete — and reading them as one made
/// «keep awake on power» never fire on a mini, a Studio or an iMac. The port
/// grew `isOnMains` for the other question, `powerCondition()` reads it, and
/// `FakePower.says(_:)` exists so a test can be a desktop.
///
/// The commit that did it says, of the same defect, "taking **every app rule
/// narrowed to `.power`** with it", and the engine's own comment beside
/// `powerCondition` repeats the claim. `appCondition()`, ten lines below, still
/// spells the old reading:
///
///     onPower: power.snapshot().map { !$0.onBattery } ?? false
///
/// So on a desktop a rule saying «keep the Mac awake while Final Cut is running,
/// but only when it is plugged in» is nil-mapped to `false` and can never fire —
/// the half of the fix that was described and not made. One rewrite, two call
/// sites, one of them changed.
///
/// The controls below matter as much as the failures: a plain power rule and an
/// unqualified app rule both hold on this same desktop, and the same qualified
/// rule holds on a laptop with the charger in. So «the rule never fires» cannot
/// be what these tests are measuring.
final class AnAppRuleOnPowerWithNoBatteryTests: XCTestCase {

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
                                 assertions: FakeAssertions(),
                                 displayInfo: displayInfo,
                                 displayObserver: FakeDisplayObserver(),
                                 power: power, apps: apps,
                                 pointer: FakePointer(), clamshell: FakeClamshell(),
                                 clock: FakeClock())
    }

    /// A Mac Studio: no power source list at all, so `snapshot()` answers nil,
    /// and mains is the only power there is. This is the combination the port's
    /// own doc comment was written for.
    private func aMacWithNoBattery() {
        power.snap = nil
        power.says(.mains)
        // One display, and it is not built-in — which is what a desktop reports.
        displayInfo.flags = [false]
    }

    /// A laptop with the charger in: both readings agree, which is why the
    /// defect never showed up on the machine it was written on.
    private func aLaptopOnMains() {
        power.snap = (onBattery: false, percent: 100)
        power.says(.mains)
        displayInfo.flags = [true]
    }

    private func aLaptopOnBattery() {
        power.snap = (onBattery: true, percent: 80)
        power.says(.battery)
        displayInfo.flags = [true]
    }

    private func rule(_ condition: AppTrigger.Condition) {
        var trigger = AppTrigger(bundleID: render)
        trigger.set(condition)
        settings.setAppTriggers([trigger])
    }

    // MARK: - The controls, first

    /// The half of the fix that was made. Without this the failures below would
    /// only be saying that the fake cannot be a desktop.
    func testThePlainPowerRuleHoldsOnAMacWithNoBattery() {
        aMacWithNoBattery()
        store.set(true, for: KeepAwakeSettings.Key.autoPower)

        engine.activate()

        XCTAssertTrue(engine.isActive)
        XCTAssertTrue(engine.activeConditions.contains(.power),
                      "the shipped fix: nil from snapshot() is not «on battery»")
    }

    /// An app rule with no qualifier on the same machine. So «app rules do not
    /// work on a desktop» is not what the failures below are measuring either.
    func testAnUnqualifiedAppRuleHoldsOnTheSameMac() {
        aMacWithNoBattery()
        rule(.always)

        engine.activate()

        XCTAssertTrue(engine.isActive)
        XCTAssertTrue(engine.activeConditions.contains(.app))
    }

    /// And the qualified rule on a laptop, where the two readings agree.
    func testTheQualifiedRuleHoldsOnALaptopWithTheChargerIn() {
        aLaptopOnMains()
        rule(.power)

        engine.activate()

        XCTAssertTrue(engine.isActive)
        XCTAssertTrue(engine.activeConditions.contains(.app))
    }

    /// The safe direction, which no fix may cost: «only when plugged in» must
    /// still mean nothing on battery, or the qualifier is decoration.
    func testTheQualifiedRuleDoesNotHoldOnALaptopOnBattery() {
        aLaptopOnBattery()
        rule(.power)

        engine.activate()

        XCTAssertFalse(engine.isActive,
                       "a rule narrowed to «only on power» held a Mac running on its battery")
    }

    // MARK: - The half that was described and not made

    func testAnAppRuleNarrowedToPowerHoldsOnAMacWithNoBattery() {
        aMacWithNoBattery()
        rule(.power)

        engine.activate()

        XCTAssertTrue(engine.isActive,
                      "«only when plugged in» is dead on a Mac that is only ever plugged in — "
                      + "appCondition still reads snapshot(), which is nil where there is no "
                      + "battery, and maps that to «on battery»")
        XCTAssertTrue(engine.activeConditions.contains(.app))
    }

    /// The same reading, through the rule that needs both halves. The display
    /// half is satisfied on a desktop (`ExternalDisplaySupport` reads a list
    /// with no built-in as «yes», deliberately), so the power half is the only
    /// thing that can be refusing.
    func testAnAppRuleNarrowedToDisplayAndPowerHoldsOnAMacWithNoBattery() {
        aMacWithNoBattery()
        rule(.displayAndPower)

        engine.activate()

        XCTAssertTrue(engine.isActive,
                      "the display half of this rule is satisfied on a desktop and the power "
                      + "half is answered from the nil reading")
    }

    /// A charger event on a desktop is not an event at all, so the rule has to
    /// be right at the first recompute — but the observer path is the one a
    /// person meets when they launch the app before the rule's app, and it
    /// reads the same two functions.
    func testTheRuleIsStillDeadWhenTheAppArrivesLater() {
        aMacWithNoBattery()
        rule(.power)
        apps.ids = []
        engine.activate()
        XCTAssertFalse(engine.isActive, "precondition: the app is not running yet")

        apps.ids = [render]
        apps.fire()

        XCTAssertTrue(engine.isActive,
                      "the app the rule names has started and the Mac is on mains — "
                      + "there is nothing left for the rule to be waiting for")
    }
}
