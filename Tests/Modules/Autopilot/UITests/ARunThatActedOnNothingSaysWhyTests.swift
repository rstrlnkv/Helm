import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **«Acted on 0 of 3» is what a refusal on every file looks like.**
///
/// `SweepReport` carries `refused` and `failed`; the banner took `acted` and
/// `examined` alone, so a Run now that refused every file said the same thing as
/// a Run now over a folder where nothing matched. And the record that explains
/// it — a history row per file, with the reason — was already written by the time
/// the banner was drawn and was not asked for, because the page's own
/// `.task { loadHistory() }` had run once when the list appeared.
///
/// So the one moment a person is looking straight at the module, having pressed
/// the button whose whole purpose is "show me that this works", it held the
/// answer and showed a number that reads as "nothing here matched".
@MainActor
final class ARunThatActedOnNothingSaysWhyTests: XCTestCase {

    private func model(on wire: AutopilotWire) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: wire))
    }

    private let folder = WatchedFolder(id: "downloads", path: "/tmp/watched")

    private func refusals(_ count: Int) -> [ActionRecord] {
        (0..<count).map {
            ActionRecord(at: Date(), rule: "Invoices", file: "\($0).pdf", kind: .refused,
                         detail: "outOfScope", path: "/tmp/watched/\($0).pdf")
        }
    }

    // MARK: - The record that explains it

    /// The control: a run really does reach the wire and set a banner, so the
    /// assertions below are about a page that has just run.
    func testARunReachesTheEngine() async {
        let wire = AutopilotWire(folders: [folder],
                                 report: SweepReport(folderID: folder.id, examined: 3,
                                                     acted: 3, refused: 0, failed: 0))
        let model = model(on: wire)
        await model.load()

        await model.runNow(folder)

        XCTAssertTrue(wire.commands.contains(.runNow), "precondition: the run was sent")
        XCTAssertNotNil(model.banner, "precondition: the run reported something")
    }

    func testARunThatRefusedEveryFileLoadsTheRecordThatExplainsIt() async {
        let wire = AutopilotWire(folders: [folder],
                                 report: SweepReport(folderID: folder.id, examined: 3,
                                                     acted: 0, refused: 2, failed: 0))
        let model = model(on: wire)
        await model.load()
        XCTAssertEqual(model.history, [], "precondition: the page opened on an empty history")

        // What the engine wrote while the sweep ran, which is what the page is
        // about to be asked to explain.
        wire.holds(refusals(2))
        await model.runNow(folder)

        XCTAssertEqual(model.history.count, 2,
                       "the page holds the answer, was told it, and did not read it back")
    }

    // MARK: - What the banner says

    func testTheBannerNamesWhatWasNotCompleted() async {
        let wire = AutopilotWire(folders: [folder],
                                 report: SweepReport(folderID: folder.id, examined: 3,
                                                     acted: 0, refused: 2, failed: 0))
        let model = model(on: wire)
        await model.load()

        await model.runNow(folder)

        XCTAssertEqual(model.banner, ApStr.swept(0, 3, notCompleted: 2),
                       "«\(model.banner ?? "")» is what a refusal on every file looked like")
    }

    /// Refusals and failures are one figure: both mean a file the rule meant to
    /// act on is still where it was, and a person reading a banner does not need
    /// the difference — the history rows carry it.
    func testAFailureCountsWithTheRefusals() {
        XCTAssertEqual(ApStr.swept(0, 3, notCompleted: 3), ApStr.swept(0, 3, notCompleted: 3))
        XCTAssertNotEqual(ApStr.swept(0, 3, notCompleted: 0), ApStr.swept(0, 3, notCompleted: 3))
    }

    /// And a clean run is the sentence it always was: the tail appears only when
    /// there is something in it. In every language, because a composition that
    /// works in English can put a stray separator in the seven that are not it.
    func testACleanRunSaysNothingAboutProblems() {
        for language in AppLanguage.allCases {
            let clean = ApStr.swept(3, 3, notCompleted: 0, language: language)
            XCTAssertEqual(clean, ApStr.swept(3, 3, language: language),
                           "a clean run grew a tail in \(language.rawValue)")
            let problems = ApStr.swept(0, 3, notCompleted: 2, language: language)
            XCTAssertTrue(problems.hasPrefix(ApStr.swept(0, 3, language: language)),
                          "the tail replaced the sentence it was added to in \(language.rawValue)")
            XCTAssertTrue(problems.contains(ApStr.historyProblems(2, language: language)),
                          "the tail lost its own sentence in \(language.rawValue)")
        }
    }
}
