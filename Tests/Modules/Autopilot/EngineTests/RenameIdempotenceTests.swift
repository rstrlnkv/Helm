import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// `rename` on a volume where the stamp does not stick, as `RuleRunnerTests`
/// covers `move` and `sortIntoSubfolder`. It is the one action that is not
/// idempotent by nature: a pattern that puts `{name}` *next to* something else
/// takes the last sweep's output into `{name}` and differs from its input
/// again, past `RuleRunner`'s guard for a name that resolves to itself.
///
/// Most tests here are `RenamePattern.apply` alone, with no filesystem, stamp
/// or clock: given the facts of the file the previous run produced, the name
/// this run produces must be the same name.
final class RenameIdempotenceTests: XCTestCase {

    private let added = Date(timeIntervalSince1970: 1_784_116_800)   // 2026-07-15

    private func facts(_ name: String) -> FileFacts {
        FileFacts(name: name, kind: .document, bytes: 4,
                  added: added, modified: added, now: added)
    }

    /// Applies a pattern the way an unstamped sweep does: the name that came
    /// out of the last run is the name that goes into this one.
    private func sweeps(_ pattern: String, from name: String, times: Int) -> [String] {
        var current = name
        var out: [String] = []
        for _ in 0..<times {
            guard let next = RenamePattern.apply(pattern, to: facts(current)) else { break }
            out.append(next)
            current = next
        }
        return out
    }

    // MARK: - A pattern that keeps the name and adds to it

    /// The name stops growing. A path component holds 255 bytes and each sweep
    /// of `{date}-{name}` would add eleven, so an hourly sweep would reach the
    /// limit inside a day and the rule would report `.failed` on that file for
    /// good. The assertion is on the growth, not on a byte count.
    func testTheNameStopsGrowing() {
        let names = sweeps("{date}-{name}", from: "report.pdf", times: 24)

        XCTAssertEqual(Set(names).count, 1,
                       "an hourly sweep produced \(Set(names).count) different names in a day; "
                       + "the last was \(names.last?.count ?? 0) characters")
    }

    // MARK: - The same thing, through the runner, on disk

    /// The property above through the runner, on disk: two runs of a rule whose
    /// stamp never stuck, against a real file. A fresh rule id each run leaves
    /// the stamp unconsulted, as on an unstampable volume; the second run's facts
    /// are the name the first produced, as `FolderReader` hands it an hour later.
    /// A listing, not a count: the harm is a file under a name nobody chose.
    func testTwoSweepsOfAnUnstampedRenameLeaveOneFileUnderOneName() throws {
        let home = scratchDirectory("home")
        let root = home.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runner = RuleRunner(home: home.path)

        func sweep(_ name: String) -> RuleOutcome {
            let url = root.appendingPathComponent(name)
            let plan = RulePlan(facts: facts(name),
                                rule: Rule(id: "unstamped-\(UUID().uuidString)", name: "r",
                                           enabled: true, conditions: [.name(.contains, "")],
                                           action: .rename(pattern: "{date}-{name}")))
            return runner.run(plan, at: url.path, key: TestRuleKey.material)
        }

        try Data(repeating: 0x41, count: 4).write(to: root.appendingPathComponent("report.pdf"))

        guard case let .renamed(first) = sweep("report.pdf") else {
            return XCTFail("precondition: the first sweep renames the file")
        }
        XCTAssertEqual(first, "2026-07-15-report.pdf")

        _ = sweep(first)

        let listing = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        XCTAssertEqual(listing, ["2026-07-15-report.pdf"],
                       "the second sweep renamed a file the first sweep had already named")
    }

    /// Over the awkward-input list: whatever a pattern produces, feeding it back
    /// in produces the same thing. A pattern that refuses (nil) is a fixed point
    /// too — nothing happens, twice.
    ///
    /// The rows with an expected first output, and what each is for:
    /// - `{date}-{name}`, the pattern the rule editor's own examples lead somebody
    ///   to write.
    /// - `{name} {date}`, the token at the other end, so a guard that
    ///   special-cases a prefix fails.
    /// - `{name}`, the control: the loop's `continue` on nil would let "refuse
    ///   every rename" pass, so a listed row must produce its output.
    /// - `{date}`, which names nothing about the file and is a fixed point by
    ///   construction.
    func testEveryPatternThatRenamesOnceRenamesOnlyOnce() {
        let expectedFirst = ["{date}-{name}": "2026-07-15-report.pdf",
                             "{name} {date}": "report 2026-07-15.pdf",
                             "{name}": "report.pdf", "{date}": "2026-07-15.pdf"]
        let patterns = ["{name}", "{date}", "{counter}", "{date}-{name}", "{name} {date}",
                        "{name}{counter}", "scan-{name}", "{name}-copy", "{name}{name}",
                        "отчёт-{name}", "🙂 {name}", "{name}\t{date}", "  {name}  "]
        for pattern in patterns {
            let first = RenamePattern.apply(pattern, to: facts("report.pdf"))
            if let expected = expectedFirst[pattern] {
                XCTAssertEqual(first, expected, "pattern \(pattern.debugDescription): the first output")
            }
            guard let once = first else { continue }
            let twice = RenamePattern.apply(pattern, to: facts(once))
            XCTAssertEqual(twice, once,
                           "pattern \(pattern.debugDescription): report.pdf → \(once) → "
                           + "\(twice ?? "nil")")
        }
    }
}
