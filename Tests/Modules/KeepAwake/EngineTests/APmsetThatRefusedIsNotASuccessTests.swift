import XCTest
import HelmTestSupport
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
    @MainActor
    func testTheOrdinaryPathStillDisablesAndRestores() async {
        engine.startSession(minutes: 0)
        // The grant is asked for on the lid's own queue now, so the answer to a
        // gesture arrives a hop after the gesture — `waitForTheLid`.
        await waitUntil("the lid disabled sleep") { engine.clamshellActive }
        XCTAssertTrue(engine.clamshellActive, "precondition: it engaged")
        XCTAssertTrue(guardFlag)

        engine.stopSession()

        XCTAssertFalse(engine.clamshellActive)
        XCTAssertFalse(guardFlag, "the flag is only cleared once sleep is really back")
    }

    /// A refusal on the way in must not be reported as a lid you may close.
    @MainActor
    func testARefusedDisableIsNotDrawnAsAClosedLidThatIsSafe() async {
        clamshell.disableSleepSucceeds = false
        engine.startSession(minutes: 0)

        // The refusal has to have happened before its absence is read: «the lid
        // is not claimed safe» is true of a question still on its way to `pmset`.
        await waitUntil("the lid asked pmset") { clamshell.disableSleepCalls.contains(true) }
        XCTAssertFalse(engine.clamshellActive,
                       "the panel draws «Lid closed — staying awake» from this, and "
                       + "pmset had just refused to disable sleep")
        XCTAssertTrue(engine.isActive, "the session itself is unaffected — the assertion holds")
    }

    /// …and the guard still says «this app may have touched system sleep», so
    /// the next launch goes and reads `pmset` rather than trusting us.
    @MainActor
    func testARefusedDisableStillLeavesTheNextLaunchSomethingToCheck() async {
        clamshell.disableSleepSucceeds = false
        engine.startSession(minutes: 0)

        await waitUntil("the lid asked pmset") { clamshell.disableSleepCalls.contains(true) }
        XCTAssertTrue(guardFlag,
                      "the flag was cleared on a call whose outcome nobody knows, and the "
                      + "launch-time recovery is guarded on it")
    }

    /// The expensive one. Sleep is off machine-wide, the restore fails, and
    /// clearing the flag would mean nothing ever looks again.
    @MainActor
    func testARefusedRestoreKeepsTheFlagThatBringsTheNextLaunchBack() async {
        engine.startSession(minutes: 0)
        await waitUntil("the lid disabled sleep") { engine.clamshellActive }
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
    @MainActor
    func testTheNextLaunchRestoresWhatTheRefusalLeftBehind() async {
        store.set(true, for: KeepAwakeSettings.Key.clamshellGuard)
        clamshell.pmset = "SleepDisabled 1"

        let engine = atLaunch()
        engine.activate()

        await waitUntil("the lid put sleep back") { clamshell.disableSleepCalls.contains(false) }
        XCTAssertTrue(clamshell.disableSleepCalls.contains(false),
                      "a launch that finds the guard set and sleep disabled has to put it back")
    }

    /// **The same refusal, on the other of the two paths that clear the flag.**
    ///
    /// `disengage()` was taught to keep the flag when `pmset` refuses — that is
    /// the test four above, and it is the expensive case: sleep is off
    /// machine-wide and the note is the only thing that brings anybody back to
    /// look. `recoverAtLaunch()` does the identical pair of steps and was left
    /// as it was: `_ = clamshell.setDisableSleep(false)`, result discarded, and
    /// then the flag cleared whatever happened.
    ///
    /// So the sequence this whole file is about — Helm crashed with sleep off,
    /// and the sudoers rule has since been taken out by an admin, a migration or
    /// somebody tidying `/etc/sudoers.d`, which is exactly what this machine's
    /// leftover `vorssaint-clamshell` line is — ends with the restore refused,
    /// the note erased, and **no launch ever looking again**. The Mac does not
    /// sleep again, and every screen says Keep Awake is idle: `active` is false
    /// on the path that never succeeded, so even the settings row that now says
    /// «Sleep is off right now» says nothing.
    ///
    /// Asserted as the flag rather than as a `pmset` call count, for the reason
    /// its sibling gives: the flag is the whole mechanism by which a failure
    /// here is recoverable at all.
    @MainActor
    func testARefusedRecoveryAtLaunchKeepsTheFlagThatBringsTheNextLaunchBack() async {
        store.set(true, for: KeepAwakeSettings.Key.clamshellGuard)
        clamshell.pmset = "SleepDisabled 1"
        clamshell.disableSleepSucceeds = false

        let engine = atLaunch()
        engine.activate()

        await waitUntil("the lid tried to put sleep back") { clamshell.disableSleepCalls.contains(false) }
        // The subject first: a test about a refusal is vacuous if the call never
        // happened. `recoverAtLaunch` short-circuits on the flag *and* on the
        // `pmset` report, and either half missing would leave nothing to refuse.
        XCTAssertTrue(clamshell.disableSleepCalls.contains(false),
                      "precondition: the launch did try to put sleep back")
        XCTAssertTrue(guardFlag,
                      "the restore was refused and the note that says «this app may have left "
                      + "system sleep off» has been cleared anyway — nothing will ever look "
                      + "again, this Mac never sleeps, and `active` is false so no screen says "
                      + "a word about it")
    }

    /// **The refusal reaches the screen from the coordinator, not from the habits
    /// of its callers.**
    ///
    /// `ClamshellCoordinator` is told `stateChanged` rather than asking, because
    /// its answers change while a password prompt is up — and `reallyEngage`'s
    /// refusal branch calls it while `restoreSleep`'s did not. Every caller of
    /// `restoreSleep` happens to emit on the same turn today (`recompute`,
    /// `releaseForBattery`, `reconcileActiveSettings`, `activate`, `deactivate`),
    /// so this is a test of the contract and not of anything visible: asserted
    /// here, one call away, because at engine level it cannot fail.
    @MainActor
    func testARefusedRestoreAnnouncesItselfRatherThanTrustingTheCaller() async {
        let lid = ClamshellCoordinator(clamshell: clamshell, store: store,
                                       settings: KeepAwakeSettings(store: store))
        lid.sessionIsActive = { true }
        var announcements = 0
        lid.stateChanged = { announcements += 1 }
        clamshell.passwordlessGrantExists = true
        lid.engage(mayPrompt: false)
        await waitUntil("the lid engaged") { lid.active }
        XCTAssertTrue(lid.active, "precondition: sleep is off, so there is something to restore")
        // Engaging announces its own answer as well now, and for the same reason
        // the refusal below must: `sudo -n` is asked on the lid's own queue, so
        // the answer arrives after the caller that would have emitted for it has
        // returned. Counted from here rather than from zero.
        let afterEngaging = announcements

        clamshell.disableSleepSucceeds = false
        lid.disengage()

        XCTAssertEqual(announcements - afterEngaging, 1,
                       "the restore was refused — system sleep is still off — and the class whose "
                       + "whole reason for holding `stateChanged` is «a refusal has to reach the "
                       + "screen» said nothing")
    }

    /// A second engine over the same store and the same lid, which is what the
    /// next launch is.
    private func atLaunch() -> KeepAwakeEngine {
        KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                        assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(), power: FakePower(),
                        apps: FakeApps(), pointer: FakePointer(),
                        clamshell: clamshell, clock: FakeClock())
    }
}
