import HelmTestSupport
import XCTest

/// `Scripts/test.sh` promises that a `--filter` alternative it cannot count is
/// named and failed (CLAUDE.md, the first lines of Commands). An alternative
/// that is *empty* is the one that cannot be counted at all: `swift test`
/// reads it as a pattern that matches every test (measured for a trailing `|`
/// only: the whole suite; the rest follow from the regex), so a trailing `|` turns a
/// family run into the whole suite, and the runner's own count never fails a bare one:
/// splitting on `|` drops a trailing empty side and counts a leading or middle one
/// as matching every case. A group's has no empty piece; its unbalanced halves do fail
/// the count, but only after the run is spent.
///
/// **What is run.** The real script, with a stub `swift` first on `PATH` that
/// records its arguments and exits 0, so nothing real is ever started — a
/// failure here is a recorded call, never a suite spent. The test refuses to
/// go on at all unless the shell it spawns resolves `swift` to the stub.
///
/// **What is asserted.** An empty alternative is refused *before* `swift`
/// runs: the stub was never called, the status is 1, the last line on stdout
/// is the runner's `==> FAIL (runner exit=1, swift test exit=not run)` line —
/// the same shape as the newline refusal beside it — and standard error says
/// the `--filter` alternative is empty. A refusal that merely exits is not enough: an
/// empty script would pass it. And the controls: a value with no empty
/// alternative, group included, reaches `swift` with exactly the arguments it
/// was given, so a refusal that refuses everything fails here too.
///
/// **Why a group counts.** `(A|)` has no empty piece when the value is split
/// on `|` — it falls into `(A` and `)` — yet its regular expression has an
/// empty alternative and, by the regex, matches everything, while
/// `Foo(A|B)Tests` has none.
final class AnEmptyFilterAlternativeIsRefusedBeforeSwiftRunsTests: XCTestCase {

    private static let a = "TheMapNamesRealDirectoriesTests"
    private static let b = "AStartedToolCannotKillTheAppTests"

    private struct Outcome {
        let status: Int32
        let stdout: String
        let stderr: String
        /// Every call the stub recorded, each as the arguments it received.
        let calls: [[String]]
    }

    private var stubDirectory: URL!
    private var record: URL!
    private var workDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = scratchDirectory("filter-stub")
        stubDirectory = root.appendingPathComponent("bin")
        workDirectory = root.appendingPathComponent("work")
        record = root.appendingPathComponent("record")
        try FileManager.default.createDirectory(at: stubDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let stub = stubDirectory.appendingPathComponent("swift")
        try """
            #!/bin/bash
            { echo CALL; printf '<%s>\\n' "$@"; } >> "$STUB_RECORD"
            exit 0
            """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
    }

    private var environment: [String: String] {
        [
            "PATH": "\(stubDirectory.path):/usr/bin:/bin",
            "HOME": workDirectory.path,
            "TMPDIR": workDirectory.path + "/",
            "STUB_RECORD": record.path,
            "HELM_TEST_LOG": workDirectory.appendingPathComponent("log").path,
        ]
    }

    private func launch(_ arguments: [String], program: String = "/bin/bash") throws -> (Int32, String, String) {
        let out = workDirectory.appendingPathComponent("stdout")
        let err = workDirectory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        FileManager.default.createFile(atPath: err.path, contents: nil)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: program)
        task.arguments = arguments
        task.environment = environment
        task.currentDirectoryURL = workDirectory
        task.standardInput = FileHandle.nullDevice
        let outHandle = try FileHandle(forWritingTo: out)
        let errHandle = try FileHandle(forWritingTo: err)
        task.standardOutput = outHandle
        task.standardError = errHandle
        try task.run()
        task.waitUntilExit()
        try? outHandle.close()
        try? errHandle.close()
        return (task.terminationStatus,
                (try? String(contentsOf: out, encoding: .utf8)) ?? "",
                (try? String(contentsOf: err, encoding: .utf8)) ?? "")
    }

    /// The runner, run for real with the stub on `PATH`.
    private func runner(_ arguments: [String]) throws -> Outcome {
        try? FileManager.default.removeItem(at: record)
        try? FileManager.default.removeItem(at: workDirectory.appendingPathComponent("log"))
        let script = RepoSource.root.appendingPathComponent("Scripts/test.sh").path
        let (status, stdout, stderr) = try launch([script] + arguments)
        let recorded = (try? String(contentsOf: record, encoding: .utf8)) ?? ""
        var calls: [[String]] = []
        for line in recorded.components(separatedBy: "\n") where !line.isEmpty {
            if line == "CALL" { calls.append([]) }
            else if line.hasPrefix("<"), line.hasSuffix(">"), !calls.isEmpty {
                calls[calls.count - 1].append(String(line.dropFirst().dropLast()))
            }
        }
        return Outcome(status: status, stdout: stdout, stderr: stderr, calls: calls)
    }

    /// Nothing below may run unless a spawned shell finds the stub; the other
    /// answer is the real `swift test` over the whole suite.
    private func requireTheStubToBeWhatRunsAsSwift() throws {
        let (status, stdout, _) = try launch(["-c", "command -v swift"])
        let resolved = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = stubDirectory.appendingPathComponent("swift").path
        guard status == 0,
              URL(fileURLWithPath: resolved).resolvingSymlinksInPath().path
                  == URL(fileURLWithPath: expected).resolvingSymlinksInPath().path else {
            XCTFail("a spawned shell resolves swift to «\(resolved)», not the stub; nothing is run")
            throw XCTSkip("the stub is not first on PATH")
        }
    }

    // MARK: - What is refused

    private static let emptyAlternatives = ["", "\(a)|", "|\(a)", "\(a)||\(b)", "(\(a)|)", "(|\(a))"]

    /// Each value spelled as `--filter X` and as `--filter=X`.
    private static var refusedRows: [[String]] {
        var rows: [[String]] = []
        for value in emptyAlternatives {
            rows.append(["--filter", value])
            rows.append(["--filter=\(value)"])
        }
        rows.append(["--filter"])
        rows.append(["--filter", a, "--filter", ""])
        rows.append(["--filter=\(a)", "--filter="])
        rows.append(["--filter", a, "--filter="])
        rows.append(["--filter=\(a)", "--filter", ""])
        rows.append(["--filter", "", "--filter", a])
        rows.append(["--filter=", "--filter=\(a)"])
        return rows
    }

    func testAnEmptyAlternativeIsRefusedBeforeSwiftRuns() throws {
        try requireTheStubToBeWhatRunsAsSwift()
        XCTAssertGreaterThan(Self.refusedRows.count, 15, "the table of rows has shrunk")

        for row in Self.refusedRows {
            let spelled = row.map { "«\($0)»" }.joined(separator: " ")
            let outcome = try runner(row)
            let lastLine = outcome.stdout.components(separatedBy: "\n").last { !$0.isEmpty } ?? ""

            XCTAssertTrue(outcome.calls.isEmpty, """
                \(spelled): swift was started \(outcome.calls.count) time(s) with \
                \(outcome.calls.first ?? []) — an empty alternative reached the run
                """)
            XCTAssertEqual(outcome.status, 1, "\(spelled): the runner exited \(outcome.status), not 1")
            XCTAssertTrue(lastLine.hasPrefix("==> FAIL (runner exit=1, swift test exit=not run)"), """
                \(spelled): the last line is «\(lastLine)», not the runner's refusal before swift test runs
                """)
            let said = outcome.stderr.lowercased()
            XCTAssertTrue(said.contains("--filter") && said.contains("empty"), """
                \(spelled): standard error does not say the --filter alternative is empty: «\(outcome.stderr)»
                """)
        }
    }

    // MARK: - What still goes through

    private static let reachingRows: [[String]] = [
        ["--filter", a], ["--filter=\(a)"],
        ["--filter", "\(a)|\(b)"], ["--filter=\(a)|\(b)"],
        ["--filter", "Foo(\(a)|\(b))Tests"], ["--filter=Foo(\(a)|\(b))Tests"],
        ["--filter", "Foo(A|B)Tests"], ["--filter=Foo(A|B)Tests"],
    ]

    func testAnAlternativeThatIsNotEmptyStillReachesSwift() throws {
        try requireTheStubToBeWhatRunsAsSwift()

        for row in Self.reachingRows {
            let spelled = row.map { "«\($0)»" }.joined(separator: " ")
            let outcome = try runner(row)
            XCTAssertEqual(outcome.calls.count, 1, """
                \(spelled): swift was started \(outcome.calls.count) time(s); stderr: «\(outcome.stderr)»
                """)
            XCTAssertEqual(outcome.calls.first,
                           ["test", "--explicit-target-dependency-import-check", "error"] + row,
                           "\(spelled): swift did not receive the arguments it was given")
        }
    }
}
