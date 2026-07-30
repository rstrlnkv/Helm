import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// A session the person started, across the end of the process.
///
/// `endDate`, `startDate` and `manualOn` lived in engine memory and nowhere else,
/// so a two-hour Keep Awake was cancelled by anything that ended the process —
/// and the routine one is Helm's own silent updater, which calls
/// `NSApp.terminate(nil)` (`HelmApp/Installer.swift:44`) and has a detached script
/// swap the bundle and start it again. The IOKit assertion is per-process too, so
/// the Mac could sleep with the countdown gone from the menu bar and nothing
/// anywhere saying the session had been cut short.
///
/// The module already knew how to survive a relaunch, one field away:
/// `clamshellGuard` is written at the moment sleep is disabled and undone in
/// `activate()`, because that change outlives the process. It protected the
/// *system* from being left wrong and not the person's own request.
///
/// A relaunch is two engines over one store — which is what the module's own
/// `KeepAwakeEngineTests` already does for the clamshell recovery.
final class SessionSurvivesRelaunchTests: XCTestCase {

    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var clock: FakeClock!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        clock = FakeClock()
    }

    /// A second engine over the same store, as a relaunch gives.
    private func engine(assertions: FakeAssertions = FakeAssertions()) -> KeepAwakeEngine {
        KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                        assertions: assertions,
                        displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(),
                        power: FakePower(), apps: FakeApps(),
                        pointer: FakePointer(), clamshell: FakeClamshell(),
                        clock: clock)
    }

    // MARK: - It comes back

    func testATimedSessionComesBackAfterARelaunch() {
        let before = engine()
        before.startSession(minutes: 120)
        XCTAssertTrue(before.isActive, "precondition: the session is running")

        // Twenty minutes later the updater swaps the bundle and starts us again.
        clock.current = clock.current.addingTimeInterval(20 * 60)
        let assertions = FakeAssertions()
        let after = engine(assertions: assertions)
        after.activate()

        XCTAssertTrue(after.isActive, "the session the person asked for was dropped in silence")
        XCTAssertTrue(assertions.held, "and the Mac was left free to sleep")
        XCTAssertEqual(after.endDate, before.endDate,
                       "it must end when it was always going to end, not 120 minutes from now")
    }

    /// The countdown in the menu bar and the arc's proportion are both drawn from
    /// `startDate` (`KeepAwakeDescriptor.swift:61`), so a session that comes back
    /// without one comes back with no countdown.
    func testTheRestoredSessionKnowsWhenItBegan() {
        let before = engine()
        before.startSession(minutes: 90)
        let started = before.startDate

        clock.current = clock.current.addingTimeInterval(600)
        let after = engine()
        after.activate()

        XCTAssertEqual(after.startDate, started)
    }

    func testAnIndefiniteSessionComesBackToo() {
        let before = engine()
        before.startSession(minutes: 0)
        XCTAssertTrue(before.isActive, "precondition")
        XCTAssertNil(before.endDate, "precondition: no deadline")

        let after = engine()
        after.activate()

        XCTAssertTrue(after.isActive, "\"until I say stop\" does not mean \"until Helm restarts\"")
        XCTAssertNil(after.endDate)
    }

    /// The restored deadline is a deadline, not a duration: it still expires, and
    /// it expires at the remaining time rather than at the original.
    func testTheRestoredSessionStillExpires() {
        let before = engine()
        before.startSession(minutes: 60)
        clock.current = clock.current.addingTimeInterval(45 * 60)
        let after = engine()
        after.activate()
        XCTAssertTrue(after.isActive, "precondition: fifteen minutes left")

        clock.fire(after: 15 * 60)

        XCTAssertFalse(after.isActive, "the restored session never ended")
        XCTAssertNil(after.endDate)
    }

    // MARK: - It does not come back when it should not

    func testASessionWhoseDeadlinePassedWhileTheAppWasGoneStaysOver() {
        let before = engine()
        before.startSession(minutes: 30)

        // Gone for two hours: the thirty minutes ran out an hour and a half ago.
        clock.current = clock.current.addingTimeInterval(2 * 3600)
        let assertions = FakeAssertions()
        let after = engine(assertions: assertions)
        after.activate()

        XCTAssertFalse(after.isActive,
                       "the Mac was kept awake for a stretch nobody asked for")
        XCTAssertFalse(assertions.held)
        XCTAssertNil(after.endDate)
    }

    /// Stopping is a decision, and it has to outlive the process as firmly as
    /// starting does — otherwise the next launch resurrects what was switched off.
    func testASessionTheUserStoppedDoesNotComeBack() {
        let before = engine()
        before.startSession(minutes: 120)
        before.stopSession()
        XCTAssertFalse(before.isActive, "precondition")

        let after = engine()
        after.activate()

        XCTAssertFalse(after.isActive, "a stopped session came back from the store")
    }

    /// And an expiry that happened while the app was running clears the store on
    /// its way out, so the deadline cannot be found again by the next launch.
    func testASessionThatExpiredWhileRunningDoesNotComeBack() {
        let before = engine()
        before.startSession(minutes: 10)
        clock.fire(after: 10 * 60)
        XCTAssertFalse(before.isActive, "precondition: it expired")

        let after = engine()
        after.activate()

        XCTAssertFalse(after.isActive)
    }

    /// The control: none of the above may be satisfied by an engine that simply
    /// never activates a session.
    func testTheHarnessCanHoldASessionAtAll() {
        let assertions = FakeAssertions()
        let only = engine(assertions: assertions)
        only.startSession(minutes: 5)
        XCTAssertTrue(only.isActive)
        XCTAssertTrue(assertions.held)
    }
}
