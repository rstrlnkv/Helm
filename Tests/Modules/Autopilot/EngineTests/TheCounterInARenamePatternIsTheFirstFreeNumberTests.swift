import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// M017: `{counter}` was always `001`, because nothing passed a number to
/// `RenamePattern.apply` while the rule editor's hint promised it was replaced.
///
/// Decision (2026-11-11): `{counter}` is the first free number in the folder the
/// file lands in, `001`, and when that name is taken there `002`, `003`... A
/// later sweep over the result must rename nothing: renaming is the one action
/// that is not idempotent, and it runs unattended on a person's files.
///
/// Driven through the real `RuleRunner` on a scratch folder. Every run uses a
/// fresh rule id, so no stamp is consulted: the state of a volume that will not
/// keep the attribute, where the shape of the name is all that stops a rename.
final class TheCounterInARenamePatternIsTheFirstFreeNumberTests: XCTestCase {

    private let added = Date(timeIntervalSince1970: 1_784_116_800)   // 2026-07-15

    private func facts(_ name: String) -> FileFacts {
        FileFacts(name: name, kind: .document, bytes: 4,
                  added: added, modified: added, now: added)
    }

    private func folder() throws -> (home: URL, root: URL) {
        let home = scratchDirectory("home")
        let root = home.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return (home, root)
    }

    private func put(_ names: [String], in root: URL) throws {
        for name in names {
            try Data(repeating: 0x41, count: 4).write(to: root.appendingPathComponent(name))
        }
    }

    private func sweep(_ pattern: String, over names: [String], in root: URL,
                       home: URL) -> [RuleOutcome] {
        let runner = RuleRunner(home: home.path)
        return names.map { name in
            let plan = RulePlan(facts: facts(name),
                                rule: Rule(id: "counter-\(UUID().uuidString)", name: "r",
                                           enabled: true, conditions: [.name(.contains, "")],
                                           action: .rename(pattern: pattern)))
            return runner.run(plan, at: root.appendingPathComponent(name).path,
                              key: TestRuleKey.material)
        }
    }

    private func listing(_ root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    }

    func testTwoFilesRenamedInOneSweepGetOneAndTwo() throws {
        let (home, root) = try folder()
        try put(["a.txt", "b.txt"], in: root)

        _ = sweep("photo-{counter}", over: ["a.txt", "b.txt"], in: root, home: home)

        XCTAssertEqual(try listing(root), ["photo-001.txt", "photo-002.txt"])
    }

    func testTheCounterAlsoWorksBesideADate() throws {
        let (home, root) = try folder()
        try put(["a.txt", "b.txt"], in: root)

        _ = sweep("{date}-{counter}", over: ["a.txt", "b.txt"], in: root, home: home)

        XCTAssertEqual(try listing(root), ["2026-07-15-001.txt", "2026-07-15-002.txt"])
    }

    func testANumberAlreadyTakenInTheFolderIsSkipped() throws {
        let (home, root) = try folder()
        try put(["photo-001.txt", "c.txt"], in: root)

        _ = sweep("photo-{counter}", over: ["c.txt"], in: root, home: home)

        XCTAssertEqual(try listing(root), ["photo-001.txt", "photo-002.txt"])
    }

    func testASecondSweepRenamesNothing() throws {
        let (home, root) = try folder()
        try put(["a.txt", "b.txt"], in: root)
        _ = sweep("photo-{counter}", over: ["a.txt", "b.txt"], in: root, home: home)
        let after = try listing(root)
        XCTAssertEqual(after, ["photo-001.txt", "photo-002.txt"],
                       "precondition: the first sweep numbered")

        _ = sweep("photo-{counter}", over: after, in: root, home: home)

        XCTAssertEqual(try listing(root), ["photo-001.txt", "photo-002.txt"],
                       "the second sweep renamed a file the first had already numbered")
    }

    func testASecondSweepOfANameAndCounterPatternRenamesNothing() throws {
        let (home, root) = try folder()
        try put(["a.txt", "b.txt"], in: root)
        _ = sweep("{name}-{counter}", over: ["a.txt", "b.txt"], in: root, home: home)
        let after = try listing(root)
        XCTAssertEqual(after, ["a-001.txt", "b-002.txt"].sorted(),
                       "precondition: the first sweep numbered")

        _ = sweep("{name}-{counter}", over: after, in: root, home: home)

        XCTAssertEqual(try listing(root), after)
    }

    /// Control: a pattern without the token is what it is today.
    func testAPatternWithoutACounterIsUnchanged() throws {
        let (home, root) = try folder()
        try put(["a.txt"], in: root)

        _ = sweep("{date}-{name}", over: ["a.txt"], in: root, home: home)
        XCTAssertEqual(try listing(root), ["2026-07-15-a.txt"])

        _ = sweep("{date}-{name}", over: ["2026-07-15-a.txt"], in: root, home: home)
        XCTAssertEqual(try listing(root), ["2026-07-15-a.txt"])
    }

    // MARK: - One numbering for the dry run and the sweep

    private func plan(_ pattern: String, _ name: String, in root: URL) -> RulePlan {
        RulePlan(facts: FileFacts(name: name, path: root.appendingPathComponent(name).path,
                                  kind: .document, bytes: 4,
                                  added: added, modified: added, now: added),
                 rule: Rule(id: "counter-\(UUID().uuidString)", name: "r", enabled: true,
                            conditions: [.name(.contains, "")], action: .rename(pattern: pattern)))
    }

    /// The preview numbers the rows the way the run will, through one book in
    /// the same order: not `001` on every row.
    func testThePreviewNumbersTwoFilesTheWayTheRunDoes() throws {
        let (home, root) = try folder()
        try put(["a.txt", "b.txt"], in: root)
        let plans = ["a.txt", "b.txt"].map { plan("{name}-{counter}", $0, in: root) }

        let book = CounterBook()
        let shown = plans.map { PreviewRow($0, counters: book).destination }
        XCTAssertEqual(shown, ["a-001.txt", "b-002.txt"])

        let runner = RuleRunner(home: home.path)
        let sweepBook = CounterBook()
        for p in plans {
            _ = runner.run(p, at: p.facts.path, key: TestRuleKey.material, counters: sweepBook)
        }
        XCTAssertEqual(try listing(root), ["a-001.txt", "b-002.txt"])
    }

    /// The folder is listed once for the pass, not once per file.
    func testTheFolderIsListedOncePerPass() throws {
        let (home, root) = try folder()
        try put(["a.txt", "b.txt", "c.txt"], in: root)
        nonisolated(unsafe) var listings = 0
        let book = CounterBook(list: {
            listings += 1
            return try FileManager.default.contentsOfDirectory(atPath: $0)
        })
        let runner = RuleRunner(home: home.path)
        for name in ["a.txt", "b.txt", "c.txt"] {
            let p = plan("n-{counter}", name, in: root)
            _ = runner.run(p, at: p.facts.path, key: TestRuleKey.material, counters: book)
        }
        XCTAssertEqual(listings, 1)
        XCTAssertEqual(try listing(root), ["n-001.txt", "n-002.txt", "n-003.txt"])
    }

    /// A folder that cannot be listed is not an empty one: the rename is
    /// refused, and the preview says so instead of showing a number.
    func testAFolderThatCannotBeListedRefusesTheRename() throws {
        let (home, root) = try folder()
        try put(["a.txt"], in: root)
        struct Unreadable: Error {}
        let p = plan("photo-{counter}", "a.txt", in: root)

        let outcome = RuleRunner(home: home.path).run(
            p, at: p.facts.path, key: TestRuleKey.material,
            counters: CounterBook(list: { _ in throw Unreadable() }))
        XCTAssertEqual(outcome, .refused(.folderUnreadable))
        XCTAssertEqual(try listing(root), ["a.txt"])

        let row = PreviewRow(p, counters: CounterBook(list: { _ in throw Unreadable() }))
        XCTAssertEqual(row.refusal, .folderUnreadable)
        XCTAssertNil(row.destination)
    }

    /// APFS holds `Invoice-001.pdf` and `invoice-001.pdf` to be one name.
    func testANumberWornInAnotherCaseIsTaken() throws {
        let (home, root) = try folder()
        try put(["Invoice-001.pdf", "x.pdf"], in: root)

        _ = sweep("invoice-{counter}", over: ["x.pdf"], in: root, home: home)

        XCTAssertEqual(try listing(root), ["Invoice-001.pdf", "invoice-002.pdf"])
    }

    /// Every number to 999 worn: refused for its own reason, nothing renamed.
    func testAFolderWithEveryNumberUsedRefusesForItsOwnReason() throws {
        let (home, root) = try folder()
        try put(["x.txt"], in: root)
        let worn = (1...999).map { String(format: "photo-%03d.txt", $0) }
        let p = plan("photo-{counter}", "x.txt", in: root)

        let outcome = RuleRunner(home: home.path).run(
            p, at: p.facts.path, key: TestRuleKey.material,
            counters: CounterBook(list: { _ in worn + ["x.txt"] }))

        XCTAssertEqual(outcome, .refused(.counterNumbersUsedUp))
        XCTAssertEqual(try listing(root), ["x.txt"])
        XCTAssertEqual(PreviewRow(p, counters: CounterBook(list: { _ in worn })).refusal,
                       .counterNumbersUsedUp)
    }

    // MARK: - Edges of the search

    /// 998 worn: the last number, 999, is still free and is handed out; the
    /// ceiling is inclusive.
    func testTheLastNumberBeforeTheCeilingIsStillFree() throws {
        let (home, root) = try folder()
        try put(["x.txt"], in: root)
        let worn = (1...998).map { String(format: "photo-%03d.txt", $0) }
        let p = plan("photo-{counter}", "x.txt", in: root)

        let outcome = RuleRunner(home: home.path).run(
            p, at: p.facts.path, key: TestRuleKey.material,
            counters: CounterBook(list: { _ in worn + ["x.txt"] }))

        XCTAssertEqual(outcome, .renamed(to: "photo-999.txt"))
    }

    /// `.PDF` and `.pdf` are one extension to the filesystem, so `photo-001.PDF`
    /// wears `001` for a `.pdf` file.
    func testANumberWornWithAnotherCaseOfTheExtensionIsTaken() throws {
        let (home, root) = try folder()
        try put(["photo-001.PDF", "x.pdf"], in: root)

        let outcome = sweep("photo-{counter}", over: ["x.pdf"], in: root, home: home)

        XCTAssertEqual(outcome, [.renamed(to: "photo-002.pdf")])
    }

    /// Two folders in one pass are numbered apart: the second folder's first
    /// file is `001`, not the next number of the first folder.
    func testTwoFoldersOfOnePassAreNumberedApart() throws {
        let (home, root) = try folder()
        let other = root.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try put(["a.txt"], in: root)
        try put(["b.txt"], in: other)
        let runner = RuleRunner(home: home.path)
        let book = CounterBook()
        for (name, dir) in [("a.txt", root), ("b.txt", other)] {
            let p = plan("n-{counter}", name, in: dir)
            _ = runner.run(p, at: p.facts.path, key: TestRuleKey.material, counters: book)
        }
        XCTAssertEqual(try listing(root), ["Other", "n-001.txt"])
        XCTAssertEqual(try listing(other), ["n-001.txt"])
    }

    /// A pattern the filesystem should not take is refused as a bad pattern
    /// before the folder is asked about: an unreadable folder does not rename
    /// that into a different refusal.
    func testAnUnusablePatternIsRefusedAsOneWithoutReadingTheFolder() throws {
        let (home, root) = try folder()
        try put(["a.txt"], in: root)
        struct Unreadable: Error {}
        let p = plan("sub/{name}-{counter}", "a.txt", in: root)

        let outcome = RuleRunner(home: home.path).run(
            p, at: p.facts.path, key: TestRuleKey.material,
            counters: CounterBook(list: { _ in throw Unreadable() }))

        XCTAssertEqual(outcome, .refused(.badPattern))
        XCTAssertEqual(try listing(root), ["a.txt"])
    }

    // MARK: - The shape walk is bounded

    /// Four free-length holes against a 250-character stem: unmemoised, this
    /// is minutes of backtracking. The walk answers once per (position, part),
    /// so it finishes; asserted by its answer only, no timing and no test hook.
    func testManyNameHolesOnALongStemAreAnsweredAndNumbered() {
        let shape = RenameShape(resolved: "{name}-{name}-{name}-{name}-{counter}")
        let stem = String(repeating: "ab-", count: 83) + "007"

        XCTAssertTrue(shape.matches(stem))
        XCTAssertEqual(shape.numbers(in: stem), [7])
        XCTAssertFalse(shape.matches(String(repeating: "ab-", count: 83) + "x7"))
        XCTAssertEqual(shape.numbers(in: "a-b-c-d-001-"), [])
    }

    func testANumberIsWornOnlyWhereTheShapeCanPutIt() {
        XCTAssertEqual(RenameShape(resolved: "{counter}-{counter}").numbers(in: "001-002"), [1, 2])
        XCTAssertEqual(RenameShape(resolved: "{name}-{counter}-x").numbers(in: "a-001-002-x"), [2])
    }
}
