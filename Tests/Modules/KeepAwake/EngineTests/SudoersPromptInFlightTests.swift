import Foundation
import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// What happens to the sudoers rule while the password prompt is on screen.
///
/// `ClamshellCoordinator.engage` asks the system and, on no, starts an admin
/// prompt. Nothing records that a prompt is already up, and the file the
/// question is about does not appear until the prompt is answered — so every
/// path that reaches `engage` in that window asks again, and every path
/// that reaches `releaseSudoersIfUnneeded` in that window is told there is
/// nothing to remove.
///
/// Both halves of that are the same missing fact: "an install is in flight" is
/// state the engine keeps nowhere.
///
/// The prompt is hand-cranked, so every interleaving below is chosen rather than
/// raced, and the main queue is drained by enqueueing after the engine's own
/// block — FIFO, not a sleep.
@MainActor
final class SudoersPromptInFlightTests: XCTestCase {
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
        engine = fakeEngine(settings: settings, store: store, clamshell: clamshell)
        KeepAwakeSettings(store: store).setClamshellEnabled(true)
    }

    /// Puts a prompt on screen and leaves it there.
    private func startSessionWithPromptUp() async {
        // The dialog comes only from the person's gesture on the lid switch,
        // never from a Start press: the session starts with the option off and
        // the switch is turned on during it.
        KeepAwakeSettings(store: store).setClamshellEnabled(false)
        engine.activate()
        engine.startSession(minutes: 0)
        engine.lidSwitchTurned(true)
        // The question that decides whether to prompt is `sudo -n`, asked off
        // the drawing thread — see `waitForTheLid`.
        await waitUntil("the lid asked for the rule") { clamshell.installCalls == 1 }
        XCTAssertEqual(clamshell.installCalls, 1, "precondition: one password prompt is up")
        XCTAssertTrue(clamshell.disableSleepCalls.isEmpty,
                      "precondition: nothing has been granted yet")
    }

    // MARK: - The rule outlives the feature it was installed for

    /// The sequence: turn the clamshell option on, start a session, get the
    /// password prompt — then change your mind and turn the option off while the
    /// prompt is still up, then answer it anyway (or let the shell finish; the
    /// dialog is modal to nothing).
    ///
    /// `releaseSudoersIfUnneeded` runs on `settingsChanged` and is gated on
    /// `isSudoersInstalled()`, which is false because the rule is not on disk
    /// yet. When it lands there is nothing left that looks again.
    ///
    /// What is left behind is the exact thing the method's own doc comment
    /// exists to prevent: a permanent `NOPASSWD` line in `/etc/sudoers.d` for a
    /// feature the person has switched off — "a grant nobody is holding", and
    /// the one Helm's predecessor left on this machine.
    func testARuleThatLandsAfterTheOptionIsOffIsTakenBackOut() async throws {
        await startSessionWithPromptUp()

        // The person changes their mind while the prompt is up.
        KeepAwakeSettings(store: store).setClamshellEnabled(false)
        engine.settingsChanged()
        XCTAssertEqual((clamshell.removeCalls + clamshell.passwordlessRemovals), 0,
                       "precondition: there was nothing on disk to remove yet")

        // …and then the password is typed. The rule is installed now.
        clamshell.answerAllPrompts(granted: true)
        await drainMainQueue()

        XCTAssertFalse(clamshell.sudoersInstalled,
                       "a passwordless-sudo rule was left installed for a feature that is off")
    }

    /// The half of that which is already right, asserted so the fix cannot be
    /// made by weakening it: the rule landing late must not disable sleep for a
    /// feature nobody has turned on.
    func testARuleThatLandsAfterTheOptionIsOffDisablesNoSleep() async throws {
        await startSessionWithPromptUp()

        KeepAwakeSettings(store: store).setClamshellEnabled(false)
        engine.settingsChanged()
        clamshell.answerAllPrompts(granted: true)
        await drainMainQueue()

        XCTAssertFalse(clamshell.disableSleepCalls.contains(true))
        XCTAssertFalse(engine.clamshellActive)
    }

    // MARK: - One question, asked once

    /// Only the person's own gesture raises the dialog: a Start press or an
    /// unrelated settings change reaches `engage(mayPrompt: false)` and never
    /// the in-flight flag, so it is not tested here (`AStoredSwitchIsNotAGestureTests`).
    /// The one way left to ask twice: the person's own gesture, twice. Off and on
    /// again on the switch while the first prompt is still up is a second rising
    /// edge, and only the in-flight flag stands between it and a second dialog.
    func testTheSwitchTurnedOffAndOnAgainWhileThePromptIsUpRaisesNoSecondDialog() async {
        await startSessionWithPromptUp()

        let asked = clamshell.grantChecks
        engine.lidSwitchTurned(false)
        engine.lidSwitchTurned(true)

        await waitUntil("the lid asked again whether it needs a password") {
            clamshell.grantChecks > asked
        }
        // The answer is acted on back on main, after the question: read the
        // count only once that hop has landed, or it is green because the
        // second request has not been made yet.
        await engine.drainClamshellForTests()
        await drainMainQueue()
        XCTAssertEqual(clamshell.installCalls, 1,
                       "a second admin password prompt was stacked on the one already up")
    }

    // MARK: - …and the feature still works

    /// The control. Nothing was withdrawn, the password was typed, the rule is
    /// installed and sleep is disabled — so none of the above can be satisfied
    /// by never installing anything.
    func testAnAnsweredPromptStillEngagesTheClamshellGuard() async {
        await startSessionWithPromptUp()

        clamshell.answerAllPrompts(granted: true)
        await drainMainQueue()

        XCTAssertTrue(clamshell.sudoersInstalled)
        XCTAssertEqual(clamshell.disableSleepCalls, [true])
        XCTAssertTrue(engine.clamshellActive)
        XCTAssertEqual((clamshell.removeCalls + clamshell.passwordlessRemovals), 0)
    }

    /// And a refused prompt asks again on the next session, because a person who
    /// clicked Cancel may well mean to say yes later. This is what the in-flight
    /// guard the tests above ask for must *not* break: "a prompt is up" and "a
    /// prompt was declined" are different states.
    func testADeclinedPromptCanBeAskedAgainByTheNextGestureOnTheSwitch() async {
        await startSessionWithPromptUp()

        clamshell.answerAllPrompts(granted: false)
        await drainMainQueue()
        engine.stopSession()
        engine.startSession(minutes: 0)
        // A Start press does not ask; the person's next turn of the switch does.
        engine.lidSwitchTurned(false)
        engine.lidSwitchTurned(true)

        await waitUntil("the lid asked for the rule a second time") { clamshell.installCalls == 2 }
        XCTAssertEqual(clamshell.installCalls, 2,
                       "the person declined once and can no longer turn the feature on")
    }
}
