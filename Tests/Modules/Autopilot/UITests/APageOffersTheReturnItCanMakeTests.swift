import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// What the page does with a return, and what it says afterwards.
///
/// The section used to carry a comment saying it had no undo, and a page that
/// offers one has three new ways to lie: an item on a row that could only
/// refuse, a report that counts what it tried instead of what worked, and a
/// silence where a file went back under a different name.
@MainActor
final class APageOffersTheReturnItCanMakeTests: XCTestCase {

    private func model(on wire: AutopilotWire) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: wire))
    }

    private func record(_ file: String, run: String? = "pass-1", at hour: Int = 1,
                        undoable: Bool = true) -> ActionRecord {
        // Inside the thirty-day window the section reads through, because a
        // record older than that is not a row and cannot be a group either.
        ActionRecord(at: Date().addingTimeInterval(TimeInterval(hour) * 3600 - 86_400),
                     rule: "Invoices", file: file, kind: .moved, detail: "Invoices",
                     path: "/tmp/watched/" + file,
                     destination: undoable ? "/tmp/watched/Invoices/" + file : "",
                     run: run, ruleID: "r",
                     device: undoable ? 1 : nil, inode: undoable ? 7 : nil)
    }

    private func line(_ file: String, _ outcome: UndoOutcome) -> UndoReport.Line {
        UndoReport.Line(id: file, file: file, outcome: outcome)
    }

    // MARK: - Asking

    func testPressingPutBackSendsTheRecordsOwnId() async throws {
        let wire = AutopilotWire(history: [record("a.pdf")])
        let model = model(on: wire)
        await model.load()
        let row = try XCTUnwrap(model.history.first)

        await model.undo(row)

        XCTAssertTrue(wire.commands.contains(.undo))
        XCTAssertEqual(wire.returns, [row.id])
    }

    func testPuttingAPassBackSendsTheRunId() async throws {
        let wire = AutopilotWire(history: [record("a.pdf"), record("b.pdf", at: 2)])
        let model = model(on: wire)
        await model.load()

        await model.undoRun(try XCTUnwrap(model.runs.first))

        XCTAssertTrue(wire.commands.contains(.undoRun))
        XCTAssertEqual(wire.returns, ["pass-1"])
    }

    /// The history is read back after a return, because what the page is
    /// holding is now out of date in the one way that matters: the rows it
    /// would offer again.
    func testTheHistoryIsReadBackAfterAReturn() async throws {
        let wire = AutopilotWire(history: [record("a.pdf")])
        let model = model(on: wire)
        await model.load()
        // The initialiser starts a load of its own, and a count taken while it
        // is still in flight is a count of a moving target: its history read
        // landed during the `undo` below in 8 constructions of 200, and this
        // line then failed — «3 is not equal to 2» — in full-suite runs only.
        await model.firstLoad?.value
        wire.answers(UndoReport(lines: [line("a.pdf", .restored(to: "/tmp/watched/a.pdf",
                                                                stamped: true))]))
        let readsBefore = wire.commands.filter { $0 == .history }.count

        await model.undo(try XCTUnwrap(model.history.first))

        XCTAssertEqual(wire.commands.filter { $0 == .history }.count, readsBefore + 1,
                       "the page went on offering a return it had already made")
    }

    // MARK: - Saying what happened

    func testACleanReturnSaysHowManyWentBack() async throws {
        let wire = AutopilotWire(history: [record("a.pdf"), record("b.pdf", at: 2)])
        let model = model(on: wire)
        await model.load()
        wire.answers(UndoReport(lines: [
            line("a.pdf", .restored(to: "/tmp/watched/a.pdf", stamped: true)),
            line("b.pdf", .restored(to: "/tmp/watched/b.pdf", stamped: true))
        ]))

        await model.undoRun(try XCTUnwrap(model.runs.first))

        XCTAssertEqual(model.banner, ApStr.putBackReport(2, notPutBack: 0))
    }

    /// **A pass is not atomic, and the sentence must not round.** Two files back
    /// and one refused is not "3 files back", and the reason belongs to the row
    /// it is about.
    func testAHalfReturnNamesEachFailureAndItsReason() async throws {
        let wire = AutopilotWire(history: [record("a.pdf"), record("b.pdf", at: 2)])
        let model = model(on: wire)
        await model.load()
        wire.answers(UndoReport(lines: [
            line("a.pdf", .restored(to: "/tmp/watched/a.pdf", stamped: true)),
            line("b.pdf", .refused(.notTheSameFile))
        ]))

        await model.undoRun(try XCTUnwrap(model.runs.first))

        let banner = try XCTUnwrap(model.banner)
        XCTAssertTrue(banner.contains(ApStr.putBackReport(1, notPutBack: 1)),
                      "«\(banner)» does not say how many did not go back")
        XCTAssertTrue(banner.contains("b.pdf"), "the failure is not named")
        XCTAssertTrue(banner.contains(ApStr.undoRefusal(.notTheSameFile)),
                      "the reason for the failure is not given")
        XCTAssertFalse(banner.contains("a.pdf"),
                       "the file that went back was reported as a problem")
    }

    /// A file that came back under another name is a fact somebody has to be
    /// told, or they go looking for `march.pdf` and it is `march 2.pdf`.
    func testAFileBackUnderAnotherNameIsNamed() async throws {
        let wire = AutopilotWire(history: [record("a.pdf")])
        let model = model(on: wire)
        await model.load()
        wire.answers(UndoReport(lines: [line("a.pdf", .restored(to: "/tmp/watched/a 2.pdf",
                                                                stamped: true))]))

        await model.undo(try XCTUnwrap(model.history.first))

        XCTAssertTrue(model.banner?.contains("a 2.pdf") == true,
                      "«\(model.banner ?? "")» does not say what the file is called now")
    }

    /// The mark did not stick, so the rule takes the file again within the
    /// hour. The one case where the report has something for the person to *do*.
    func testAReturnWithNoMarkWarnsThatTheRuleMayTakeItAgain() async throws {
        let wire = AutopilotWire(history: [record("a.pdf")])
        let model = model(on: wire)
        await model.load()
        wire.answers(UndoReport(lines: [line("a.pdf", .restored(to: "/tmp/watched/a.pdf",
                                                                stamped: false))]))

        await model.undo(try XCTUnwrap(model.history.first))

        XCTAssertTrue(model.banner?.contains(ApStr.ruleMayTakeItAgain) == true,
                      "«\(model.banner ?? "")» does not warn that the rule can take it back")
    }

    // MARK: - What is offered at all

    /// The verdict comes after the press. What the row decides beforehand is
    /// its own shape — a record with no identity could only refuse, and an item
    /// that always refuses is worse than no item.
    func testARowWithNothingToGoBackToIsNotOfferedAReturn() async throws {
        let wire = AutopilotWire(history: [record("gone.pdf", undoable: false)])
        let model = model(on: wire)
        await model.load()
        XCTAssertEqual(model.history.count, 1, "precondition: the row is there")
        XCTAssertFalse(try XCTUnwrap(model.history.first).undoable)
        XCTAssertFalse(model.canPutBack(try XCTUnwrap(model.history.first)))
    }

    // MARK: - Straight after a run

    /// **The moment somebody most wants it.** A rule has just run on a folder
    /// they were watching it do, and the report says it acted on twelve files;
    /// the gesture that belongs beside that sentence is "put those twelve
    /// back", not "scroll down and find the pass".
    func testARunThatActedOffersThatPassBackOnTheBanner() async throws {
        let wire = AutopilotWire(folders: [WatchedFolder(id: "f", path: "/tmp/watched")],
                                 history: [record("a.pdf"), record("b.pdf", at: 2)],
                                 report: SweepReport(folderID: "f", examined: 2, acted: 2,
                                                     refused: 0, failed: 0))
        let model = model(on: wire)
        await model.load()

        await model.runNow(try XCTUnwrap(model.folders.first))

        XCTAssertNotNil(model.banner, "precondition: the run reported something")
        XCTAssertEqual(model.bannerRun?.id, "pass-1")
        XCTAssertEqual(model.bannerRun?.undoable.count, 2)
    }

    /// A run that moved nothing has no pass to offer, and the newest pass in
    /// the history is somebody else's work from an hour ago.
    func testARunThatActedOnNothingOffersNoReturn() async throws {
        let wire = AutopilotWire(folders: [WatchedFolder(id: "f", path: "/tmp/watched")],
                                 history: [record("a.pdf")],
                                 report: SweepReport(folderID: "f", examined: 2, acted: 0,
                                                     refused: 2, failed: 0))
        let model = model(on: wire)
        await model.load()

        await model.runNow(try XCTUnwrap(model.folders.first))

        XCTAssertNotNil(model.banner, "precondition: the run reported something")
        XCTAssertNil(model.bannerRun)
    }

    /// And it goes away with the banner it belongs to.
    func testTheOfferGoesWithTheBanner() async throws {
        let wire = AutopilotWire(folders: [WatchedFolder(id: "f", path: "/tmp/watched")],
                                 history: [record("a.pdf")],
                                 report: SweepReport(folderID: "f", examined: 1, acted: 1,
                                                     refused: 0, failed: 0))
        let model = model(on: wire)
        await model.load()
        await model.runNow(try XCTUnwrap(model.folders.first))
        XCTAssertNotNil(model.bannerRun, "precondition: the offer was made")

        model.dismissBanner()

        XCTAssertNil(model.bannerRun)
    }

    /// A history something else wrote is drawn and offers nothing, because
    /// every return out of it would refuse.
    func testAHistoryThatIsNotHelmsOffersNoReturns() async throws {
        let wire = AutopilotWire(status: AutopilotStatus(refusal: nil, historyRefused: true),
                                 history: [record("a.pdf"), record("b.pdf", at: 2)])
        let model = model(on: wire)

        await model.load()

        XCTAssertEqual(model.history.count, 2, "the section went blank instead of saying why")
        XCTAssertTrue(model.historyRefused)
        XCTAssertEqual(try XCTUnwrap(model.runs.first).canBePutBack, true,
                       "precondition: the pass could be put back but for the seal")
        XCTAssertFalse(model.canPutBack(try XCTUnwrap(model.runs.first)))
        XCTAssertFalse(model.canPutBack(try XCTUnwrap(model.history.first)))
    }
}
