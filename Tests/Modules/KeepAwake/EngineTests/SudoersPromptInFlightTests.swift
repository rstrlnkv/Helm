import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The clamshell port with the one thing the shared fake cannot express: a
/// password prompt that is *up*.
///
/// `installSudoers` shells out to `osascript … with administrator privileges`,
/// which blocks for as long as the person takes to find their password — that is
/// seconds to minutes, and the app carries on running underneath it. The shared
/// `FakeClamshell` keeps a single `installCompletion` and overwrites it, so a
/// second request is indistinguishable from the first. This one counts them and
/// holds them all.
///
/// It also models what the real command does on success: the rule is on disk
/// *before* `done(true)` is called, because the shell has already run `mv` into
/// `/etc/sudoers.d`.
private final class PromptClamshell: ClamshellPort {
    var sudoersInstalled = false
    var pmset = ""
    var disableSleepCalls: [Bool] = []
    private(set) var installCount = 0
    private(set) var removeCount = 0
    private var pending: [(Bool) -> Void] = []

    func isSudoersInstalled() -> Bool { sudoersInstalled }

    func installSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        installCount += 1
        pending.append(done)
    }

    /// The person typed their password. The file exists from this moment on.
    func answerAllPrompts(granted: Bool) {
        let waiting = pending
        pending = []
        if granted { sudoersInstalled = true }
        for done in waiting { done(granted) }
    }

    func removeSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        removeCount += 1
        sudoersInstalled = false
        done(true)
    }

    func setDisableSleep(_ on: Bool) -> Bool { disableSleepCalls.append(on); return true }
    func pmsetReport() -> String { pmset }
}

/// What happens to the sudoers rule while the password prompt is on screen.
///
/// `engageClamshell` asks `isSudoersInstalled()` and, on no, starts an admin
/// prompt. Nothing records that a prompt is already up, and the file the
/// question is about does not appear until the prompt is answered — so every
/// path that reaches `engageClamshell` in that window asks again, and every path
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
    private var clamshell: PromptClamshell!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        settings = KeepAwakeSettings(store: store)
        clamshell = PromptClamshell()
        engine = KeepAwakeEngine(settings: settings, store: store,
                                 assertions: FakeAssertions(),
                                 displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(),
                                 power: FakePower(), apps: FakeApps(),
                                 pointer: FakePointer(),
                                 clamshell: clamshell, clock: FakeClock())
        store.set(true, for: "clamshellEnabled")
    }

    /// Everything already on the main queue has run. The engine posts its
    /// install callback with `DispatchQueue.main.async`; this is enqueued after
    /// it, and a serial queue runs them in order — so this is an ordering fact,
    /// not a sleep.
    ///
    /// `await fulfillment` rather than `wait(for:)`: these tests are on the main
    /// actor, and blocking it is what stops the queue draining at all.
    private func drainMain() async {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 5)
    }

    /// Puts a prompt on screen and leaves it there.
    private func startSessionWithPromptUp() {
        engine.activate()
        engine.startSession(minutes: 0)
        XCTAssertEqual(clamshell.installCount, 1, "precondition: one password prompt is up")
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
        startSessionWithPromptUp()

        // The person changes their mind while the prompt is up.
        store.set(false, for: "clamshellEnabled")
        _ = try await engine.transport.send(EngineCommand(name: "settingsChanged"))
        XCTAssertEqual(clamshell.removeCount, 0,
                       "precondition: there was nothing on disk to remove yet")

        // …and then the password is typed. The rule is installed now.
        clamshell.answerAllPrompts(granted: true)
        await drainMain()

        XCTAssertFalse(clamshell.sudoersInstalled,
                       "a passwordless-sudo rule was left installed for a feature that is off")
    }

    /// The half of that which is already right, asserted so the fix cannot be
    /// made by weakening it: the rule landing late must not disable sleep for a
    /// feature nobody has turned on.
    func testARuleThatLandsAfterTheOptionIsOffDisablesNoSleep() async throws {
        startSessionWithPromptUp()

        store.set(false, for: "clamshellEnabled")
        _ = try await engine.transport.send(EngineCommand(name: "settingsChanged"))
        clamshell.answerAllPrompts(granted: true)
        await drainMain()

        XCTAssertFalse(clamshell.disableSleepCalls.contains(true))
        XCTAssertFalse(engine.clamshellActive)
    }

    // MARK: - One question, asked once

    /// Stop and start again while the prompt is up, which is one click each in
    /// the panel and needs no timing at all: `recompute` calls `engageClamshell`
    /// on every false→true edge of `isActive`, and `isSudoersInstalled()` is
    /// still false because the first prompt has not been answered.
    ///
    /// The person now has two admin password dialogs for one decision, and both
    /// of them are `osascript` writing the same staging file inside
    /// `/etc/sudoers.d`.
    func testStartingASessionAgainDoesNotAskForThePasswordTwice() {
        startSessionWithPromptUp()

        engine.stopSession()
        engine.startSession(minutes: 0)

        XCTAssertEqual(clamshell.installCount, 1,
                       "a second admin password prompt was stacked on the one already up")
    }

    /// The same edge through the settings page rather than the panel.
    /// `reconcileActiveSettings` asks `clamshellEnabled && !clamshellActive` —
    /// which is true for the whole life of the prompt — so *any* settings change
    /// while it is up asks again: the display toggle, the jiggle interval, a
    /// battery threshold.
    func testASettingsChangeWhileThePromptIsUpDoesNotAskAgain() async throws {
        startSessionWithPromptUp()

        _ = try await engine.transport.send(EngineCommand(name: "settingsChanged"))

        XCTAssertEqual(clamshell.installCount, 1,
                       "changing an unrelated setting put a second password prompt on screen")
    }

    // MARK: - …and the feature still works

    /// The control. Nothing was withdrawn, the password was typed, the rule is
    /// installed and sleep is disabled — so none of the above can be satisfied
    /// by never installing anything.
    func testAnAnsweredPromptStillEngagesTheClamshellGuard() async {
        startSessionWithPromptUp()

        clamshell.answerAllPrompts(granted: true)
        await drainMain()

        XCTAssertTrue(clamshell.sudoersInstalled)
        XCTAssertEqual(clamshell.disableSleepCalls, [true])
        XCTAssertTrue(engine.clamshellActive)
        XCTAssertEqual(clamshell.removeCount, 0)
    }

    /// And a refused prompt asks again on the next session, because a person who
    /// clicked Cancel may well mean to say yes later. This is what the in-flight
    /// guard the tests above ask for must *not* break: "a prompt is up" and "a
    /// prompt was declined" are different states.
    func testADeclinedPromptCanBeAskedAgainOnTheNextSession() async {
        startSessionWithPromptUp()

        clamshell.answerAllPrompts(granted: false)
        await drainMain()
        engine.stopSession()
        engine.startSession(minutes: 0)

        XCTAssertEqual(clamshell.installCount, 2,
                       "the person declined once and can no longer turn the feature on")
    }
}
