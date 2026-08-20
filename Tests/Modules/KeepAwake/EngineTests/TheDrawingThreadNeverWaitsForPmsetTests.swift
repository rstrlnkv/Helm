import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The same shape as the keychain hang, one port over.
///
/// `PmsetClamshellPort`'s four methods are `HelmProcess.run(…)` — a child
/// process, waited for on the calling thread. Two facts make that a hang rather
/// than a few milliseconds:
///
/// - **No deadline.** `HelmProcess.run(_:_:env:)` calls `runData` with
///   `deadline: nil`, so the caller waits for as long as the child takes. The
///   bounded overload exists and this port does not use it.
/// - **Eight slots for the whole app.** `runData` takes `HelmProcess.slots`
///   (`launchCeiling` = 8) *around the whole run*, and every module shares them.
///   Homebrew's search is two `brew search` runs of about nine seconds each,
///   started per press of Return; while eight of those are out, the ninth
///   caller waits on the semaphore before it even spawns.
///
/// And every KeepAwake caller of that port is the thread that draws.
/// `activate()` is the host's module enable, at launch; `recompute()` runs from
/// the display, power and application observers, all of which deliver on main;
/// the transport handler wraps itself in `MainActor.run` on purpose. So a Mac
/// whose Homebrew page is busy can have its main thread parked inside
/// `ClamshellCoordinator`, at launch, before anything is drawn — which is the
/// arrangement `fix(settings): the thread that draws never waits for the
/// keychain` (4dcc5fb6) took out of `SettingGuard`.
///
/// These cases assert **where** the work happens, never how long it takes: the
/// call has to have happened before the thread is judged, or this is an
/// absence-passes-vacuously test of a port nobody asked anything.
final class TheDrawingThreadNeverWaitsForPmsetTests: XCTestCase {

    /// A clamshell port that answers like `FakeClamshell` and also records the
    /// thread each answer was given on. The real one can be called from any
    /// thread — `installSudoers` and `removeSudoers` already hand their answer
    /// back on a global queue — so «which thread asked» is a fact about the
    /// caller and not about the port.
    private final class RecordingClamshell: ClamshellPort, @unchecked Sendable {
        private let lock = NSLock()
        private var _asked: [(method: String, onMain: Bool)] = []
        /// Fulfilled the first time the named method is asked, so a case can
        /// wait for the work to have happened before judging where it happened.
        /// Behind the lock like everything else here: what this port is *for*
        /// is being asked from a thread other than the one that set it up.
        private var _onAsked: [String: XCTestExpectation] = [:]
        func fulfil(_ expectation: XCTestExpectation, whenAsked method: String) {
            lock.withLock { _onAsked[method] = expectation }
        }

        var pmset = "SleepDisabled 1"
        var grantExists = true
        /// A child process that has not finished yet. **A port that answers the
        /// instant it is asked cannot tell a caller that waits from one that
        /// does not** — the same reason a busy-gate test needs a runner that
        /// never exits. `HelmProcess.run` has no deadline and takes one of eight
        /// slots shared with `brew`, so «still running» is the ordinary state,
        /// not a contrived one.
        let stillRunning = DispatchSemaphore(value: 0)
        var blockUntilReleased = false

        var asked: [(method: String, onMain: Bool)] { lock.withLock { _asked } }
        func wasAskedOnMain(_ method: String) -> Bool {
            asked.contains { $0.method == method && $0.onMain }
        }
        func wasAsked(_ method: String) -> Bool { asked.contains { $0.method == method } }

        private func record(_ method: String) {
            let waiting: XCTestExpectation? = lock.withLock {
                _asked.append((method, Thread.isMainThread))
                return _onAsked[method]
            }
            waiting?.fulfill()
            // A turnstile rather than a single pass: one launch asks this port
            // three times, and a gate that let one through would leave the
            // others parked on a semaphore for the rest of the run.
            if blockUntilReleased { stillRunning.wait(); stillRunning.signal() }
        }

        func isSudoersInstalled() -> Bool { record("isSudoersInstalled"); return grantExists }
        func canDisableSleepWithoutPassword() -> Bool {
            record("canDisableSleepWithoutPassword")
            return grantExists
        }
        func installSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
            record("installSudoers")
            DispatchQueue.global().async { done(true) }
        }
        func removeSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
            record("removeSudoers")
            DispatchQueue.global().async { done(true) }
        }
        /// The free withdrawal — a child process like the rest, so it belongs on
        /// this list for the same reason.
        func removeSudoersWithoutPassword() -> Bool {
            record("removeSudoersWithoutPassword")
            grantExists = false
            return true
        }
        func setDisableSleep(_ on: Bool) -> Bool { record("setDisableSleep"); return grantExists }
        func pmsetReport() -> String { record("pmsetReport"); return pmset }
    }

    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var clamshell: RecordingClamshell!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        clamshell = RecordingClamshell()
    }

    override func tearDown() {
        backing = nil
        store = nil
        clamshell = nil
        super.tearDown()
    }

    private func engine(clock: FakeClock = FakeClock(),
                        apps: FakeApps = FakeApps(),
                        assertions: FakeAssertions = FakeAssertions()) -> KeepAwakeEngine {
        KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                        assertions: assertions,
                        displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(),
                        power: FakePower(), apps: apps,
                        pointer: FakePointer(), clamshell: clamshell,
                        clock: clock)
    }

    /// The control: with neither anchor, launch asks `pmset` nothing at all —
    /// which is what `recoverAtLaunch` is written for, and what makes the case
    /// below about a Mac that has used the lid option rather than about every
    /// Mac.
    func testALaunchWithNoAnchorShellsOutForNothing() {
        clamshell.grantExists = false
        engine().activate()

        XCTAssertFalse(clamshell.wasAsked("pmsetReport"),
                       "the recovery read `pmset -g` on a Mac that never used the option")
        XCTAssertFalse(clamshell.wasAsked("setDisableSleep"))
    }

    /// A Mac that *has* used it — which is every Mac the recovery exists for —
    /// reads `pmset -g` and then runs `sudo pmset disablesleep 0`, and both of
    /// those happen inside `activate()`, on the thread that called it.
    func testTheLaunchRecoveryDoesNotReadPmsetOnTheDrawingThread() {
        store.set(true, for: KeepAwakeSettings.Key.clamshellGuard)
        let read = expectation(description: "pmset -g was read")
        read.assertForOverFulfill = false
        clamshell.fulfil(read, whenAsked: "pmsetReport")

        engine().activate()

        // That it happened at all, and only then where. An absence asserted
        // about work that never ran is green on any code whatever.
        wait(for: [read], timeout: 2)
        XCTAssertFalse(clamshell.wasAskedOnMain("pmsetReport"),
                       "the read moved off the caller's stack and still runs on main")
    }

    /// The second half of the same launch: the restore itself is `sudo pmset
    /// disablesleep 0`, a second child process on the same thread.
    func testTheLaunchRecoveryDoesNotRunSudoOnTheDrawingThread() {
        store.set(true, for: KeepAwakeSettings.Key.clamshellGuard)
        let restored = expectation(description: "sleep was put back")
        restored.assertForOverFulfill = false
        clamshell.fulfil(restored, whenAsked: "setDisableSleep")

        engine().activate()

        wait(for: [restored], timeout: 2)
        XCTAssertFalse(clamshell.wasAskedOnMain("setDisableSleep"),
                       "`sudo pmset disablesleep 0` ran on the thread that draws")
    }

    /// The other half of «where», and the half a thread hop alone does not
    /// answer: `activate()` **waits** for the child.
    ///
    /// Told with a port that has not finished, because nothing else can tell a
    /// caller that waits from one that does not — a port answering instantly
    /// makes the question vacuous, and a bare «had it been asked yet?» after
    /// `activate()` returns is a race that a real fix loses about as often as
    /// it wins. Here the gate is not opened until the deadline has passed, so
    /// the only way to return in time is not to have waited.
    func testTheLaunchDoesNotWaitForTheChildProcessToFinish() {
        store.set(true, for: KeepAwakeSettings.Key.clamshellGuard)
        clamshell.blockUntilReleased = true
        let engine = engine()
        let returned = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            engine.activate()
            returned.signal()
        }
        let inTime = returned.wait(timeout: .now() + 2)
        // Whatever the answer, the port is let go before anything is judged:
        // a test that leaves a thread parked on a semaphore takes the run down
        // with it.
        clamshell.stillRunning.signal()
        // Only when it is still in there: the wait above consumes the signal
        // when it succeeds, and a second one would then sit out its own
        // deadline for nothing.
        if inTime == .timedOut { _ = returned.wait(timeout: .now() + 2) }

        XCTAssertEqual(inTime, .success,
                       "`activate()` did not return while `pmset` was still running — that is "
                       + "the thread the host enables modules on, at launch, waiting on a child "
                       + "process with no deadline behind a semaphore shared with `brew`")
    }

    /// And the ordinary running case, which is the one that repeats: an app the
    /// rules name launches, the engine recomputes on the main thread, and
    /// `engage` asks `sudo -n` whether it may disable sleep. Nobody pressed
    /// anything; the person is looking at some other app.
    func testARuleTakingHoldDoesNotAskSudoOnTheDrawingThread() throws {
        try XCTSkipUnless(MacHardware.hasLid,
                          "this Mac has no lid, so the lid is never engaged")
        store.set(true, for: KeepAwakeSettings.Key.clamshellEnabled)
        store.set(AppTriggerRules.encode([AppTrigger(bundleID: "com.example.render")]),
                  for: KeepAwakeSettings.Key.autoAppRules)
        let apps = FakeApps()
        apps.ids = ["com.example.render"]
        let asked = expectation(description: "sudo was asked whether it may disable sleep")
        asked.assertForOverFulfill = false
        clamshell.fulfil(asked, whenAsked: "canDisableSleepWithoutPassword")

        let engine = engine(apps: apps)
        engine.activate()

        wait(for: [asked], timeout: 2)
        XCTAssertFalse(clamshell.wasAskedOnMain("canDisableSleepWithoutPassword"),
                       "a watched app launching parks the thread that draws inside `sudo -n`")
    }
}
