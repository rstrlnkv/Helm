import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The one thing this module does that outlives its own process.
///
/// «Stay awake with the lid closed» is `sudo pmset disablesleep 1` — a
/// system-wide setting, above every IOKit assertion, still in force after Helm
/// quits. It is installed through a NOPASSWD sudoers rule, and `sudo -n` fails
/// the moment that rule is gone: removed by an admin, by a migration, by
/// somebody tidying `/etc/sudoers.d`. This machine has a leftover
/// `vorssaint-clamshell` from Helm's predecessor sitting there right now, which
/// is what those files do — they outlive the app that wrote them.
///
/// Both ends used to discard the result. The engage side then claimed a lid was
/// safe to close; the disengage side cleared the flag that brings the next
/// launch back to look, so a Mac that could not sleep would never be found —
/// and the log line said «closed-lid sleep restored» either way.
///
/// None of this was testable before: `FakeClamshell.setDisableSleep` returned
/// `true` unconditionally, so «pmset refused» was a state no test could write
/// down. The fake takes a flag now, which is the fix that had to come first.
final class APmsetThatRefusedIsNotASuccessTests: XCTestCase {
    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var clamshell: FakeClamshell!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        clamshell = FakeClamshell()
        clamshell.sudoersInstalled = true
        KeepAwakeSettings(store: store).setClamshellEnabled(true)
        engine = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                 assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(), power: FakePower(),
                                 apps: FakeApps(), pointer: FakePointer(),
                                 clamshell: clamshell, clock: FakeClock())
    }

    private var guardFlag: Bool {
        store.bool(KeepAwakeSettings.Key.clamshellGuard, default: false)
    }

    /// The control. Everything below is about a refusal, and a test of a
    /// refusal passes trivially if the thing never happened at all.
    func testTheOrdinaryPathStillDisablesAndRestores() {
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.clamshellActive, "precondition: it engaged")
        XCTAssertTrue(guardFlag)

        engine.stopSession()

        XCTAssertFalse(engine.clamshellActive)
        XCTAssertFalse(guardFlag, "the flag is only cleared once sleep is really back")
    }

    /// A refusal on the way in must not be reported as a lid you may close.
    func testARefusedDisableIsNotDrawnAsAClosedLidThatIsSafe() {
        clamshell.disableSleepSucceeds = false
        engine.startSession(minutes: 0)

        XCTAssertFalse(engine.clamshellActive,
                       "the panel draws «Lid closed — staying awake» from this, and "
                       + "pmset had just refused to disable sleep")
        XCTAssertTrue(engine.isActive, "the session itself is unaffected — the assertion holds")
    }

    /// …and the guard still says «this app may have touched system sleep», so
    /// the next launch goes and reads `pmset` rather than trusting us.
    func testARefusedDisableStillLeavesTheNextLaunchSomethingToCheck() {
        clamshell.disableSleepSucceeds = false
        engine.startSession(minutes: 0)

        XCTAssertTrue(guardFlag,
                      "the flag was cleared on a call whose outcome nobody knows, and the "
                      + "launch-time recovery is guarded on it")
    }

    /// The expensive one. Sleep is off machine-wide, the restore fails, and
    /// clearing the flag would mean nothing ever looks again.
    func testARefusedRestoreKeepsTheFlagThatBringsTheNextLaunchBack() {
        engine.startSession(minutes: 0)
        XCTAssertTrue(guardFlag, "precondition: sleep was really disabled")

        clamshell.disableSleepSucceeds = false
        engine.stopSession()

        XCTAssertTrue(guardFlag,
                      "system sleep is still off and the only note about it has been erased — "
                      + "this Mac never sleeps again and every screen says the module is idle")
        XCTAssertTrue(engine.clamshellActive,
                      "the state says sleep is restored while `pmset -g` would say otherwise")
    }

    /// And the recovery the flag exists for still runs on the next launch, so
    /// the guard above is guarding something that happens.
    func testTheNextLaunchRestoresWhatTheRefusalLeftBehind() {
        store.set(true, for: KeepAwakeSettings.Key.clamshellGuard)
        clamshell.pmset = "SleepDisabled 1"
        let fresh = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                    assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                    displayObserver: FakeDisplayObserver(), power: FakePower(),
                                    apps: FakeApps(), pointer: FakePointer(),
                                    clamshell: clamshell, clock: FakeClock())

        fresh.activate()

        XCTAssertTrue(clamshell.disableSleepCalls.contains(false),
                      "a launch that finds the guard set and sleep disabled has to put it back")
    }
}
