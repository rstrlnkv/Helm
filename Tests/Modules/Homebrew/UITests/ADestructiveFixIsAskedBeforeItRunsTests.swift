import XCTest
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **«Run» ran `brew uninstall periphery` on one click, six points from
/// «Copy».**
///
/// Measured 2026-09-16 on the inspector: «Скопировать» 106.5×24 at x 675.5…782
/// and «Выполнить» 93.5×24 at x 788 — a 6 pt gap, no weight difference, no
/// role, no question. `DoctorFix.Allowed` holds two commands and only one of
/// them is recoverable: a cached download comes back, and a cellar directory
/// does not. Every other irreversible deletion in Helm asks first, and the
/// Uninstall button three lines up the same file raises a dialog that names the
/// package and says what it takes with it.
///
/// **What makes this a guard rather than a claim about a `role:`.** The
/// behaviour is what is asserted: the press does not reach the engine at all
/// until the question is answered, and the cleanup press still does — otherwise
/// «nothing was sent» would be true of a view model with the command deleted.
@MainActor
final class ADestructiveFixIsAskedBeforeItRunsTests: XCTestCase {

    // MARK: - The decision

    func testTheTwoAllowedCommandsAreNotTheSameKindOfAct() {
        XCTAssertEqual(FixAsk.of(["cleanup"]), .runsOnThePress)
        XCTAssertEqual(FixAsk.of(["uninstall", "periphery"]), .uninstalls(name: "periphery"), """
            a fix that removes a package for good was read as one to run on the press — which is \
            the single click this whole file is about
            """)
    }

    /// **Anything else asks too.** `DoctorFix.judge` is argument-exact, so
    /// nothing outside those two reaches Run today; that is a fact about today's
    /// allowlist, and a third entry added by somebody who did not read
    /// `DoctorFix.Allowed`'s checklist gets a question rather than a press.
    func testAnUnrecognisedCommandIsAskedAboutRatherThanRun() {
        XCTAssertEqual(FixAsk.of(["update-reset"]), .unrecognised)
        XCTAssertEqual(FixAsk.of(["untap", "somebody/tap"]), .unrecognised)
        // Argument-exact in this direction as well: `cleanup --prune=all` throws
        // away every cached download regardless of age, which is not the act
        // `cleanup` performs.
        XCTAssertEqual(FixAsk.of(["cleanup", "--prune=all"]), .unrecognised)
    }

    // MARK: - The words

    /// The question names the package, in the words the Uninstall button's own
    /// dialog uses — one key, one act, eight translations already written for
    /// it. Checked in every language, because the sentence is the whole of what
    /// a person decides on and this Mac reads one of the eight.
    func testTheQuestionNamesThePackageTheWayTheUninstallDialogDoes() {
        let uninstall = DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable)
        let cleanup = DoctorFix(argv: ["cleanup"], kind: .runnable)
        AppLanguage.each { language in
            XCTAssertEqual(HomebrewSettingsPage.fixQuestion(uninstall),
                           HbStr.confirmUninstall("periphery"), """
                \(language.rawValue): the question a press on Run raises is not the one the \
                Uninstall button asks about the same act
                """)
            XCTAssertEqual(HomebrewSettingsPage.fixQuestionNote(uninstall, dependents: []),
                           HbStr.uninstallIsPermanent,
                           "\(language.rawValue): the dialog does not say the removal is permanent")
            XCTAssertNil(HomebrewSettingsPage.fixQuestion(cleanup), """
                \(language.rawValue): `brew cleanup` raises a question — a dialog in front of a \
                recoverable act is how people learn to dismiss dialogs
                """)
        }
    }

    // MARK: - What the press does

    /// The argv of every doctor fix the fake was asked to run, in order.
    private func fired(_ work: FakeHomebrewWork) -> [[String]] {
        work.acts.compactMap { act in
            if case .doctorFix(let argv) = act { return argv }
            return nil
        }
    }

    private func settle(_ work: FakeHomebrewWork, until: () -> Bool) async {
        for _ in 0..<2_000 where !until() { await Task.yield() }
    }

    /// **The recoverable one still goes on the press.** Asserted first: without
    /// it, every «nothing was sent» below is true of a view model that sends
    /// nothing at all.
    func testCleanupStillRunsOnThePress() async {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)
        await model.askToRunFix(DoctorFix(argv: ["cleanup"], kind: .runnable))
        await settle(work) { !fired(work).isEmpty }
        XCTAssertEqual(fired(work), [["cleanup"]], """
            `brew cleanup` did not reach the engine on the press — so this fake sees no commands \
            at all, and the absences below prove nothing
            """)
        XCTAssertNil(model.pendingFix, "a recoverable fix left a question standing")
    }

    func testTheDestructiveOneReachesNothingUntilItIsConfirmed() async {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)
        let fix = DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable)

        await model.askToRunFix(fix)
        XCTAssertEqual(model.pendingFix, fix, "the press raised no question")
        await settle(work) { !fired(work).isEmpty }
        XCTAssertEqual(fired(work), [], """
            `brew uninstall periphery` was on its way to the engine before anybody had answered \
            the question — which is the single click, with a dialog drawn over it
            """)

        model.confirmFix()
        await settle(work) { !fired(work).isEmpty }
        XCTAssertEqual(fired(work), [["uninstall", "periphery"]], """
            answering the question ran nothing, so the dialog is the whole feature and the fix \
            cannot be applied at all
            """)
        XCTAssertNil(model.pendingFix)
    }

    /// Declining runs nothing, and the question does not come back — the second
    /// half is `cancelUninstall`'s own lesson: this view model outlives the
    /// page, so a question left standing is one the next visit opens with.
    func testDecliningRunsNothingAndClearsTheQuestion() async {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)
        await model.askToRunFix(DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable))
        model.cancelFix()
        await settle(work) { !fired(work).isEmpty }
        XCTAssertEqual(fired(work), [], "the fix ran after the person declined it")
        XCTAssertNil(model.pendingFix)
        // And a confirm with nothing pending is not a second door to the act.
        model.confirmFix()
        await settle(work) { !fired(work).isEmpty }
        XCTAssertEqual(fired(work), [], "a confirm with no question standing ran something")
    }

    // MARK: - What it takes with it

    /// **The fix's dialog reads what depends on the package before it asks** —
    /// the Uninstall button's reading, through the same function. Nothing runs
    /// before the answer, and the sentence is the one the other dialog draws.
    func testTheFixDialogShowsWhatStillNeedsThePackageBeforeAnythingRuns() async {
        let work = FakeHomebrewWork()
        work.dependents = ["aria2", "node"]
        let model = HomebrewViewModel(work: work)
        let fix = DoctorFix(argv: ["uninstall", "openssl@3"], kind: .runnable)

        await model.askToRunFix(fix)
        XCTAssertEqual(work.dependentsAsked, [PackageRef(name: "openssl@3", isCask: false)],
                       "the fix's question did not read the dependents")
        XCTAssertEqual(model.pendingFix, fix, "the control: the question was not raised")
        XCTAssertEqual(model.dependentsOfPending, ["aria2", "node"])
        XCTAssertEqual(HomebrewSettingsPage.fixQuestionNote(fix, dependents: model.dependentsOfPending),
                       HomebrewSettingsPage.uninstallNote(dependents: ["aria2", "node"]))
        XCTAssertTrue(HomebrewSettingsPage.uninstallNote(dependents: ["aria2", "node"])
                        .hasSuffix(HbStr.stillNeededBy + "\naria2, node"))
        XCTAssertEqual(fired(work), [], "`brew uninstall` was sent before the question was answered")

        model.confirmFix()
        XCTAssertEqual(fired(work), [["uninstall", "openssl@3"]])
        XCTAssertEqual(model.dependentsOfPending, [], "the reading outlived its question")
    }

    /// A reading that did not answer is not «nothing depends on it»: the
    /// question is still asked, with no list and no reassurance.
    func testAFailedDependentsReadIsNotAReassuranceInTheFixDialog() async {
        let work = FakeHomebrewWork()
        work.dependents = nil
        let model = HomebrewViewModel(work: work)
        let fix = DoctorFix(argv: ["uninstall", "openssl@3"], kind: .runnable)

        await model.askToRunFix(fix)
        XCTAssertEqual(work.dependentsAsked.count, 1, "control: nothing was read")
        XCTAssertEqual(model.pendingFix, fix)
        XCTAssertEqual(model.dependentsOfPending, [])
        let note = HomebrewSettingsPage.fixQuestionNote(fix, dependents: model.dependentsOfPending)
        XCTAssertEqual(note, HbStr.uninstallIsPermanent)
        XCTAssertFalse(note?.contains(HbStr.stillNeededBy) ?? true)
        XCTAssertEqual(fired(work), [])
    }

    /// Declining or leaving retires a read still out: its answer raises nothing.
    func testACancelledFixAskRaisesNothingWhenItsReadComesBack() async {
        let work = FakeHomebrewWork()
        work.dependents = ["node"]
        work.park("readDependents")
        let model = HomebrewViewModel(work: work)
        let ask = Task { await model.askToRunFix(DoctorFix(argv: ["uninstall", "openssl@3"], kind: .runnable)) }
        await eventually("the read is out") { work.calls.contains("readDependents openssl@3") }
        model.cancelFix()
        work.release("readDependents")
        await ask.value
        XCTAssertNil(model.pendingFix, "a cancelled ask raised its dialog")
        XCTAssertEqual(model.dependentsOfPending, [])
    }

    /// A fix that is not an uninstall has no package to ask about: `cleanup`
    /// runs on the press and an unrecognised command waits for its answer, and
    /// neither reads dependents (a reading no dialog would show is a `brew uses`
    /// launched for nothing).
    func testOnlyAnUninstallFixReadsDependents() async {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)
        await model.askToRunFix(DoctorFix(argv: ["cleanup"], kind: .runnable))
        await settle(work) { !fired(work).isEmpty }
        XCTAssertEqual(fired(work), [["cleanup"]], "control: the cleanup press did not reach the engine")
        XCTAssertEqual(work.dependentsAsked, [], "a cleanup press read what depends on a package")
        XCTAssertEqual(model.dependentsOfPending, [])

        let unrecognised = DoctorFix(argv: ["foo"], kind: .runnable)
        await model.askToRunFix(unrecognised)
        XCTAssertEqual(model.pendingFix, unrecognised, "control: the unrecognised ask raised no question")
        XCTAssertEqual(work.dependentsAsked, [], "an unrecognised command read what depends on a package")
    }
}
