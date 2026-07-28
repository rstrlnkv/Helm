import Foundation
import XCTest
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The sibling of `testRenamingAFileToTheNameItAlreadyHasChangesNothing`.
///
/// That case is guarded by `target.path != url.path` — a string comparison. A
/// Mac's own volume is case-insensitive: `report.pdf` and `REPORT.pdf` are two
/// spellings the filesystem treats as one name, and the string comparison
/// cannot see it. So a rule that only changes capitalisation walks past the
/// guard, `free(_:)` then finds the "collision" (which is the file itself), and
/// numbers it.
///
/// Normalising names is one of the two or three things anybody writes a rename
/// rule for.
final class RuleRunnerCaseRenameTests: XCTestCase {

    private var root: URL!
    private var home: URL!
    private var runner: RuleRunner!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-home-\(UUID().uuidString)")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        runner = RuleRunner(home: home.path)

        // The defect only exists where the volume folds case, which is the
        // default on a Mac. On a case-sensitive volume the two names are two
        // files and the numbering would be correct.
        let probe = root.appendingPathComponent("case-probe")
        try Data("x".utf8).write(to: probe)
        let folded = FileManager.default
            .fileExists(atPath: root.appendingPathComponent("CASE-PROBE").path)
        try FileManager.default.removeItem(at: probe)
        try XCTSkipUnless(folded, "case-sensitive volume: these two names are two files")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func rename(_ url: URL, pattern: String) -> RuleOutcome {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        let facts = FileFacts(name: url.lastPathComponent, path: url.path, kind: .document,
                              bytes: 4, added: now, modified: now, now: now)
        let rule = Rule(id: "r", name: "Tidy names", enabled: true,
                        conditions: [.fileExtension(["pdf"])],
                        action: .rename(pattern: pattern))
        return runner.run(RulePlan(facts: facts, rule: rule), at: url.path)
    }

    private func listing() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    }

    func testRenamingAFileToADifferentSpellingOfItsOwnNameDoesNotNumberIt() throws {
        let file = root.appendingPathComponent("report.pdf")
        try Data(repeating: 0x41, count: 4).write(to: file)

        let outcome = rename(file, pattern: "REPORT")

        let onDisk = try listing()
        XCTAssertEqual(onDisk, ["REPORT.pdf"],
                       "the rule asked for REPORT.pdf; \(onDisk) is what it got")
        XCTAssertEqual(outcome, .renamed(to: "REPORT.pdf"))
    }
}
