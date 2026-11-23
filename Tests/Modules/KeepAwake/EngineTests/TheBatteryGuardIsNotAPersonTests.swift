import HelmTestSupport
import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// What the battery guard leaves behind when it ends a session.
///
/// The guard is a floor the machine keeps, and it fires with nobody at the Mac
/// — that is the whole reason it exists, since `defaultDurationMinutes` ships
/// as «indefinitely» and nothing else ever ends an unattended session. It once
/// ended one through `stopSession()`, the person's own Stop button, which sets
/// `suppressed` («an automatic condition is true and is being ignored»), and
/// that lifts only when the *trigger* drops and comes back, so the charger
/// going in did nothing. It now vetoes while the charge is low: the veto is
/// recomputed on every power event, lifts by itself, and is published as
/// `batteryStopped`, which is what the screens draw the reason from.
final class TheBatteryGuardIsNotAPersonTests: XCTestCase {

    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var power: FakePower!
    private var apps: FakeApps!
    private var clock: FakeClock!
    private var assertions: FakeAssertions!
    private var engine: KeepAwakeEngine!

    private let render = "com.example.render"

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        settings = KeepAwakeSettings(store: store)
        settings.setAppTriggers([AppTrigger(bundleID: render)])
        power = FakePower()
        apps = FakeApps()
        apps.ids = [render]
        clock = FakeClock()
        assertions = FakeAssertions()
        engine = fakeEngine(settings: settings, store: store, assertions: assertions, power: power,
                            apps: apps, clock: clock)
    }

    private func onMains() {
        power.snap = (onBattery: false, percent: 100)
        power.says(.mains)
    }

    /// Under the shipped floor of 20%.
    private func onAFlatBattery() {
        power.snap = (onBattery: true, percent: 5)
        power.says(.battery)
    }

    /// The rule is holding the Mac and then the battery runs down.
    private func theGuardStopsTheRule() {
        onMains()
        engine.activate()
        XCTAssertTrue(engine.isActive, "precondition: the rule is holding the Mac")

        onAFlatBattery()
        power.fire()
        XCTAssertFalse(engine.isActive, "precondition: the guard ended it")
    }

    // MARK: - The guard's decision outlives the guard's own condition

    func testThePowerComingBackGivesTheRuleBack() {
        theGuardStopsTheRule()

        // The person plugs the charger in. The battery is no longer low, the
        // app the rule names never went anywhere, and nothing about the reason
        // the session ended is true any more.
        onMains()
        power.fire()

        XCTAssertTrue(engine.isActive,
                      "the app rule is silenced until the app quits and comes back, because "
                      + "the battery guard ended the session through the same verb a person "
                      + "does — the charger is in and the rule that applies is being ignored")
        XCTAssertTrue(assertions.held)
    }

    /// The same fact stated where a screen can see it: after the charger goes
    /// in, the panel and the page still draw «Automation paused» with a Resume
    /// button for a rule nobody paused.
    func testTheChargerGoingInClearsTheSuppression() {
        theGuardStopsTheRule()
        // The guard no longer suppresses at all — it vetoes while the charge is
        // low and the veto lifts by itself. The precondition here used to assert
        // the defect; what the test is about survives it.
        XCTAssertFalse(engine.suppressed,
                       "a flat battery is not a person saying stop, and `suppressed` is "
                       + "the flag that means one did")

        onMains()
        power.fire()

        XCTAssertFalse(engine.suppressed,
                       "«Automation paused» is offered with «Resume» for a decision the "
                       + "person never made and a condition that has passed")
    }

    /// The control, which the two above must not be able to pass without: a
    /// rule the *person* silenced stays silenced when the charger moves. That
    /// is what suppression is, and no fix to the guard may take it away.
    func testARuleThePersonStoppedStaysStoppedWhenTheChargerMoves() {
        onMains()
        engine.activate()
        XCTAssertTrue(engine.isActive, "precondition")

        engine.stopSession()
        XCTAssertTrue(engine.suppressed, "precondition: the person silenced the rule")
        onAFlatBattery()
        power.fire()
        onMains()
        power.fire()

        XCTAssertFalse(engine.isActive,
                       "the rule the person switched off came back because the charger moved")
        XCTAssertTrue(engine.suppressed)
    }

    /// And the other control: the guard really does end a session, so nothing
    /// above is passing because nothing ever happened.
    func testTheGuardEndsTheSessionAtAll() {
        onMains()
        engine.activate()
        XCTAssertTrue(assertions.held, "precondition")

        onAFlatBattery()
        power.fire()

        XCTAssertFalse(assertions.held, "the Mac is held awake at 5% with nobody there")
    }

    // MARK: - Every thirty seconds, for as long as it takes

    /// «Resume» on a Mac that is still at 5 %.
    ///
    /// This used to be a loop: the guard ended the session through the verb a
    /// person uses, «Resume» handed the Mac back, and thirty seconds later the
    /// same fuse burned down to the same decision — with a banner saying what
    /// it had said before the button was pressed. The veto has no fuse: while
    /// the charge is under the floor nothing holds the Mac, so pressing Resume
    /// changes nothing and says nothing new, which is the honest answer to a
    /// button that cannot do what it offers.
    ///
    /// The log line is the account of an unattended stop, so its count is
    /// asserted — an absence would pass here for free otherwise.
    func testResumeCannotOutrunAFlatBattery() {
        tailTheLog()

        theGuardStopsTheRule()
        engine.resumeAutomation()

        XCTAssertFalse(engine.isActive,
                       "the veto is recomputed, so Resume cannot hand the Mac back while "
                       + "the charge is still under the floor")
        XCTAssertEqual(guardLines(), 1,
                       "one stop, one line — the loop used to write a second one every "
                       + "thirty seconds for as long as somebody kept pressing Resume")
    }

    /// A session with no rule behind it — pressed by hand, at 5%, on the way to
    /// the door. The guard is consulted where the decision is made, so it is
    /// refused at once; `suppressed` stays false because no automatic condition
    /// holds, and `batteryStopped` is what tells the screens the battery is why.
    func testAHandStartedSessionAtFivePerCentIsRefusedAndTheBatteryIsSaidToBeWhy() {
        tailTheLog()

        settings.setAppTriggers([])
        apps.ids = []
        onAFlatBattery()
        engine.activate()
        engine.startSession(minutes: 0)

        XCTAssertFalse(engine.isActive,
                       "the guard is consulted where the decision is made now, so a session "
                       + "asked for at 5% is refused at once rather than holding the Mac "
                       + "until the watch ticks half a minute later")
        XCTAssertFalse(engine.suppressed,
                       "nothing was suppressed, so the paused banner is not the account")
        XCTAssertTrue(engine.batteryStopped,
                      "the battery is the reason, and the state the screens read says so")
        XCTAssertEqual(guardLines(), 1, "the log is the whole account")
    }

    // MARK: - A guard that stops nothing still says it stopped something

    /// `recompute` runs from the power observer, and the power observer
    /// fires on every change IOKit reports — each percentage step on a
    /// draining battery, each charging-state change. Nothing in it asks
    /// whether a session is running, so below the floor it writes
    /// «battery guard stopped the session at 5%» over and over for a session
    /// that does not exist, and calls `stopSession()` on a Mac that is not
    /// being held awake.
    ///
    /// The line is not decoration: it is the *only* account this module gives
    /// of an unattended session ending, and a trail that says it every few
    /// seconds when nothing happened is a trail nobody can read the real one
    /// out of. The house rule about the log being a product surface is the
    /// same rule.
    func testAGuardWithNoSessionToStopSaysNothing() {
        tailTheLog()

        settings.setAppTriggers([])
        apps.ids = []
        onAFlatBattery()
        engine.activate()
        XCTAssertFalse(engine.isActive, "precondition: nothing is holding the Mac")

        // Three percentage steps on the way down, with the module idle.
        power.fire()
        power.snap = (onBattery: true, percent: 4)
        power.fire()
        power.snap = (onBattery: true, percent: 3)
        power.fire()

        XCTAssertEqual(guardLines(), 0,
                       "the guard reported ending a session three times over, and there was "
                       + "no session — the one line that accounts for an unattended stop is "
                       + "written when nothing stopped")
    }

    /// The control for it, so «says nothing» cannot be satisfied by a guard
    /// that has stopped working: the same battery, with a session running,
    /// still writes exactly one line.
    func testTheGuardStillSpeaksWhenThereIsASessionToStop() {
        tailTheLog()

        settings.setAppTriggers([])
        apps.ids = []
        onMains()
        engine.activate()
        engine.startSession(minutes: 0)

        onAFlatBattery()
        power.fire()

        XCTAssertFalse(engine.isActive)
        XCTAssertEqual(guardLines(), 1)
    }

    private func guardLines() -> Int {
        HelmLog.shared.recentEntries()
            .filter { $0.category == KeepAwakeEngine.moduleID && $0.message.contains("battery guard") }
            .count
    }
}
