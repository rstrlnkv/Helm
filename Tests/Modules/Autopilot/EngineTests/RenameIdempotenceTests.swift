import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// The third action, on the volume where the stamp does not stick.
///
/// `RuleRunnerIdempotenceTests` covers `move` and `sortIntoSubfolder` under
/// exactly these conditions and says why they matter: `RuleRunner.note`
/// tolerates a stamp that will not stick, and the sentence it leans on is that
/// the action "re-runs an idempotent action on an unchanged file". The
/// tolerated case is any volume that will not keep the attribute, or a file
/// whose AppleDouble `._name` sidecar something dropped, with a sweep every
/// hour — `WatchScope` deliberately admits `/Volumes`.
///
/// `rename` is the third action and it is the one that is not idempotent.
/// `RuleRunner` guards a single shape of it — `guard target.path != url.path`,
/// which catches a pattern that resolves to the name the file already has —
/// and `RuleRunnerRenameTests` pins that for the bare `{name}` pattern. Any
/// pattern that puts `{name}` *next to* something else walks straight past the
/// guard, because the second sweep substitutes the first sweep's output into
/// `{name}` and the result differs from the input again.
///
/// The tests below are about `RenamePattern.apply` alone: no filesystem, no
/// stamp, no clock. Given the facts of the file the previous run produced, the
/// name it produces this run must be the same name — that is what "idempotent"
/// has to mean for a rule that is allowed to run unstamped, and it is the
/// property the runner's own guard is a partial implementation of.
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

    /// The pattern the rule editor's own examples lead somebody to write, and
    /// the one a Downloads folder wants: stamp the date on the front and keep
    /// the name. Stamped, this runs once. Unstamped it runs every sweep, and
    /// each one prepends another date.
    ///
    /// Asserted as a fixed point rather than as a count of files: after the
    /// first rename the file is where the rule wants it, so every later sweep
    /// must produce the name it already has.
    func testADatePrefixIsNotAddedTwice() {
        let names = sweeps("{date}-{name}", from: "report.pdf", times: 3)

        XCTAssertEqual(names.first, "2026-07-15-report.pdf", "precondition: the first run renames")
        XCTAssertEqual(names[1], names[0],
                       "the second sweep renamed the file the first sweep had already named: "
                       + names.joined(separator: " → "))
    }

    /// The same shape with the token at the other end, because a fix that
    /// special-cases a prefix is not a fix.
    func testASuffixIsNotAddedTwice() {
        let names = sweeps("{name} {date}", from: "report.pdf", times: 3)

        XCTAssertEqual(names.first, "report 2026-07-15.pdf")
        XCTAssertEqual(names[1], names[0], names.joined(separator: " → "))
    }

    /// What it costs if nobody stops it. A path component is limited to 255
    /// bytes; each sweep of `{date}-{name}` adds eleven, and an hourly sweep
    /// therefore reaches the limit inside a day — after which `moveItem` throws
    /// and the rule reports `.failed` on that file forever.
    ///
    /// The assertion is on the shape of the growth, not on a byte count: the
    /// name must stop growing, whatever the limit is.
    func testTheNameStopsGrowing() {
        let names = sweeps("{date}-{name}", from: "report.pdf", times: 24)

        XCTAssertEqual(Set(names).count, 1,
                       "an hourly sweep produced \(Set(names).count) different names in a day; "
                       + "the last was \(names.last?.count ?? 0) characters")
    }

    // MARK: - The patterns that already hold

    /// The bare token, which `RuleRunner` already guards and which is the
    /// control for everything above: a fix must not be "refuse every rename".
    func testTheBareNameTokenIsAlreadyAFixedPoint() {
        XCTAssertEqual(sweeps("{name}", from: "report.pdf", times: 3),
                       ["report.pdf", "report.pdf", "report.pdf"])
    }

    /// A pattern that names nothing about the file is a fixed point by
    /// construction — it produces the same name whatever it is given.
    func testAPatternWithoutTheNameTokenIsAFixedPoint() {
        let names = sweeps("{date}", from: "report.pdf", times: 3)
        XCTAssertEqual(names, ["2026-07-15.pdf", "2026-07-15.pdf", "2026-07-15.pdf"])
    }

    // MARK: - The same thing, through the runner, on disk

    /// The pure property above, reached the way a sweep reaches it: two runs of
    /// a rule whose stamp never stuck, against a real file in a real folder.
    ///
    /// The rule id differs between the runs for the same reason
    /// `RuleRunnerIdempotenceTests` uses a fresh one — the stamp is not
    /// disabled, it is simply not consulted, which is the state an unstampable
    /// volume is in on every sweep. The facts for the second run are read off
    /// the name the first run produced, because that is what `FolderReader`
    /// hands the matcher an hour later.
    ///
    /// The folder is described by a listing rather than a count: the harm is a
    /// file existing under a name nobody chose.
    func testTwoSweepsOfAnUnstampedRenameLeaveOneFileUnderOneName() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-home-\(UUID().uuidString)")
        let root = home.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = RuleRunner(home: home.path)

        func sweep(_ name: String) -> RuleOutcome {
            let url = root.appendingPathComponent(name)
            let plan = RulePlan(facts: facts(name),
                                rule: Rule(id: "unstamped-\(UUID().uuidString)", name: "r",
                                           enabled: true, conditions: [.name(.contains, "")],
                                           action: .rename(pattern: "{date}-{name}")))
            return runner.run(plan, at: url.path)
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

    /// The property behind all of the above, over the awkward-input list this
    /// suite family uses elsewhere: whatever a pattern produces, feeding it back
    /// in must produce the same thing. A pattern that refuses (nil) is a fixed
    /// point too — nothing happens, twice.
    func testEveryPatternThatRenamesOnceRenamesOnlyOnce() {
        let patterns = ["{name}", "{date}", "{counter}", "{date}-{name}", "{name} {date}",
                        "{name}{counter}", "scan-{name}", "{name}-copy", "{name}{name}",
                        "отчёт-{name}", "🙂 {name}", "{name}\t{date}", "  {name}  "]
        for pattern in patterns {
            guard let once = RenamePattern.apply(pattern, to: facts("report.pdf")) else { continue }
            let twice = RenamePattern.apply(pattern, to: facts(once))
            XCTAssertEqual(twice, once,
                           "pattern \(pattern.debugDescription): report.pdf → \(once) → "
                           + "\(twice ?? "nil")")
        }
    }
}
