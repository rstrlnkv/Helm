import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// One press of Stop used to end two things: the session somebody started, and
/// any rule that was holding the Mac alongside it. The second half was never
/// asked for — it was inferred from a trigger being true.
///
/// The rule now is the person's whereabouts. **The timer switch is about being
/// away**: it runs out while you are asleep or out of the room, and the rules
/// stand down without you. **Stop is about being at the Mac**, so with that
/// switch on it hands the steps back — the first press ends the session and
/// leaves the rules running, the second ends the rules. With the switch off the
/// timer never touches the rules, there is nothing for a second step to mean,
/// and Stop stays the one press it has always been.
///
/// The half this file exists to hold down is the second one in the brief: the
/// step is **derived from what is true**, never stored. Nothing in here plants
/// a flag and nothing waits for one to expire; every case below changes the
/// world between the two presses and reads what the next press does.
final class TheSecondPressIsWhatEndsTheRulesTests: XCTestCase {
    private let render = "com.example.render"
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
        apps.ids = [render]
        clock = FakeClock()
        assertions = FakeAssertions()
        store.set(AppTriggerRules.encode([AppTrigger(bundleID: render)]),
                  for: KeepAwakeSettings.Key.autoAppRules)
        engine = makeEngine()
    }

    private func makeEngine() -> KeepAwakeEngine {
        KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                        assertions: assertions, displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(), power: FakePower(),
                        apps: apps, pointer: FakePointer(),
                        clamshell: FakeClamshell(), clock: clock)
    }

    private func timerEndsAutomation(_ on: Bool) {
        store.set(on, for: KeepAwakeSettings.Key.timerEndsAutomation)
    }

    // MARK: - The decision itself

    /// Three inputs, and every one of them is read at the moment of the press.
    func testWithTheSwitchOffOnePressEndsEverythingWhateverElseIsTrue() {
        for sessionRunning in [true, false] {
            for ruleHolds in [true, false] {
                XCTAssertEqual(StopPress.next(sessionRunning: sessionRunning,
                                              ruleHolds: ruleHolds,
                                              timerEndsAutomation: false),
                               .stopEverything,
                               "session \(sessionRunning), rule \(ruleHolds)")
            }
        }
    }

    /// With the switch on and a rule holding, the press that ends a session and
    /// the press that ends the rules are two different presses.
    func testWithTheSwitchOnTheSessionAndTheRulesAreTwoPresses() {
        XCTAssertEqual(StopPress.next(sessionRunning: true, ruleHolds: true,
                                      timerEndsAutomation: true),
                       .stopSessionOnly)
        XCTAssertEqual(StopPress.next(sessionRunning: false, ruleHolds: true,
                                      timerEndsAutomation: true),
                       .turnAutomationOff)
    }

    /// No rule is holding, so there is no second half to hand back and the
    /// switch changes nothing. Without this the button would rename itself on a
    /// page where nothing it names exists.
    func testWithNoRuleHoldingTheSwitchChangesNothing() {
        XCTAssertEqual(StopPress.next(sessionRunning: true, ruleHolds: false,
                                      timerEndsAutomation: true),
                       .stopEverything)
        XCTAssertEqual(StopPress.next(sessionRunning: false, ruleHolds: false,
                                      timerEndsAutomation: true),
                       .stopEverything)
    }

    // MARK: - The engine acts on it

    func testTheFirstPressEndsTheSessionAndLeavesTheRuleHolding() {
        timerEndsAutomation(true)
        engine.activate()
        engine.startSession(minutes: 30)
        XCTAssertTrue(engine.activeConditions.contains(.manual), "precondition")

        engine.stopSession()

        XCTAssertNil(engine.endDate, "the timer is what the first press ends")
        XCTAssertFalse(engine.activeConditions.contains(.manual))
        XCTAssertFalse(engine.suppressed,
                       "the first press decided for the person that their rule was over too")
        XCTAssertTrue(engine.isActive, "the app rule is still true, so the Mac is still held")
        XCTAssertTrue(assertions.held)
    }

    func testTheSecondPressEndsTheRule() {
        timerEndsAutomation(true)
        engine.activate()
        engine.startSession(minutes: 30)
        engine.stopSession()

        engine.stopSession()

        XCTAssertTrue(engine.suppressed)
        XCTAssertFalse(engine.isActive)
        XCTAssertFalse(assertions.held)
    }

    /// The control the two above need: with the switch off nothing is handed
    /// back, and one press still does both halves. A second step here would be
    /// symmetry for its own sake and one more thing to remember.
    func testWithTheSwitchOffOnePressStillDoesBoth() {
        engine.activate()
        engine.startSession(minutes: 30)

        engine.stopSession()

        XCTAssertTrue(engine.suppressed)
        XCTAssertFalse(engine.isActive)
    }

    // MARK: - The world between the two presses

    /// The rule the second press was aimed at has gone. Nothing is armed, so
    /// there is nothing to fire at what is left.
    func testARuleThatDropsBetweenThePressesTakesTheSecondStepWithIt() {
        timerEndsAutomation(true)
        engine.activate()
        engine.startSession(minutes: 30)
        engine.stopSession()

        apps.ids = []
        apps.fire()

        XCTAssertFalse(engine.isActive, "the app quit; nothing is holding the Mac")
        XCTAssertFalse(engine.suppressed, "and nothing was paused, because nothing applies")

        engine.stopSession()
        XCTAssertFalse(engine.suppressed,
                       "a press with no rule holding must not leave a pause behind for the "
                       + "next time the app is launched")
    }

    /// A rule that fires *between* the presses is a rule the second press ends,
    /// which is only true because the press asks the world rather than a flag
    /// written when the first press happened.
    func testARuleThatFiresBetweenThePressesIsEndedByTheSecondOne() {
        timerEndsAutomation(true)
        store.set(true, for: KeepAwakeSettings.Key.autoPower)
        engine.activate()
        engine.startSession(minutes: 30)
        engine.stopSession()

        apps.ids = []
        apps.fire()
        XCTAssertTrue(engine.isActive, "precondition: the charger is holding it now")

        engine.stopSession()

        XCTAssertTrue(engine.suppressed)
        XCTAssertFalse(engine.isActive)
    }

    /// Starting another session between the presses puts the person back at the
    /// first step, because a session is exactly what the first step ends.
    func testAFreshSessionBetweenThePressesIsTheFirstStepAgain() {
        timerEndsAutomation(true)
        engine.activate()
        engine.startSession(minutes: 30)
        engine.stopSession()

        engine.startSession(minutes: 15)
        engine.stopSession()

        XCTAssertFalse(engine.suppressed, "this press ended the new session, not the rule")
        XCTAssertTrue(engine.isActive)
    }

    /// **The timer keeps its own promise.** It is the control for being away,
    /// so when it runs out it does both halves in one act — there is nobody
    /// there to press anything a second time.
    func testATimerRunningOutStillEndsTheRuleByItself() {
        timerEndsAutomation(true)
        engine.activate()
        engine.startSession(minutes: 30)

        clock.fire(after: 30 * 60)

        XCTAssertTrue(engine.suppressed, "nobody is at the Mac to take a second step")
        XCTAssertFalse(engine.isActive)
    }

    /// The one gesture that has to be able to undo itself is not a sequence:
    /// ⌥⌘K and the panel's own switch read as on/off, and a switch that needed
    /// pressing twice to go off would spring back once in front of the reader.
    func testTheOneGestureToggleStaysAllOrNothing() {
        timerEndsAutomation(true)
        engine.activate()
        engine.startSession(minutes: 30)

        engine.toggleSession()

        XCTAssertTrue(engine.suppressed)
        XCTAssertFalse(engine.isActive)
    }

    /// **Nothing survives the process, because there is nothing to survive.**
    /// A stored «the first press has happened» would come back from disk and
    /// turn an ordinary Stop into one that switches off somebody's automation.
    /// What comes back instead is the world: a rule holding and no session, and
    /// that state is the second step wherever it is met.
    func testARelaunchBetweenThePressesRemembersNoStep() {
        timerEndsAutomation(true)
        engine.activate()
        engine.startSession(minutes: 30)
        engine.stopSession()
        engine.deactivate()

        let after = makeEngine()
        after.activate()
        XCTAssertTrue(after.isActive, "the rule is still holding after the relaunch")
        XCTAssertFalse(after.suppressed)

        after.stopSession()
        XCTAssertTrue(after.suppressed, "the state is read, not remembered")
    }
}
