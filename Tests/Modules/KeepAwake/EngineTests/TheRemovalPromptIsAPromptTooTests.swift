import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The clamshell port with the removal half told the way the install half
/// already is: a password prompt that is **up**.
///
/// Both shared fakes answer `removeSudoers` inline — `FakeClamshell` and the
/// `PromptClamshell` in `SudoersPromptInFlightTests` each call `done(true)` and
/// set `sudoersInstalled = false` in the same breath. `PmsetClamshellPort` does
/// neither: it hops to a global queue and runs
/// `osascript … with administrator privileges`, which blocks for as long as the
/// person takes to find their password, and `/etc/sudoers.d` still holds the
/// rule for every second of that. A fake that finishes instantly makes a test of
/// a gate vacuous the same way a fake that answers synchronously does — the
/// second call finds the world already tidied and never meets the gate at all.
///
/// So this one holds the completion, and `isSudoersInstalled()` goes on
/// answering yes until the prompt is answered. That is the state the real port
/// is in for minutes at a time.
private final class RemovalPromptClamshell: ClamshellPort {
    var sudoersInstalled = true
    var pmset = ""
    private(set) var removeCount = 0
    private(set) var installCount = 0
    private var pendingRemovals: [(Bool) -> Void] = []

    func canDisableSleepWithoutPassword() -> Bool { sudoersInstalled }
    func isSudoersInstalled() -> Bool { sudoersInstalled }

    func installSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        installCount += 1
        sudoersInstalled = true
        done(true)
    }

    /// The prompt goes up and stays up. The file is still there.
    func removeSudoers(_ done: @escaping @Sendable (Bool) -> Void) {
        removeCount += 1
        pendingRemovals.append(done)
    }

    /// The person typed their password (or clicked Cancel). Only now does the
    /// file go — and only if they said yes.
    func answerRemovalPrompts(granted: Bool) {
        let waiting = pendingRemovals
        pendingRemovals = []
        if granted { sudoersInstalled = false }
        for done in waiting { done(granted) }
    }

    func setDisableSleep(_ on: Bool) -> Bool { true }
    func pmsetReport() -> String { pmset }
}

/// Switching «stay awake with the lid closed» off takes the passwordless-sudo
/// rule back out — and asks for a password to do it.
///
/// `ClamshellCoordinator.engage` keeps `installInFlight` for exactly this, with a
/// comment naming what it costs: "the person got one password dialog per click
/// for a single decision". `releaseSudoersIfUnneeded` is the same shape with
/// nothing in front of it —
///
///     guard !settings.clamshellEnabled, clamshell.isSudoersInstalled() else { return }
///     clamshell.removeSudoers { _ in }
///
/// — and it runs on `settingsChanged`, which the settings page sends on **every
/// control it draws**: a colour swatch, the jiggle interval, the battery floor.
/// With the option off and the rule still on disk, each of those is another
/// `osascript` asking for an administrator password for the one decision the
/// person already made.
///
/// **What asks is the switch, not the message.** This file used to send bare
/// `settingsChanged`es with the option *never having been on* — so what it
/// called «turning the option off» was «the option is off», which is the
/// reading `ADeclinedRemovalIsNotAskedForEverTests` showed the cost of: it is
/// true from the first edit of every future launch, and the battery floor's
/// `Slider` sends one of these per rounded value it passes. The ask follows the
/// option's **falling edge** now (`ClamshellCoordinator.releaseIfUnneeded`), the
/// same shape the install side already had, so every case here drives the
/// switch rather than repeating a message that says nothing changed. Nothing
/// asserted here was given up: a decline can still be asked again, it just takes
/// the gesture that means «take that rule away» rather than any edit at all.
@MainActor
final class TheRemovalPromptIsAPromptTooTests: XCTestCase {

    private var store: NamespacedStore!
    private var clamshell: RemovalPromptClamshell!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        clamshell = RemovalPromptClamshell()
        // The option is on and its rule is installed, which is where somebody
        // who has used the feature starts — and it is what makes switching it
        // off below an *edge* rather than a value that was always false.
        KeepAwakeSettings(store: store).setClamshellEnabled(true)
        engine = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                 assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(), power: FakePower(),
                                 apps: FakeApps(), pointer: FakePointer(),
                                 clamshell: clamshell, clock: FakeClock())
        engine.activate()
    }

    /// What the settings page sends when anything on it moves.
    private func settingsChanged() async {
        _ = try? await engine.transport.send(
            EngineCommand(name: KeepAwakeCommand.settingsChanged.rawValue))
    }

    /// The gesture: the switch moves, and the page says so the only way it can.
    private func switchTheOption(_ on: Bool) async {
        KeepAwakeSettings(store: store).setClamshellEnabled(on)
        await settingsChanged()
    }

    /// The control, first: a test about asking twice is worth nothing if the
    /// first ask never happened.
    func testTurningTheOptionOffAsksToRemoveTheRule() async {
        await switchTheOption(false)

        XCTAssertEqual(clamshell.removeCount, 1,
                       "a NOPASSWD line for a feature that is off is a grant nobody is holding")
    }

    /// The person switched the lid option off, the password dialog is on screen,
    /// and while it is up they carry on with the page — the battery floor, a
    /// swatch, the jiggle interval. Every one of those is a `settingsChanged`.
    func testAChangeMadeWhileTheRemovalPromptIsUpDoesNotAskAgain() async {
        await switchTheOption(false)
        XCTAssertEqual(clamshell.removeCount, 1, "precondition: one prompt is up")

        await settingsChanged()

        XCTAssertEqual(clamshell.removeCount, 1,
                       "a second administrator password dialog was stacked on the one already "
                       + "up, for the decision the person already made — the install side keeps "
                       + "`installInFlight` for precisely this")
    }

    /// And it is not two: the page sends this command on every control it has.
    func testFourMoreSettingsChangesDoNotStackFourMorePrompts() async {
        await switchTheOption(false)
        for _ in 0..<4 { await settingsChanged() }

        XCTAssertEqual(clamshell.removeCount, 1,
                       "five ordinary edits on the settings page, five password dialogs")
    }

    /// The same question asked of the *gesture*, which is what the in-flight
    /// guard is left holding once unrelated edits no longer ask: somebody
    /// flicking the switch while the dialog waits gets one dialog, not three.
    ///
    /// Here because without it `removalInFlight` is guarded by nothing a test
    /// can see — every other case above is now answered by the edge, and a flag
    /// no test can fail is a flag the next reader deletes.
    func testFlickingTheSwitchWhileThePromptIsUpDoesNotStackPrompts() async {
        await switchTheOption(false)
        XCTAssertEqual(clamshell.removeCount, 1, "precondition: one prompt is up")

        await switchTheOption(true)
        await switchTheOption(false)

        XCTAssertEqual(clamshell.removeCount, 1,
                       "a second administrator dialog was stacked on the one already up, for a "
                       + "rule that is still on disk because nobody has answered the first")
        // Answered, so nothing is left waiting on a completion this test owns.
        clamshell.answerRemovalPrompts(granted: true)
    }

    /// The other end, which no in-flight flag may cost: once the prompt has been
    /// answered and the rule is gone, nothing asks again — and nothing keeps
    /// asking for ever either.
    func testOnceTheRuleIsGoneNothingAsksAgain() async {
        await switchTheOption(false)
        clamshell.answerRemovalPrompts(granted: true)
        XCTAssertFalse(clamshell.sudoersInstalled, "precondition: the rule is off disk")

        await settingsChanged()
        // And not only an unrelated edit: the gesture itself finds nothing to
        // ask about, which is what stops «switch it off again» from being a
        // password dialog for a file that is not there.
        await switchTheOption(true)
        await switchTheOption(false)

        XCTAssertEqual(clamshell.removeCount, 1)
    }

    /// A prompt that was **declined** is a different state from one that is up:
    /// the rule is still there, the person said no this time, and the next
    /// decision of theirs may well be yes. This is what the guard the tests
    /// above ask for must not break — the same distinction the install side
    /// already keeps (`testADeclinedPromptCanBeAskedAgainOnTheNextSession`).
    ///
    /// What asks again is the switch, not the next edit of anything on the page:
    /// «any settings change» is the trigger that made one drag of the battery
    /// floor six administrator dialogs, and it never stopped, because a declined
    /// removal leaves the file exactly where the next launch finds it.
    func testADeclinedRemovalCanBeAskedAgain() async {
        await switchTheOption(false)
        clamshell.answerRemovalPrompts(granted: false)
        XCTAssertTrue(clamshell.sudoersInstalled, "precondition: Cancel leaves the rule on disk")

        await switchTheOption(true)
        await switchTheOption(false)

        XCTAssertEqual(clamshell.removeCount, 2,
                       "the person clicked Cancel once and the rule can never be removed again")
    }

    /// The feature switched back on while the removal prompt is still up, and
    /// then answered anyway — `osascript` is already running and nothing can
    /// call it back. The rule goes, and the option it belonged to is on.
    ///
    /// What matters is that the module *notices*: it may not go on claiming a
    /// lid is safe to close on the strength of a rule that has just been
    /// removed. It asks for it back instead, which is the same answer
    /// `APmsetThatRefusedIsNotASuccessTests` demands when the rule disappears
    /// behind the app's back for any other reason.
    func testARuleRemovedWhileTheOptionWentBackOnIsAskedForAgain() async {
        await switchTheOption(false)
        XCTAssertEqual(clamshell.removeCount, 1, "precondition: a removal is in flight")

        await switchTheOption(true)
        // …and only now does the person answer the dialog that is still up.
        clamshell.answerRemovalPrompts(granted: true)
        XCTAssertFalse(clamshell.sudoersInstalled, "precondition: the rule is gone")

        engine.startSession(minutes: 0)
        await drainMain()

        XCTAssertEqual(clamshell.installCount, 1,
                       "the session began with the lid option on and a rule that is no longer "
                       + "there, and nothing went to look")
        XCTAssertTrue(engine.clamshellActive)
    }

    /// Everything already on the main queue has run. The engine posts its
    /// install callback with `DispatchQueue.main.async`; this is enqueued after
    /// it, and a serial queue runs them in order — an ordering fact, not a sleep.
    private func drainMain() async {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 5)
    }
}
