import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The other half of «stopping is a decision too».
///
/// `SessionSurvivesRelaunchTests` proves a *manual* session survives the end of
/// the process in both directions: one that was running comes back, and one the
/// person stopped stays stopped. Its own words for the second are the ones this
/// file borrows — «otherwise the next launch resurrects what was switched off».
///
/// Pressing Stop while a rule is holding the Mac does something else, and it is
/// the case the log shows people actually reaching (`released` followed a minute
/// later by `automation resumed by hand`): the session ends **and the rule is
/// silenced**, which is the whole of `suppressed`. That flag is written nowhere.
/// `rememberSession()` stores `manualOn`, `sessionStartedAt` and `sessionEndsAt`
/// and nothing else, so the decision that reached the store is «no manual
/// session» — which was already true — while the decision the person actually
/// made is dropped on the floor.
///
/// The relaunch is not hypothetical: Helm's own silent updater terminates the
/// app and a detached script starts it again (`HelmApp/Installer.swift`), so a
/// rule paused at 14:00 is holding the Mac again by 14:05 with nobody having
/// touched anything. The screen agrees with the Mac and both are wrong about
/// what was asked for.
///
/// A relaunch is two engines over one store, which is the shape
/// `SessionSurvivesRelaunchTests` and `KeepAwakeEngineTests` both use.
final class APausedRuleSurvivesARelaunchTests: XCTestCase {

    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var clock: FakeClock!
    /// One set of running apps across both engines: the app the rule names is
    /// still running when the second one starts, because that is the case —
    /// the trigger has not dropped, so nothing has lifted the pause.
    private var apps: FakeApps!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        clock = FakeClock()
        apps = FakeApps()
        apps.ids = ["com.example.render"]
        store.set(AppTriggerRules.encode([AppTrigger(bundleID: "com.example.render")]),
                  for: KeepAwakeSettings.Key.autoAppRules)
    }

    override func tearDown() {
        backing = nil
        store = nil
        clock = nil
        apps = nil
        super.tearDown()
    }

    /// Every port named, so no construction can take a default that reaches the
    /// machine this runs on.
    private func engine(assertions: FakeAssertions = FakeAssertions()) -> KeepAwakeEngine {
        KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                        assertions: assertions,
                        displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(),
                        power: FakePower(), apps: apps,
                        pointer: FakePointer(), clamshell: FakeClamshell(),
                        clock: clock)
    }

    /// The control, first: without the pause the rule really does take the Mac
    /// back at the next launch. Every assertion below would pass on an engine
    /// that simply never holds anything, and this is what says it does.
    func testTheRuleHoldsTheMacAgainAfterARelaunchWhenNobodyPausedIt() {
        let assertions = FakeAssertions()
        let after = engine(assertions: assertions)
        after.activate()

        XCTAssertTrue(after.isActive, "the rule's app is running and nothing was paused")
        XCTAssertTrue(assertions.held)
    }

    /// Stop with a rule holding = pause the rule. The next launch must not undo
    /// it.
    func testARulePausedByHandIsStillPausedAfterARelaunch() {
        let before = engine()
        before.activate()
        XCTAssertTrue(before.isActive, "precondition: the rule is holding the Mac")

        before.stopSession()
        XCTAssertFalse(before.isActive, "precondition: Stop let the Mac sleep")
        XCTAssertTrue(before.suppressed,
                      "precondition: Stop silenced the rule rather than ending a session "
                      + "that was never started")

        // The updater swaps the bundle and starts us again. The app the rule
        // names never quit.
        let assertions = FakeAssertions()
        let after = engine(assertions: assertions)
        after.activate()

        XCTAssertTrue(after.suppressed,
                      "the pause was never written down, so nothing could restore it")
        XCTAssertFalse(after.isActive,
                       "a rule the person paused took the Mac back because Helm restarted")
        XCTAssertFalse(assertions.held, "and the Mac was held awake with nobody asking")
    }

    /// And the pause still means «until the trigger drops and comes back», which
    /// is the one thing that must lift it. Without this the fix could be «never
    /// hold again», which is a different defect wearing the same green tick.
    func testTheRestoredPauseStillLiftsWhenTheAppQuitsAndComesBack() {
        let before = engine()
        before.activate()
        before.stopSession()
        XCTAssertTrue(before.suppressed, "precondition")

        let after = engine()
        after.activate()
        // Asserted, not assumed: with no restored pause the rest of this test
        // is a rule holding a Mac and being asked to stop holding it, which
        // passes on the defect as readily as on the fix.
        XCTAssertTrue(after.suppressed, "precondition: the pause came back with the launch")

        // The trigger drops…
        apps.ids = []
        after.settingsChangedForTests()
        XCTAssertFalse(after.isActive, "precondition: nothing holds the Mac with the app gone")

        // …and comes back, which is what «until the rule applies again» means.
        apps.ids = ["com.example.render"]
        after.settingsChangedForTests()

        XCTAssertFalse(after.suppressed, "the pause outlived the trigger it was set against")
        XCTAssertTrue(after.isActive, "the rule never held the Mac again")
    }
}
