import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The one line in a return's report that has something to *do* about it.
///
/// When the mark that stops a rule acting twice could not be re-written, the
/// rule takes the file again within the hour — and the warning that says so used
/// to be the whole of it, a sentence with no lever beside it. The lever is a
/// button per rule that could not be re-marked, named, because a person with
/// four rules needs to know which one is about to take the file back.
@MainActor
final class AReturnOffersToTurnOffTheRuleTests: XCTestCase {

    private func model(on wire: AutopilotWire) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: wire))
    }

    /// A folder holding the rule the record names, so turning it off has
    /// something to switch. The rule's id matches the record's `ruleID`.
    private func folder(ruleEnabled: Bool = true) -> WatchedFolder {
        WatchedFolder(id: "f", path: "/tmp/watched",
                      rules: [Rule(id: "r", name: "Invoices", enabled: ruleEnabled,
                                   action: .sortIntoSubfolder(.kind))])
    }

    private func record(_ file: String = "a.pdf") -> ActionRecord {
        ActionRecord(at: Date().addingTimeInterval(3600 - 86_400),
                     rule: "Invoices", file: file, kind: .moved, detail: "Invoices",
                     path: "/tmp/watched/" + file,
                     destination: "/tmp/watched/Invoices/" + file,
                     run: "pass-1", ruleID: "r", device: 1, inode: 7)
    }

    /// The report line's id is the record's id — the way the engine builds it —
    /// so the page can walk from the line back to the rule that made it.
    private func unstuck(_ record: ActionRecord) -> UndoReport {
        UndoReport(lines: [UndoReport.Line(id: record.id, file: record.file,
                                           outcome: .restored(to: record.destination,
                                                              stamped: false))])
    }

    func testAReturnThatCouldNotReMarkOffersToTurnTheRuleOff() async throws {
        let row = record()
        let wire = AutopilotWire(folders: [folder()], history: [row])
        let model = model(on: wire)
        await model.load()
        wire.answers(unstuck(row))

        await model.undo(try XCTUnwrap(model.history.first))

        XCTAssertEqual(model.unmarkedRules.map(\.name), ["Invoices"],
                       "the warning fired but no rule was offered to turn off")
    }

    /// A return whose mark did stick has nothing to warn about and nothing to
    /// offer — the button appears only where the warning does.
    func testACleanReturnOffersNoRuleToTurnOff() async throws {
        let row = record()
        let wire = AutopilotWire(folders: [folder()], history: [row])
        let model = model(on: wire)
        await model.load()
        wire.answers(UndoReport(lines: [UndoReport.Line(id: row.id, file: row.file,
                                        outcome: .restored(to: row.destination, stamped: true))]))

        await model.undo(try XCTUnwrap(model.history.first))

        XCTAssertTrue(model.unmarkedRules.isEmpty,
                      "a rule was offered to turn off with nothing to warn about")
    }

    /// Pressing it switches the named rule off and saves — the same write path a
    /// rule's own toggle takes — and takes the offer down with it.
    func testTurningTheRuleOffDisablesItAndSaves() async throws {
        let row = record()
        let wire = AutopilotWire(folders: [folder()], history: [row])
        let model = model(on: wire)
        await model.load()
        wire.answers(unstuck(row))
        await model.undo(try XCTUnwrap(model.history.first))
        let offered = try XCTUnwrap(model.unmarkedRules.first)

        model.turnOffRule(offered)

        // The rule is off in the model straight away, and the offer is gone.
        XCTAssertEqual(model.folders.first?.rules.first?.enabled, false,
                       "the rule was not switched off")
        XCTAssertTrue(model.unmarkedRules.isEmpty, "the offer outlived the press")
        // The write is `save()`'s detached task, so it lands a turn later.
        for _ in 0..<100 where wire.saved.isEmpty { await Task.yield() }
        let saved = try XCTUnwrap(wire.saved.last, "the change was never written")
        XCTAssertEqual(saved.first?.rules.first?.enabled, false,
                       "the rule was not switched off in the write")
    }

    // MARK: - A single return's report on the row it is about

    /// A file that did not go back is a fact about its row, not only the banner:
    /// the reason is pinned to the record it names.
    func testAReturnPinsAFailuresReasonToItsRow() async throws {
        let a = record("a.pdf")
        let b = record("b.pdf")
        let wire = AutopilotWire(folders: [folder()], history: [a, b])
        let model = model(on: wire)
        await model.load()
        wire.answers(UndoReport(lines: [
            UndoReport.Line(id: a.id, file: "a.pdf",
                            outcome: .restored(to: a.destination, stamped: true)),
            UndoReport.Line(id: b.id, file: "b.pdf", outcome: .refused(.notTheSameFile))
        ]))

        await model.undoRun(try XCTUnwrap(model.runs.first))

        XCTAssertEqual(model.undoNote(for: b),
                       ApStr.notPutBack("b.pdf", ApStr.undoRefusal(.notTheSameFile)))
        XCTAssertNil(model.undoNote(for: a), "a clean return left a note on the row")
    }

    /// A file that came back under another name says so on its own row, so
    /// nobody goes looking for `march.pdf` while it sits there as `march 2.pdf`.
    func testAReturnPinsANewNameToItsRow() async throws {
        let a = record("a.pdf")
        let wire = AutopilotWire(folders: [folder()], history: [a])
        let model = model(on: wire)
        await model.load()
        wire.answers(UndoReport(lines: [UndoReport.Line(id: a.id, file: "a.pdf",
                                        outcome: .restored(to: "/tmp/watched/a 2.pdf",
                                                          stamped: true))]))

        await model.undo(try XCTUnwrap(model.history.first))

        XCTAssertEqual(model.undoNote(for: a), ApStr.landedAs("a.pdf", as: "a 2.pdf"))
    }

    /// The notes go with the banner they came from.
    func testTheRowNotesGoWithTheBanner() async throws {
        let a = record("a.pdf")
        let wire = AutopilotWire(folders: [folder()], history: [a])
        let model = model(on: wire)
        await model.load()
        wire.answers(UndoReport(lines: [UndoReport.Line(id: a.id, file: "a.pdf",
                                        outcome: .refused(.notThere))]))
        await model.undo(try XCTUnwrap(model.history.first))
        XCTAssertNotNil(model.undoNote(for: a), "precondition: the note was made")

        model.dismissBanner()

        XCTAssertNil(model.undoNote(for: a))
    }

    /// The offer goes away with the banner it belongs to.
    func testTheOfferGoesWithTheBanner() async throws {
        let row = record()
        let wire = AutopilotWire(folders: [folder()], history: [row])
        let model = model(on: wire)
        await model.load()
        wire.answers(unstuck(row))
        await model.undo(try XCTUnwrap(model.history.first))
        XCTAssertFalse(model.unmarkedRules.isEmpty, "precondition: the offer was made")

        model.dismissBanner()

        XCTAssertTrue(model.unmarkedRules.isEmpty)
    }
}
