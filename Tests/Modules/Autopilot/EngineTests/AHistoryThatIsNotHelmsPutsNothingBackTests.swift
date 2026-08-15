import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The history is sealed for the same reason the rules are, and the reason is
/// stronger here: a rule has to be matched against a file before it does
/// anything, and a history record **is** the instruction. Every field a return
/// acts on — where the file is, where it goes, who it is — comes out of a plist
/// any process running as this user can write.
///
/// So a history that does not verify is shown and never acted on, and the one
/// way forward is to throw it away, exactly as it is for a refused rule set.
final class AHistoryThatIsNotHelmsPutsNothingBackTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var store: NamespacedStore!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NamespacedStore(namespace: "rules.test.\(UUID().uuidString)",
                                backing: InMemoryKeyValueStore())
        engine = AutopilotEngine(store: store, home: home.path,
                                 keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func folder(_ action: RuleAction) -> WatchedFolder {
        WatchedFolder(id: "f", path: root.path, enabled: true,
                      // Every PDF: `contains ""` is false in Swift, which is a
                      // trap a matcher test would have caught and a runner test
                      // never can — the runner is handed its plan.
                      rules: [Rule(id: "r", name: "Sort", enabled: true,
                                   conditions: [.fileExtension(["pdf"])], action: action)],
                      depth: 1)
    }

    /// A sweep that really moved something, so everything below is about a
    /// history with something in it.
    @discardableResult
    private func aSweptFile(_ name: String = "a.pdf") throws -> URL {
        let file = try write(name, in: root)
        engine.sweep(folder(.move(to: root.appendingPathComponent("Sorted").path)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "nothing was moved, so this proves nothing")
        return file
    }

    // MARK: - The pass

    /// One value for a whole sweep, so the page can offer "put back the twelve
    /// files that arrived at 14:22" instead of five hundred separate rows.
    func testEveryRecordOfOneSweepCarriesOneRunAndTwoSweepsAreTwo() throws {
        try aSweptFile("a.pdf")
        try aSweptFile("b.pdf")

        let runs = engine.history.compactMap(\.run)
        XCTAssertEqual(runs.count, 2, "a record came out of a sweep with no pass to belong to")
        XCTAssertEqual(Set(runs).count, 2, "two sweeps were recorded as one pass")
    }

    func testTheRecordsOfOneSweepShareItsRun() throws {
        try write("a.pdf", in: root)
        try write("b.pdf", in: root)
        engine.sweep(folder(.move(to: root.appendingPathComponent("Sorted").path)))

        let runs = Set(engine.history.compactMap(\.run))
        XCTAssertEqual(engine.history.count, 2)
        XCTAssertEqual(runs.count, 1, "one sweep was recorded as \(runs.count) passes")
    }

    // MARK: - Putting one back

    func testAnActionGoesBackAndTheRowSaysSo() throws {
        let file = try aSweptFile()
        let record = try XCTUnwrap(engine.history.first)

        let report = engine.undo(record.id)

        XCTAssertEqual(report.restored.count, 1)
        XCTAssertEqual(report.notPutBack, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNotNil(engine.history.first?.undoneAt,
                        "the row does not say it was put back, so a second press moves a "
                        + "file nobody asked about")
    }

    /// The row stays. A history that deleted what it had undone would be a
    /// history that hides an action Autopilot took.
    func testAReturnedRowIsMarkedRatherThanRemoved() throws {
        try aSweptFile()
        let record = try XCTUnwrap(engine.history.first)
        _ = engine.undo(record.id)
        XCTAssertEqual(engine.history.count, 1)
        XCTAssertEqual(engine.history.first?.id, record.id)
    }

    func testAPassGoesBackAsAWhole() throws {
        try write("a.pdf", in: root)
        try write("b.pdf", in: root)
        engine.sweep(folder(.move(to: root.appendingPathComponent("Sorted").path)))
        let run = try XCTUnwrap(engine.history.first?.run)

        let report = engine.undoRun(run)

        XCTAssertEqual(report.restored.count, 2)
        XCTAssertEqual(Set(engine.history.map { $0.undoneAt != nil }), [true])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.pdf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("b.pdf").path))
    }

    /// **A pass is not atomic and the report must not pretend it is.** One file
    /// taken out of the bucket by hand between the sweep and the press is one
    /// line that refuses, beside the ones that worked — and the counts are read
    /// off the lines, so a report cannot say three when two of them failed.
    func testAPassThatOnlyHalfGoesBackSaysWhichHalf() throws {
        try write("a.pdf", in: root)
        try write("b.pdf", in: root)
        let sorted = root.appendingPathComponent("Sorted")
        engine.sweep(folder(.move(to: sorted.path)))
        let run = try XCTUnwrap(engine.history.first?.run)
        // Somebody moved one of them out of the bucket themselves.
        try FileManager.default.removeItem(at: sorted.appendingPathComponent("a.pdf"))

        let report = engine.undoRun(run)

        XCTAssertEqual(report.restored.count, 1)
        XCTAssertEqual(report.notPutBack.map(\.file), ["a.pdf"])
        XCTAssertEqual(report.notPutBack.map(\.outcome), [.refused(.notThere)])
        XCTAssertEqual(engine.history.filter { $0.undoneAt != nil }.count, 1,
                       "a row that did not go back was marked as though it had")
    }

    // MARK: - The seal

    func testTheHistoryIsSealedAsItIsWritten() throws {
        try aSweptFile()
        XCTAssertFalse(store.string(RuleSeal.historyKey, default: "").isEmpty,
                       "the history was written with no seal over it")
    }

    /// The forged record, arriving the way it actually would: written straight
    /// into the plist. It is shown — the page's job is to say what happened —
    /// and nothing in it is acted on.
    func testAHistorySomethingElseWroteIsShownAndNeverActedOn() throws {
        let file = try aSweptFile()
        let real = try XCTUnwrap(engine.history.first)
        store.set(ActionHistory.encode([real]), for: "history")
        store.set("00", for: RuleSeal.historyKey)

        XCTAssertEqual(engine.history.count, 1, "the page went blank instead of saying why")
        XCTAssertTrue(engine.historyRefused)

        let report = engine.undo(real.id)

        XCTAssertEqual(report.notPutBack.map(\.outcome), [.refused(.historyRefused)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "a record something else wrote moved a file")
    }

    /// And the whole-pass gesture goes through the same door.
    func testAPassOutOfAHistorySomethingElseWroteIsRefused() throws {
        try aSweptFile()
        let real = try XCTUnwrap(engine.history.first)
        store.set("00", for: RuleSeal.historyKey)

        let report = engine.undoRun(try XCTUnwrap(real.run))

        XCTAssertEqual(report.notPutBack.map(\.outcome), [.refused(.historyRefused)])
    }

    /// **Nothing is folded into a history that does not verify.** Appending to
    /// it and re-sealing would hand a forged record Helm's own signature — the
    /// laundering the seal exists to prevent — and deleting it would take the
    /// warning away before anybody saw it. So it is frozen, and the way out is
    /// the one the page offers.
    func testASweepDoesNotResealAHistoryItCannotVerify() throws {
        try aSweptFile("a.pdf")
        let planted = try XCTUnwrap(engine.history.first)
        store.set("00", for: RuleSeal.historyKey)

        try write("b.pdf", in: root)
        engine.sweep(folder(.move(to: root.appendingPathComponent("Sorted").path)))

        XCTAssertEqual(engine.history.map(\.id), [planted.id],
                       "the new record was folded into a history that is not Helm's")
        XCTAssertTrue(engine.historyRefused, "the forged history was re-sealed under Helm's key")
    }

    /// The way out, by the same shape as `discardRefusedRules`: throw it away,
    /// and the section works again.
    func testClearingTheHistoryIsTheWayOut() throws {
        try aSweptFile("a.pdf")
        store.set("00", for: RuleSeal.historyKey)
        XCTAssertTrue(engine.historyRefused)

        engine.clearHistory()

        XCTAssertFalse(engine.historyRefused)
        XCTAssertEqual(engine.history, [])
        try aSweptFile("b.pdf")
        XCTAssertEqual(engine.history.count, 1, "the section never records again")
    }
}
