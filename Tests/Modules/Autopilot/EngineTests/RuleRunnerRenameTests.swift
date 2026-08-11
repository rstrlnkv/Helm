import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// Renaming, where the name the runner *reports* and the name it *produced* can
/// come apart.
///
/// `free(_:)` decides the name that actually gets used — `b.pdf` becomes
/// `b 2.pdf` when `b.pdf` is taken — but `run` reports, and stamps, the name the
/// pattern produced. Nothing else in the module notices, because the collision
/// case is the only one where the two differ. Every test here is that pair
/// agreeing, and the two failures a disagreement causes: a mark on a file
/// nobody touched, and no mark on the file that moved.
final class RuleRunnerRenameTests: XCTestCase {

    private var root: URL!
    private var home: URL!
    private var runner: RuleRunner!

    override func setUpWithError() throws {
        // Inside a temporary directory the runner is told to treat as home:
        // `WatchScope` refuses anything outside one, and a test that wanted an
        // exemption from that gate would be testing a different program.
        home = scratchDirectory("home")
        root = home
            .appendingPathComponent("helm-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        runner = RuleRunner(home: home.path)
    }

    private func rename(_ url: URL, pattern: String, id: String = "r") -> RuleOutcome {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        let facts = FileFacts(name: url.lastPathComponent, kind: .document, bytes: 4,
                              added: now, modified: now, now: now)
        let rule = Rule(id: id, name: id, enabled: true,
                        conditions: [.fileExtension(["pdf"])], action: .rename(pattern: pattern))
        return runner.run(RulePlan(facts: facts, rule: rule), at: url.path)
    }

    private func listing() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    }

    // MARK: - The name reported and the name on disk

    /// The root of the other two. `.renamed(to:)` is the only thing the sweep,
    /// the log and the stamp are told about a rename, so a name that is not on
    /// disk is a lie every one of them then acts on.
    func testTheNameAReportedRenameGivesIsTheNameOnDisk() throws {
        try write("b.pdf", in: root, bytes: 99)
        let file = try write("a.pdf", in: root)

        guard case let .renamed(to: reported) = rename(file, pattern: "b") else {
            return XCTFail("expected a rename")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(reported).path),
                      "the runner reported \(reported), which is not what it produced")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(reported)).count, 4,
                       "the reported name points at the file that was already there, not the one that moved")
    }

    /// The collateral damage. The stamp lands on `b.pdf` — a file this rule
    /// never acted on and, because it now carries the mark, never will.
    /// Switching a rule off and on again does not clear it; it is an xattr on
    /// somebody's file.
    func testACollidingRenameDoesNotStampTheFileItCollidedWith() throws {
        let bystander = try write("b.pdf", in: root, bytes: 99)
        let file = try write("a.pdf", in: root)

        _ = rename(file, pattern: "b")

        XCTAssertFalse(RuleStamp.isStamped(bystander.path, by: "r"),
                       "a file the rule never acted on was marked as done")
        XCTAssertTrue(RuleStamp.isStamped(root.appendingPathComponent("b 2.pdf").path, by: "r"),
                      "the file that was actually renamed carries no mark, so the rule will rename it again")
    }

    /// A pattern that resolves to the name the file already has.
    ///
    /// `{name}` is a legitimate thing to write — `{name} {date}` minus the date,
    /// or a pattern being edited. `free(_:)` sees the target is taken without
    /// noticing that the file taking it *is the file being renamed*, so `a.pdf`
    /// becomes `a 2.pdf`, and nothing is stamped because the path the stamp goes
    /// to no longer exists. Next hour: `a 2 2.pdf`.
    func testRenamingAFileToTheNameItAlreadyHasChangesNothing() throws {
        let file = try write("a.pdf", in: root)

        _ = rename(file, pattern: "{name}")
        XCTAssertEqual(try listing(), ["a.pdf"],
                       "a rename to the file's own name produced a numbered copy of the name")

        // Whatever shape the fix takes — a no-op, or a refusal — running again
        // must not add a file either. That is the part a sweep every hour turns
        // into a folder nobody can use.
        let remaining = try XCTUnwrap(listing().first)
        _ = rename(root.appendingPathComponent(remaining), pattern: "{name}", id: "r2")
        XCTAssertEqual(try listing(), ["a.pdf"])
    }

    // MARK: - Names the filesystem will not take

    /// 300 characters is past the 255-byte limit on a path component, so the
    /// move throws. What matters is that the file is where it was and is
    /// reported, rather than half-renamed or quietly counted as done.
    func testANameTooLongForTheFilesystemLeavesTheFileIntact() throws {
        let file = try write("a.pdf", in: root, bytes: 7)

        let outcome = rename(file, pattern: String(repeating: "x", count: 300))

        XCTAssertEqual(try listing(), ["a.pdf"])
        XCTAssertEqual(try Data(contentsOf: file).count, 7)
        if case .renamed = outcome { XCTFail("reported a rename that did not happen") }
        XCTAssertFalse(RuleStamp.isStamped(file.path, by: "r"),
                       "a rename that failed must not be recorded as having happened")
    }

    /// Guarantee 5 as a property rather than as a handful of examples: whatever
    /// a pattern is, the answer is either nothing at all or one path component
    /// that keeps the file's own extension. The corpus is the awkward input
    /// list — empty, whitespace, separators, a leading dot, a tab, a newline,
    /// Cyrillic, an emoji, and something far too long.
    ///
    /// Note what this does *not* claim: a tab and a newline survive, because
    /// `RenamePattern` only refuses `/`, `:` and a leading dot. Both are legal
    /// on APFS. They are here so that a future filter is a deliberate change to
    /// this list rather than a surprise.
    func testWhateverAPatternProducesIsOneComponentWithTheFilesOwnExtension() {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        let facts = FileFacts(name: "a.pdf", kind: .document, bytes: 1,
                              added: now, modified: now, now: now)
        let corpus = ["", "   ", "\n\t ", ".", "..", "./x", "sub/{name}", "{name}/{date}",
                      "a:b", ".{name}", "{name}", "{name}{date}{counter}", "{unknown}",
                      "отчёт", "🙂", "a\tb", "a\nb", "  {name}  ", "{name}.txt",
                      String(repeating: "x", count: 300)]

        for pattern in corpus {
            guard let produced = RenamePattern.apply(pattern, to: facts) else { continue }
            XCTAssertFalse(produced.isEmpty, "\(pattern.debugDescription) produced an empty name")
            XCTAssertFalse(produced.contains("/"),
                           "\(pattern.debugDescription) produced a path, not a name")
            XCTAssertFalse(produced.contains(":"),
                           "\(pattern.debugDescription) produced a name the Finder reads as a path")
            XCTAssertFalse(produced.hasPrefix("."),
                           "\(pattern.debugDescription) produced a hidden file")
            XCTAssertEqual((produced as NSString).pathExtension, "pdf",
                           "\(pattern.debugDescription) changed what kind of file this is")
        }
    }
}
