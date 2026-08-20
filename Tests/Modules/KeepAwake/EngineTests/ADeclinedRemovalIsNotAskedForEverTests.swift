import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_KeepAwake_Engine

/// What happens *after* somebody presses Cancel on the removal dialog.
///
/// `ALidThatDidNotWorkSaysSoTests` covers the answer itself: a declined removal
/// leaves the rule where it is and `lidGrantRemains` says so. Both cases here
/// are about the state that answer leaves behind, and both are the family
/// CLAUDE.md names — a local flag standing in for a live external fact, with the
/// reverse channel sitting unread in the same method.
///
/// `releaseIfUnneeded()` is called from the `settingsChanged` command, which the
/// settings page sends **for every control it draws** — a stepper sends one per
/// press. `removalInFlight` covers the seconds a dialog is on screen and is
/// cleared when it is answered, deliberately, «because a declined removal has to
/// be askable again». Nothing decides *when* it is asked again: the answer is
/// «on the next edit of any setting in the module», which is the same five
/// dialogs for five ordinary edits that the in-flight flag was added to stop,
/// moved one state along. The install side of the same file already has the
/// answer — `consumeRisingEdge`, the switch's own edge, «because acting on the
/// value put a dialog in front of somebody for every later edit of an unrelated
/// setting».
///
/// The control that shows what that costs is the battery floor, which is a
/// `Slider`: its binding saves on every distinct rounded value, so one drag from
/// 20 % to 50 % is six `settingsChanged` — six administrator password dialogs.
/// And the state is not transient. A declined removal leaves the file on disk,
/// so the next launch is in the same position with nothing remembered: `guard
/// !settings.clamshellEnabled` and `isSudoersInstalled()` are both true from the
/// first edit of every future session.
///
/// **This contradicts `TheRemovalPromptIsAPromptTooTests.testADeclinedRemovalCanBeAskedAgain`,
/// deliberately, and one of the two has to give.** That case sends two bare
/// `settingsChanged` and requires the second to ask — which is right about the
/// intent (a decline must not be final) and wrong about the trigger, because
/// «any edit of any setting» is the trigger that produces the six dialogs above.
/// Both are satisfiable together by asking on a gesture that means «take that
/// rule away»: the option's falling edge, the same shape `consumeRisingEdge`
/// already gives the install side, and `willDisable` for the module's own
/// switch. Written that way, the older case drives the switch off→on→off
/// instead of sending two messages that say nothing changed, and both pass.
@MainActor
final class ADeclinedRemovalIsNotAskedForEverTests: XCTestCase {

    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var clamshell: FakeClamshell!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        settings = KeepAwakeSettings(store: store)
        clamshell = FakeClamshell()
        // The rule Helm wrote is on disk and grants what it says it grants,
        // which is the state somebody who has used the lid option is in.
        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = true
        settings.setClamshellEnabled(true)
        engine = KeepAwakeEngine(settings: settings, store: store,
                                 assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(), power: FakePower(),
                                 apps: FakeApps(), pointer: FakePointer(),
                                 clamshell: clamshell, clock: FakeClock())
    }

    override func tearDown() {
        store = nil
        settings = nil
        clamshell = nil
        engine = nil
        super.tearDown()
    }

    /// The control: switching the option off takes the rule out once, which is
    /// the whole point of the removal and must not be what a fix takes away.
    ///
    /// It is counted on the withdrawal rather than on the dialog because the
    /// rule permits its own removal now, so the ordinary route raises nothing —
    /// the dialog below is what a rule *older than that line* still costs.
    func testSwitchingTheOptionOffTakesTheRuleBackOnce() async {
        settings.setClamshellEnabled(false)
        engine.settingsChangedForTests()
        await removalRan(on: clamshell)

        XCTAssertEqual(clamshell.passwordlessRemovals, 1)
        XCTAssertEqual(clamshell.removeCalls, 0, "nothing to ask a password for")
    }

    /// Cancel, then edit anything else on the page.
    ///
    /// Every edit is a `settingsChanged`, and each one finds the same true
    /// answer — the option is off, our rule is on disk — so each one puts an
    /// administrator password dialog on screen for a decision the person has
    /// already made. The `await settle()` between them is not decoration: it is
    /// what lets `removalInFlight` clear, which is exactly what the person
    /// answering the dialog does, and without it this case would pass on a
    /// guard that has nothing to do with the defect.
    func testAnUnrelatedEditAfterACancelDoesNotRaiseTheDialogAgain() async {
        clamshell.withdrawalIsGranted = false
        clamshell.removalSucceeds = false
        settings.setClamshellEnabled(false)
        engine.settingsChangedForTests()
        await removalRan(on: clamshell)
        XCTAssertEqual(clamshell.removeCalls, 1, "precondition: it was asked, and declined")
        XCTAssertTrue(clamshell.isSudoersInstalled(),
                      "precondition: Cancel leaves our file exactly where it was")

        // Three ordinary edits of some other control — the battery floor's
        // stepper sends one of these per press.
        for _ in 0..<3 {
            engine.settingsChangedForTests()
            await settle()
        }

        XCTAssertEqual(clamshell.removeCalls, 1,
                       "one administrator password dialog per unrelated settings edit, for a "
                       + "decision that was already answered")
    }

    /// And the flag the row draws is a memory of one call, not a reading.
    ///
    /// «A passwordless `pmset` rule is still installed» is a claim about
    /// `/etc/sudoers.d` — a directory this account cannot write and anything
    /// with a password can. Once the removal is declined the claim is true; when
    /// an administrator then takes the file out by hand it is false, and nothing
    /// here ever looks again. The look is `fileExists` on a `0755` directory,
    /// and `removeGrant` already does it — in a `guard` whose `else` throws the
    /// answer away.
    func testTheClaimStopsWhenTheRuleIsTakenOutBehindTheAppsBack() async {
        clamshell.withdrawalIsGranted = false
        clamshell.removalSucceeds = false
        settings.setClamshellEnabled(false)
        engine.settingsChangedForTests()
        await removalRan(on: clamshell)
        XCTAssertTrue(engine.lidGrantRemains, "precondition: declined, so the rule is still there")

        // An administrator removes it from the terminal. Nothing tells the app.
        clamshell.sudoersInstalled = false
        clamshell.passwordlessGrantExists = false
        engine.settingsChangedForTests()
        await settle()

        XCTAssertFalse(engine.lidGrantRemains,
                       "the row goes on naming a passwordless root rule that is not there, and "
                       + "the only thing it offers is a way to remove it again")
    }

    /// The other side of that reading, so the repair cannot be «clear it»: while
    /// the rule really is still on disk, the complaint stands.
    func testTheClaimStandsWhileTheRuleIsStillThere() async {
        clamshell.withdrawalIsGranted = false
        clamshell.removalSucceeds = false
        settings.setClamshellEnabled(false)
        engine.settingsChangedForTests()
        await removalRan(on: clamshell)
        XCTAssertTrue(engine.lidGrantRemains, "precondition")

        engine.settingsChangedForTests()
        await settle()

        XCTAssertTrue(engine.lidGrantRemains,
                      "the page stopped naming a rule that is still granting passwordless "
                      + "`pmset disablesleep` to this account")
    }

    /// The removal's callback records its verdict on the main actor. Awaiting a
    /// hop of our own is what puts this after it; a serial executor runs them in
    /// order, so this is an ordering fact rather than a sleep.
    private func settle() async { await drainMainActor() }
}
