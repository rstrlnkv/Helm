import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_KeepAwake_Engine

/// What the rule's own withdrawal line buys, read from the engine.
///
/// Until it existed the only way out of `/etc/sudoers.d/helm-keepawake` was an
/// administrator dialog, so the grant could only be taken back with somebody at
/// the screen — and dragging `Helm.app` to the Trash, which is how a Mac
/// application is normally removed, runs no code at all. The grant stayed for
/// the life of the machine, naming an app that no longer existed, and anything
/// running as that account could hold the Mac awake with no password. On a
/// laptop in a bag that is a thermal event.
///
/// With the withdrawal in the rule the removal is `sudo -n`: no dialog, nothing
/// to decline, nothing for a person to be present for. So it becomes affordable
/// at the moment the app goes — **but only where the grant has nothing left to
/// do.** Every case in which it is load-bearing keeps it, and those are the
/// three the second half of this file is about:
/// `AGrantIsNotRevokedByQuittingTests` argues the same three from the other
/// side, against the restore rather than the withdrawal.
final class TheGrantDoesNotOutliveTheAppItNamesTests: XCTestCase {
    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var clamshell: FakeClamshell!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        settings = KeepAwakeSettings(store: store)
        clamshell = FakeClamshell()
        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = true
        settings.setClamshellEnabled(true)
        engine = KeepAwakeEngine(settings: settings, store: store,
                                 assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(), power: FakePower(),
                                 apps: FakeApps(), pointer: FakePointer(),
                                 clamshell: clamshell, clock: FakeClock())
    }

    private var guardFlag: Bool {
        store.bool(KeepAwakeSettings.Key.clamshellGuard, default: false)
    }

    // MARK: - The option's own falling edge

    /// The removal that already existed, and what it now costs.
    @MainActor
    func testSwitchingTheOptionOffWithdrawsTheGrantWithoutADialog() async {
        settings.setClamshellEnabled(false)

        engine.settingsChangedForTests()

        await waitUntil("the rule came out") { !self.clamshell.isSudoersInstalled() }
        XCTAssertEqual(clamshell.passwordlessRemovals, 1)
        XCTAssertEqual(clamshell.removeCalls, 0,
                       "the rule permits its own removal, so there is nothing to ask a password for")
    }

    /// A rule installed by a version of Helm from before the withdrawal line —
    /// or written by something else — cannot take itself out, and that is the
    /// one removal that still costs a password. It is asked for here because
    /// there is somebody at the screen: this is the option's own switch.
    @MainActor
    func testARuleThatCannotWithdrawItselfStillAsksForAPassword() async {
        clamshell.withdrawalIsGranted = false
        settings.setClamshellEnabled(false)

        engine.settingsChangedForTests()

        await waitUntil("the dialog was raised") { self.clamshell.removeCalls == 1 }
        XCTAssertEqual(clamshell.passwordlessRemovals, 1, "the free route is tried first")
        XCTAssertFalse(clamshell.isSudoersInstalled())
    }

    // MARK: - Quitting

    /// The case this whole change exists for: quit, then drag the app to the
    /// Trash. Nothing is holding the Mac, sleep is back, and the grant names an
    /// application that is about to stop existing.
    @MainActor
    func testQuittingWithNothingLeftToDoWithdrawsTheGrant() async {
        engine.startSession(minutes: 0)
        await waitUntil("the lid disabled sleep") { self.engine.clamshellActive }
        engine.stopSession()
        await waitUntil("sleep came back") { !self.guardFlag }

        engine.deactivate()

        XCTAssertFalse(clamshell.isSudoersInstalled(),
                       "the app is going and the rule would have named it for ever")
        XCTAssertEqual(clamshell.removeCalls, 0,
                       "a terminating process must never put a password dialog on screen")
    }

    /// The withdrawal at quit is `sudo -n` or it is nothing. A rule too old to
    /// take itself out is left where it is rather than answered with a dialog
    /// nobody will be there for — which is the defect this module was corrected
    /// for once already, and the two orphaned predecessor rules in
    /// `/etc/sudoers.d` on the development Mac are what it looks like years on.
    @MainActor
    func testAnOlderRuleIsLeftAtQuitRatherThanPromptedFor() async {
        clamshell.withdrawalIsGranted = false
        engine.startSession(minutes: 0)
        await waitUntil("the lid disabled sleep") { self.engine.clamshellActive }
        engine.stopSession()
        await waitUntil("sleep came back") { !self.guardFlag }

        engine.deactivate()

        XCTAssertEqual(clamshell.removeCalls, 0, "no dialog on the way out, ever")
        XCTAssertTrue(clamshell.isSudoersInstalled(),
                      "and the rule stays, for the lid option's own switch to take out")
    }

    /// And the next launch does **not** put it back to keep the next enable
    /// seamless. That would reopen the window this change closed: a rule
    /// installed at every launch is a rule present whenever the app is deleted.
    /// It is asked for when the feature is actually needed — one dialog per run
    /// of the app, at the moment it means something.
    @MainActor
    func testTheNextLaunchPutsNothingBackUntilSomebodyStartsASession() async {
        // Our file is the only thing granting this, so the capability goes with
        // it — the planted «somebody else's rule» of the other cases would leave
        // the next session with nothing to ask for.
        clamshell.passwordlessGrantExists = nil
        engine.startSession(minutes: 0)
        await waitUntil("the lid disabled sleep") { self.engine.clamshellActive }
        engine.stopSession()
        await waitUntil("sleep came back") { !self.guardFlag }
        engine.deactivate()
        XCTAssertFalse(clamshell.isSudoersInstalled(), "precondition: the rule went at quit")
        let looksBefore = clamshell.installedChecks
        let readsBefore = clamshell.pmsetReads

        let next = atLaunch()
        next.activate()

        // The absence is read after the launch has looked, never instead of it.
        await waitUntil("the launch looked for the rule") {
            self.clamshell.installedChecks > looksBefore
        }
        XCTAssertEqual(clamshell.installCalls, 0,
                       "a password dialog at launch, for a feature nobody has asked for yet")
        XCTAssertEqual(clamshell.pmsetReads, readsBefore,
                       "with neither anchor there is nothing to recover and nothing to read")

        next.startSession(minutes: 0)

        await waitUntil("the rule was asked for") { self.clamshell.installCalls == 1 }
    }

    /// A second engine over the same store and the same lid, which is what the
    /// next launch is.
    private func atLaunch() -> KeepAwakeEngine {
        KeepAwakeEngine(settings: settings, store: store,
                        assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(), power: FakePower(),
                        apps: FakeApps(), pointer: FakePointer(),
                        clamshell: clamshell, clock: FakeClock())
    }

    // MARK: - Where the grant is still load-bearing

    /// **The updater's relaunch.** Helm terminates and a detached script starts
    /// it again, and a session the person asked for is deliberately resumed —
    /// with `mayPrompt: false`, because nobody touched anything. Withdrawing the
    /// grant on the way out would bring that session back with the lid silently
    /// unprotected, which is a Mac asleep in a bag on a promise Helm made.
    @MainActor
    func testASessionThatWillResumeKeepsTheGrantItWillNeed() async {
        engine.startSession(minutes: 0)
        await waitUntil("the lid disabled sleep") { self.engine.clamshellActive }

        engine.deactivate()

        XCTAssertTrue(clamshell.isSudoersInstalled(),
                      "the next launch resumes this session and needs the rule to hold the lid")
    }

    /// A session comes back but the lid option does not apply to it, so there is
    /// nothing for the grant to do. Without this the test above is satisfied by
    /// a module that never withdraws anything once a session has been started.
    @MainActor
    func testASessionThatWillResumeWithTheLidOptionOffDoesNotKeepIt() async {
        engine.startSession(minutes: 0)
        await waitUntil("the lid disabled sleep") { self.engine.clamshellActive }
        settings.setClamshellEnabled(false)

        engine.deactivate()

        XCTAssertFalse(clamshell.isSudoersInstalled())
    }

    /// The restore refused, so system sleep is off for the whole Mac and the
    /// next launch is the only thing that can put it back — with
    /// `sudo -n pmset disablesleep 0`, which is this grant. Taking it out here
    /// would leave a Mac that never sleeps again with every screen saying Keep
    /// Awake is idle.
    ///
    /// The session is **stopped first**, deliberately: with one still running
    /// the case above already keeps the grant, and this one would then be a
    /// green light for a guard that was not there. It was written the other way
    /// round first, and a mutation removing `!active` from `withdrawAtQuit`
    /// passed the whole file.
    @MainActor
    func testARefusedRestoreKeepsTheGrantItsOwnRecoveryNeeds() async {
        engine.startSession(minutes: 0)
        await waitUntil("the lid disabled sleep") { self.engine.clamshellActive }
        XCTAssertTrue(guardFlag, "precondition: sleep was really disabled")
        clamshell.disableSleepSucceeds = false
        engine.stopSession()

        engine.deactivate()

        XCTAssertTrue(engine.clamshellActive, "precondition: the restore really did refuse")
        XCTAssertTrue(guardFlag, "…and the note to the next launch is still set")
        XCTAssertTrue(clamshell.isSudoersInstalled(),
                      "the recovery the next launch has to run needs this rule")
    }

    /// And the note is not the only anchor, because the note is a plist entry
    /// **anything running as this user can rewrite**. Clear it while sleep is
    /// really off and the withdrawal must still refuse: `active` is this
    /// process's own knowledge, and it is the half no other process can edit.
    /// `RecoveryAnchorIsNotAWritableFlagTests` makes the same argument about the
    /// launch recovery.
    @MainActor
    func testANoteSomethingElseErasedDoesNotHandOutTheGrant() async {
        engine.startSession(minutes: 0)
        await waitUntil("the lid disabled sleep") { self.engine.clamshellActive }
        clamshell.disableSleepSucceeds = false
        engine.stopSession()
        // Somebody else's `defaults write`, or a tidy-up script.
        store.set(false, for: KeepAwakeSettings.Key.clamshellGuard)

        engine.deactivate()

        XCTAssertTrue(engine.clamshellActive, "precondition: sleep really is still off")
        XCTAssertTrue(clamshell.isSudoersInstalled(),
                      "the only anchor left was erased from outside, and the grant went with it")
    }

    /// The other half of the same refusal, and the one `active` cannot stand
    /// for: sleep was never turned off — `pmset` said no on the way *in* — but
    /// the note that brings the next launch back to look was written before the
    /// call and stays. That launch runs `sudo -n pmset disablesleep 0`, so the
    /// note without the grant is a question nobody can answer.
    @MainActor
    func testTheNoteToTheNextLaunchKeepsTheGrantThatNoteWillNeed() async {
        clamshell.disableSleepSucceeds = false
        engine.startSession(minutes: 0)
        await waitUntil("the lid was asked and refused") { self.guardFlag }
        engine.stopSession()
        XCTAssertFalse(engine.clamshellActive, "precondition: sleep is not off, as far as pmset said")

        engine.deactivate()

        XCTAssertTrue(guardFlag, "precondition: the note stands")
        XCTAssertTrue(clamshell.isSudoersInstalled())
    }
}
