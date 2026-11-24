import XCTest
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **«Run» on a doctor fix asks before it runs.**
///
/// `DoctorFix.Allowed` holds one command, an uninstall, and a Cellar directory
/// does not come back. Run sits beside Copy, and every other irreversible
/// deletion in Helm asks first, as the Uninstall button does.
///
/// The behaviour is asserted: the press does not reach the engine until the
/// question is answered, and the confirmed press does, so «nothing was sent» is
/// not met by a view model with the command deleted.
@MainActor
final class ADestructiveFixIsAskedBeforeItRunsTests: XCTestCase {

    // MARK: - The decision

    func testAnUninstallIsAskedAbout() {
        XCTAssertEqual(FixAsk.of(["uninstall", "periphery"]), .uninstalls(name: "periphery"), """
            a fix that removes a package for good was read as one to run on the press — which is \
            the single click this whole file is about
            """)
    }

    /// **Anything else asks too.** Only one command reaches Run, but a second
    /// entry added by somebody who did not read `DoctorFix.Allowed`'s checklist
    /// gets a question rather than a press.
    func testAnUnrecognisedCommandIsAskedAboutRatherThanRun() {
        XCTAssertEqual(FixAsk.of(["update-reset"]), .unrecognised)
        XCTAssertEqual(FixAsk.of(["untap", "somebody/tap"]), .unrecognised)
        XCTAssertEqual(FixAsk.of(["cleanup"]), .unrecognised)
        XCTAssertEqual(FixAsk.of(["cleanup", "--prune=all"]), .unrecognised)
    }

    // MARK: - The words

    /// The question names the package in the Uninstall dialog's own words, one
    /// key for one act, checked in every language: the sentence is the whole of
    /// what a person decides on.
    func testTheQuestionNamesThePackageTheWayTheUninstallDialogDoes() {
        let uninstall = DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable)
        AppLanguage.each { language in
            XCTAssertEqual(HomebrewSettingsPage.fixQuestion(uninstall),
                           HbStr.confirmUninstall("periphery"), """
                \(language.rawValue): the question a press on Run raises is not the one the \
                Uninstall button asks about the same act
                """)
            XCTAssertEqual(HomebrewSettingsPage.fixQuestionNote(uninstall, dependents: .read([])),
                           HbStr.uninstallIsPermanent,
                           "\(language.rawValue): the dialog does not say the removal is permanent")
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

    func testTheDestructiveOneReachesNothingUntilItIsConfirmed() async {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)
        let fix = DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable)

        await model.askToRunFix(fix)
        XCTAssertEqual(model.pendingFix, fix, "the press raised no question")
        XCTAssertEqual(fired(work), [], """
            `brew uninstall periphery` was on its way to the engine before anybody had answered \
            the question — which is the single click, with a dialog drawn over it
            """)

        model.confirmFix()
        XCTAssertEqual(fired(work), [["uninstall", "periphery"]], """
            answering the question ran nothing, so the dialog is the whole feature and the fix \
            cannot be applied at all
            """)
        XCTAssertNil(model.pendingFix)
    }

    /// Declining runs nothing, and the question does not come back: this view
    /// model outlives the page, so a question left standing is one the next
    /// visit opens with.
    func testDecliningRunsNothingAndClearsTheQuestion() async {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)
        await model.askToRunFix(DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable))
        model.cancelFix()
        XCTAssertEqual(fired(work), [], "the fix ran after the person declined it")
        XCTAssertNil(model.pendingFix)
        // And a confirm with nothing pending is not a second door to the act.
        model.confirmFix()
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
        XCTAssertEqual(model.dependentsOfPending, .read(["aria2", "node"]))
        XCTAssertEqual(HomebrewSettingsPage.fixQuestionNote(fix, dependents: model.dependentsOfPending),
                       HomebrewSettingsPage.uninstallNote(dependents: .read(["aria2", "node"])))
        XCTAssertTrue(HomebrewSettingsPage.uninstallNote(dependents: .read(["aria2", "node"]))
                        .hasSuffix(HbStr.stillNeededBy + "\naria2, node"))
        XCTAssertEqual(fired(work), [], "`brew uninstall` was sent before the question was answered")

        model.confirmFix()
        XCTAssertEqual(fired(work), [["uninstall", "openssl@3"]])
        XCTAssertEqual(model.dependentsOfPending, .notAsked, "the reading outlived its question")
    }

    /// A reading that did not answer is not «nothing depends on it»: the
    /// question is still asked, with no list and no reassurance, and one
    /// sentence that the reading failed.
    func testAFailedDependentsReadIsNotAReassuranceInTheFixDialog() async {
        let work = FakeHomebrewWork()
        work.dependents = nil
        let model = HomebrewViewModel(work: work)
        let fix = DoctorFix(argv: ["uninstall", "openssl@3"], kind: .runnable)

        await model.askToRunFix(fix)
        XCTAssertEqual(work.dependentsAsked.count, 1, "control: nothing was read")
        XCTAssertEqual(model.pendingFix, fix)
        XCTAssertEqual(model.dependentsOfPending, .unread)
        let note = HomebrewSettingsPage.fixQuestionNote(fix, dependents: model.dependentsOfPending)
        XCTAssertEqual(note, HbStr.uninstallIsPermanent + "\n\n" + HbStr.dependentsUnread)
        XCTAssertFalse(note?.contains(HbStr.stillNeededBy) ?? true)
        AppLanguage.each { language in
            let said = HomebrewSettingsPage.uninstallNote(dependents: .unread)
            XCTAssertTrue(said.hasSuffix(HbStr.dependentsUnread), "\(language): the unread sentence is missing")
        }
        XCTAssertEqual(fired(work), [])
    }

    /// Declining or leaving retires a read still out: its answer raises nothing.
    func testACancelledFixAskRaisesNothingWhenItsReadComesBack() async {
        let work = FakeHomebrewWork()
        work.dependents = ["node"]
        work.park("readDependents")
        let model = HomebrewViewModel(work: work)
        let ask = Task { await model.askToRunFix(DoctorFix(argv: ["uninstall", "openssl@3"], kind: .runnable)) }
        await waitUntil("the read is out") { work.calls.contains("readDependents openssl@3") }
        model.cancelFix()
        work.release("readDependents")
        await ask.value
        XCTAssertNil(model.pendingFix, "a cancelled ask raised its dialog")
        XCTAssertEqual(model.dependentsOfPending, .notAsked)
    }

    /// A fix that is not an uninstall has no package to ask about: an unrecognised
    /// command waits for its answer and reads no dependents (a reading no dialog would show is a `brew uses`
    /// launched for nothing).
    func testOnlyAnUninstallFixReadsDependents() async {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)
        let unrecognised = DoctorFix(argv: ["foo"], kind: .runnable)
        await model.askToRunFix(unrecognised)
        XCTAssertEqual(model.pendingFix, unrecognised, "control: the unrecognised ask raised no question")
        XCTAssertEqual(work.dependentsAsked, [], "an unrecognised command read what depends on a package")
    }

    // MARK: - The question waits for the reading

    /// **The dialog is raised with its list or not at all.** While the read is
    /// out nothing stands; a dialog raised first would show «nothing needs it»
    /// for as long as `brew uses` takes, and Run would be one click from a
    /// deletion the person has not been told the cost of.
    func testTheFixDialogIsNotRaisedWhileTheDependentsReadIsOut() async {
        let work = FakeHomebrewWork()
        work.dependents = ["aria2", "node"]
        work.park("readDependents")
        let model = HomebrewViewModel(work: work)
        let fix = DoctorFix(argv: ["uninstall", "openssl@3"], kind: .runnable)
        let ask = Task { await model.askToRunFix(fix) }
        await waitUntil("the read is out") { work.calls.contains("readDependents openssl@3") }
        XCTAssertEqual(work.dependentsAsked, [PackageRef(name: "openssl@3", isCask: false)],
                       "control: the read is not out")
        XCTAssertNil(model.pendingFix, "the fix's dialog was raised before the dependents came back")
        XCTAssertEqual(model.dependentsOfPending, .notAsked)

        work.release("readDependents")
        await ask.value
        XCTAssertEqual(model.pendingFix, fix, "the answer did not raise the question")
        XCTAssertEqual(model.dependentsOfPending, .read(["aria2", "node"]))
        XCTAssertEqual(fired(work), [])
    }

    /// The Uninstall button's door through the same function, the same rule.
    func testTheUninstallDialogIsNotRaisedWhileTheDependentsReadIsOut() async {
        let work = FakeHomebrewWork()
        work.dependents = ["aria2", "node"]
        work.park("readDependents")
        let model = HomebrewViewModel(work: work)
        let wget = BrewPackage(name: "wget", version: "1.25", isCask: false)
        let ask = Task { await model.askToUninstall(wget) }
        await waitUntil("the read is out") { work.calls.contains("readDependents wget") }
        XCTAssertEqual(work.dependentsAsked, [PackageRef(name: "wget", isCask: false)],
                       "control: the read is not out")
        XCTAssertNil(model.pendingUninstall, "the uninstall dialog was raised before the dependents came back")
        XCTAssertEqual(model.dependentsOfPending, .notAsked)

        work.release("readDependents")
        await ask.value
        XCTAssertEqual(model.pendingUninstall, wget, "the answer did not raise the question")
        XCTAssertEqual(model.dependentsOfPending, .read(["aria2", "node"]))
    }
}
