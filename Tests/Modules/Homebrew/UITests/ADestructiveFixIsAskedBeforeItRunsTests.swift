import XCTest
import HelmContract
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
            XCTAssertEqual(HomebrewSettingsPage.fixQuestionNote(uninstall),
                           HbStr.uninstallIsPermanent,
                           "\(language.rawValue): the dialog does not say the removal is permanent")
            XCTAssertNil(HomebrewSettingsPage.fixQuestion(cleanup), """
                \(language.rawValue): `brew cleanup` raises a question — a dialog in front of a \
                recoverable act is how people learn to dismiss dialogs
                """)
        }
    }

    // MARK: - What the press does

    private final class Clinic: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        private let lock = NSLock()
        private var sent: [[String]] = []
        var fired: [[String]] { lock.withLock { sent } }

        func send(_ command: EngineCommand) async throws -> Data {
            if HomebrewCommand(rawValue: command.name) == .doctorFix,
               let argv = try? JSONDecoder().decode([String].self, from: command.payload) {
                lock.withLock { sent.append(argv) }
            }
            return Data()
        }
    }

    private func settle(_ clinic: Clinic, until: () -> Bool) async {
        for _ in 0..<2_000 where !until() { await Task.yield() }
    }

    /// **The recoverable one still goes on the press.** Asserted first: without
    /// it, every «nothing was sent» below is true of a view model that sends
    /// nothing at all.
    func testCleanupStillRunsOnThePress() async {
        let clinic = Clinic()
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: clinic))
        model.askToRunFix(DoctorFix(argv: ["cleanup"], kind: .runnable))
        await settle(clinic) { !clinic.fired.isEmpty }
        XCTAssertEqual(clinic.fired, [["cleanup"]], """
            `brew cleanup` did not reach the engine on the press — so this fake sees no commands \
            at all, and the absences below prove nothing
            """)
        XCTAssertNil(model.pendingFix, "a recoverable fix left a question standing")
    }

    func testTheDestructiveOneReachesNothingUntilItIsConfirmed() async {
        let clinic = Clinic()
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: clinic))
        let fix = DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable)

        model.askToRunFix(fix)
        XCTAssertEqual(model.pendingFix, fix, "the press raised no question")
        await settle(clinic) { !clinic.fired.isEmpty }
        XCTAssertEqual(clinic.fired, [], """
            `brew uninstall periphery` was on its way to the engine before anybody had answered \
            the question — which is the single click, with a dialog drawn over it
            """)

        model.confirmFix()
        await settle(clinic) { !clinic.fired.isEmpty }
        XCTAssertEqual(clinic.fired, [["uninstall", "periphery"]], """
            answering the question ran nothing, so the dialog is the whole feature and the fix \
            cannot be applied at all
            """)
        XCTAssertNil(model.pendingFix)
    }

    /// Declining runs nothing, and the question does not come back — the second
    /// half is `cancelUninstall`'s own lesson: this view model outlives the
    /// page, so a question left standing is one the next visit opens with.
    func testDecliningRunsNothingAndClearsTheQuestion() async {
        let clinic = Clinic()
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: clinic))
        model.askToRunFix(DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable))
        model.cancelFix()
        await settle(clinic) { !clinic.fired.isEmpty }
        XCTAssertEqual(clinic.fired, [], "the fix ran after the person declined it")
        XCTAssertNil(model.pendingFix)
        // And a confirm with nothing pending is not a second door to the act.
        model.confirmFix()
        await settle(clinic) { !clinic.fired.isEmpty }
        XCTAssertEqual(clinic.fired, [], "a confirm with no question standing ran something")
    }

    /// The page presses through the door and not past it, and it retires the
    /// question when it goes away. Structural, the way
    /// `TheStopButtonReachesTheChildTests` pins its own seam: `runDoctorFix` is
    /// private now, so a call to it would not compile — what a reader has to be
    /// stopped from is a *new* unconfirmed path.
    func testThePageAsksAndRetires() throws {
        let source = try String(
            contentsOf: RepoSource.root.appendingPathComponent(
                "Sources/Modules/Homebrew/UI/HomebrewSettingsPage.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("role: .destructive) { hb.askToRunFix(fix) }"),
                      "the Run button no longer asks, or no longer reads as the destructive one")
        XCTAssertTrue(source.contains("hb.cancelFix()"),
                      "the page does not retire a standing question when it goes away")
        XCTAssertTrue(source.contains("role: .destructive) { hb.confirmFix() }"),
                      "the dialog's own button does not read as the destructive one")
    }
}
