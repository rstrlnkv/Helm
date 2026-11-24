import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_KeepAwake_Engine

/// What happens *after* somebody presses Cancel on the removal dialog.
///
/// `ALidThatDidNotWorkSaysSoTests` covers the answer itself: a declined removal
/// leaves the rule where it is and `lidGrantRemains` says so. Both cases here
/// are about the state that answer leaves behind: a local flag must not stand
/// in for a live external fact (Architecture/ModulePattern.md § Ports and logic).
///
/// The settings page sends `settingsChanged` for every control it draws, and
/// the battery floor's `Slider` sends one per rounded value, so asking again
/// «on the next edit» would be six password dialogs for one drag. A declined
/// removal leaves the file on disk, so that would be true from the first edit
/// of every future session. The removal is asked on a gesture that means «take
/// that rule away»: the option's falling edge, as `consumeRisingEdge` gives the
/// install side, and `willDisable` for the module's own switch.
/// `TheRemovalPromptIsAPromptTooTests.testADeclinedRemovalCanBeAskedAgain` holds
/// the other half: a decline is not final.
@MainActor
final class ADeclinedRemovalIsNotAskedForEverTests: XCTestCase {

    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var clamshell: FakeClamshell!
    private var engine: KeepAwakeEngine!

    override func setUp() async throws {
        try await super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        settings = KeepAwakeSettings(store: store)
        clamshell = FakeClamshell()
        // The rule Helm wrote is on disk and grants what it says it grants,
        // which is the state somebody who has used the lid option is in.
        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = true
        settings.setClamshellEnabled(true)
        engine = fakeEngine(settings: settings, store: store, clamshell: clamshell)
    }

    override func tearDown() async throws {
        store = nil
        settings = nil
        clamshell = nil
        engine = nil
        try await super.tearDown()
    }

    /// The control: switching the option off takes the rule out once, which is
    /// the whole point of the removal and must not be what a fix takes away.
    ///
    /// It is counted on the withdrawal rather than on the dialog because the
    /// rule permits its own removal, so the ordinary route raises nothing; the
    /// dialog below is what a rule without that line costs.
    func testSwitchingTheOptionOffTakesTheRuleBackOnce() async {
        settings.setClamshellEnabled(false)
        engine.settingsChanged()
        await removalRan(on: clamshell)

        XCTAssertEqual(clamshell.passwordlessRemovals, 1)
        XCTAssertEqual(clamshell.removeCalls, 0, "nothing to ask a password for")
    }

    /// Cancel, then edit anything else on the page.
    ///
    /// Every edit is a `settingsChanged`, and each one finds the same true
    /// answer — the option is off, our rule is on disk — so each one puts an
    /// administrator password dialog on screen for a decision the person has
    /// already made. The `await drainMainActor()` between them lets
    /// `removalInFlight` clear, as the person answering the dialog does; without
    /// it this case would pass on the in-flight guard instead.
    func testAnUnrelatedEditAfterACancelDoesNotRaiseTheDialogAgain() async {
        clamshell.withdrawalIsGranted = false
        clamshell.removalSucceeds = false
        settings.setClamshellEnabled(false)
        engine.settingsChanged()
        await removalRan(on: clamshell)
        XCTAssertEqual(clamshell.removeCalls, 1, "precondition: it was asked, and declined")
        XCTAssertTrue(clamshell.isSudoersInstalled(),
                      "precondition: Cancel leaves our file exactly where it was")

        // Three ordinary edits of some other control — the battery floor's
        // slider sends one of these per change.
        for _ in 0..<3 {
            engine.settingsChanged()
            await drainMainActor()
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
    /// an administrator then takes the file out by hand it is false, so the row
    /// reads the file (`fileExists` on a `0755` directory) rather than
    /// remembering.
    func testTheClaimStopsWhenTheRuleIsTakenOutBehindTheAppsBack() async {
        clamshell.withdrawalIsGranted = false
        clamshell.removalSucceeds = false
        settings.setClamshellEnabled(false)
        engine.settingsChanged()
        await removalRan(on: clamshell)
        XCTAssertTrue(engine.lidGrantRemains, "precondition: declined, so the rule is still there")

        // An administrator removes it from the terminal. Nothing tells the app.
        clamshell.sudoersInstalled = false
        clamshell.passwordlessGrantExists = false
        engine.settingsChanged()
        await drainMainActor()

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
        engine.settingsChanged()
        await removalRan(on: clamshell)
        XCTAssertTrue(engine.lidGrantRemains, "precondition")

        engine.settingsChanged()
        await drainMainActor()

        XCTAssertTrue(engine.lidGrantRemains,
                      "the page stopped naming a rule that is still granting passwordless "
                      + "`pmset disablesleep` to this account")
    }
}
