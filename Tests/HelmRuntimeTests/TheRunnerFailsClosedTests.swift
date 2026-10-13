import Foundation
import HelmTestSupport
import XCTest

/// `Scripts/test.sh` run for real, as a child, over logs `swift test` never
/// wrote.
///
/// **Why this is a test.** The runner's only wire to its reader is its last
/// line and its exit status, and every family run in this repository is read
/// through them. A runner that prints `PASS` over a run that asserted nothing
/// — every selected case skipped, no case started at all, a family that was
/// only ever found inside another family's name — is a green nobody can see
/// through, and nothing ran the runner itself to find out.
///
/// **How.** Each case starts the tree's own script with a `swift` that is a
/// stub: it records the arguments it was started with, prints a canned log and
/// exits with a canned status. The logs are spelled here, in the lines `swift
/// test` writes, so a row says in one place what the runner was shown and what
/// it must answer.
///
/// **The stub is the only `swift` the child can reach.** `/usr/bin/swift`
/// exists on every Mac, so a `PATH` that kept `/usr/bin` behind the stub would
/// turn a stub that failed to appear into a real `swift test` started from
/// inside a test run. The child's `PATH` is one scratch directory holding the
/// stub and links to the programs the runner starts, and
/// `testWithNoStubTheChildReachesNoSwift` holds that property on its own.
///
/// **Every row reads the runner's verdict.** An absence asserted over a
/// child that never ran is true of every run: a wrong script path, a missing
/// shell and a stub nobody started all print nothing, and nothing is exactly
/// what a row about a line that must not appear would accept. So each row
/// reads the last line as a verdict and fails when there is none, and each
/// names whether `swift` ran and with what — all but
/// `testEveryLastLineCarriesTheSameFieldsInTheSameOrder`, which reads the
/// line's shape and never the stub's record.
///
/// **A failure message never quotes a canned log.** This file's own run is
/// read by the same runner, which counts a `Test Case … started` line wherever
/// it sits on a line; a canned log printed into a message would be counted as
/// cases of this run. Messages carry the child's exit status, its last line
/// and its `!!` lines, each on the one line of the message.
final class TheRunnerFailsClosedTests: XCTestCase {

    // MARK: - What swift printed

    private enum Outcome {
        case passed, skipped, failed
    }

    /// One test case of a canned run.
    private struct Case {
        let target: String
        let type: String
        let method: String
        var outcome: Outcome = .passed

        func ended(_ outcome: Outcome) -> Case {
            Case(target: target, type: type, method: method, outcome: outcome)
        }
    }

    private static let stamp = "2026-01-05 10:00:00.000"

    /// Lines a log of a finished build begins with, whatever ran afterwards;
    /// a real one carries the build's progress lines among them.
    private static let buildLines = [
        "Building for debugging...",
        "[Computing dependencies]",
        "[Using on-disk description]",
        "Build complete! (1.13s)",
    ]

    private static let removable = [
        Case(target: "HelmRuntimeTests", type: "RemovableScopeTests", method: "testAnotherUsersLibraryIsRefused"),
        Case(target: "HelmRuntimeTests", type: "RemovableScopeTests", method: "testPartitionKeepsEveryPathAndItsOrder"),
        Case(target: "HelmRuntimeTests", type: "RemovableScopeTests", method: "testTraversalIsResolvedBeforeTheDecision"),
    ]

    /// A family that skips itself whole unless it is asked to measure.
    private static let benchmark = [
        Case(target: "HelmAppTests", type: "LogPageTickChurnBenchmark",
             method: "testAGrowingTailKeepsNothingPerTickEither", outcome: .skipped),
        Case(target: "HelmAppTests", type: "LogPageTickChurnBenchmark",
             method: "testAQuietTailStillChurnsEverySecond", outcome: .skipped),
    ]

    /// Three families whose name ends in `ScopeTests`, and no case of the
    /// family named `ScopeTests` alone: what a run holds once that family is
    /// gone.
    private static let scopes = [
        Case(target: "HelmRuntimeTests", type: "RemovableScopeTests", method: "testAnotherUsersLibraryIsRefused"),
        Case(target: "HelmRuntimeTests", type: "RemovableScopeTests", method: "testPartitionKeepsEveryPathAndItsOrder"),
        Case(target: "HelmRuntimeTests", type: "UserFileScopeTests", method: "testVolumeRootsAreProtected"),
        Case(target: "Module_Hosts_EngineTests", type: "SSHFileScopeTests", method: "testADirectoryIsRefused"),
    ]

    /// Eight cases across five bundles, chosen so that a name can be met as a
    /// target, as the start of a class, as a whole method, and only inside a
    /// longer name.
    private static let eight = [
        Case(target: "HelmRuntimeTests", type: "RemovableScopeTests", method: "testAnotherUsersLibraryIsRefused"),
        Case(target: "HelmRuntimeTests", type: "UserFileScopeTests", method: "testVolumeRootsAreProtected"),
        Case(target: "Module_Hosts_EngineTests", type: "SSHFileScopeTests", method: "testADirectoryIsRefused"),
        Case(target: "HelmUITests", type: "PublishedTokensAreTheTreesTests",
             method: "testTheRecordIsWhatTheTreeResolvesTo"),
        Case(target: "HelmUITests", type: "PublishedTokensAreTheTreesTests",
             method: "testTheRecordHoldsEveryTokenTheTreeHas"),
        Case(target: "HelmRuntimeTests", type: "DocumentsNameTheTreeTests",
             method: "testTheExcusedNamesAreStillMentioned"),
        Case(target: "Module_Layout_EngineTests", type: "LayoutEngineConcurrencyTests",
             method: "testConcurrentSettingsAndTapsUnderTheSanitiser"),
        Case(target: "Module_Leftovers_EngineTests", type: "LeftoversScanFootprintTests",
             method: "testAScanCostsItsItemsAndNotWhatItRead"),
    ]

    /// What one case leaves in a sequential log: the line that it started,
    /// then how it ended. A skip is two lines, the note and the case's own
    /// `skipped` line; a failure is the `error:` line and the case's `failed`.
    private static func caseLines(_ one: Case) -> [String] {
        let name = "-[\(one.target).\(one.type) \(one.method)]"
        let source = "/Helm/Tests/\(one.type).swift:207:"
        switch one.outcome {
        case .passed:
            return ["Test Case '\(name)' started.",
                    "Test Case '\(name)' passed (0.001 seconds)."]
        case .skipped:
            return ["Test Case '\(name)' started.",
                    "\(source) \(name) : Test skipped",
                    "Test Case '\(name)' skipped (0.001 seconds)."]
        case .failed:
            return ["Test Case '\(name)' started.",
                    "\(source) error: \(name) : XCTAssertTrue failed - a canned failure",
                    "Test Case '\(name)' failed (0.002 seconds)."]
        }
    }

    /// The two lines a suite closes with. The summary names skips only when
    /// there were some, and says `1 test` and `1 failure` without the plural.
    private static func closing(_ suite: String, _ cases: [Case]) -> [String] {
        let failed = cases.filter { $0.outcome == .failed }.count
        let skipped = cases.filter { $0.outcome == .skipped }.count
        func counted(_ count: Int, _ noun: String) -> String {
            "\(count) \(noun)\(count == 1 ? "" : "s")"
        }
        let skips = skipped > 0 ? "\(counted(skipped, "test")) skipped and " : ""
        return [
            "Test Suite '\(suite)' \(failed > 0 ? "failed" : "passed") at \(stamp).",
            "\t Executed \(counted(cases.count, "test")), with \(skips)\(counted(failed, "failure"))"
                + " (0 unexpected) in 0.001 (0.002) seconds",
        ]
    }

    /// The log of a sequential run in which these cases started: the build's
    /// lines, then one section per bundle, each closed three times over — the
    /// class, the bundle and the top suite each print their own summary. A
    /// filtered run also names a bundle in which nothing was selected, as
    /// every filtered run of this package does.
    private static func sequentialLog(_ cases: [Case], top: String = "Selected tests") -> String {
        var bundles: [(name: String, cases: [Case])] = []
        if top == "Selected tests" { bundles.append((name: "HelmContractTests", cases: [])) }
        for one in cases {
            if let at = bundles.firstIndex(where: { $0.name == one.target }) {
                bundles[at].cases.append(one)
            } else {
                bundles.append((name: one.target, cases: [one]))
            }
        }
        var lines = buildLines
        for bundle in bundles {
            lines.append("Test Suite '\(top)' started at \(stamp).")
            lines.append("Test Suite '\(bundle.name).xctest' started at \(stamp).")
            var types: [String] = []
            for one in bundle.cases where !types.contains(one.type) { types.append(one.type) }
            for type in types {
                let inType = bundle.cases.filter { $0.type == type }
                lines.append("Test Suite '\(type)' started at \(stamp).")
                for one in inType { lines += caseLines(one) }
                lines += closing(type, inType)
            }
            lines += closing("\(bundle.name).xctest", bundle.cases)
            lines += closing(top, bundle.cases)
        }
        return lines.joined(separator: "\n")
    }

    /// A log in the shape the runner reads as a parallel run: one progress
    /// line per case. The lines are spelled from the runner's own pattern for
    /// them and from nothing more — no log of a parallel run stands behind
    /// this shape.
    private static func parallelLog(_ cases: [Case]) -> String {
        var lines = buildLines
        for (index, one) in cases.enumerated() {
            lines.append("[\(index + 1)/\(cases.count)] Testing \(one.target).\(one.type)/\(one.method)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - What the runner is given

    /// Where the runner is told to keep its log.
    private enum LogPath {
        /// A plain file in scratch.
        case inScratch
        /// Nowhere: the runner reserves a name of its own under `TMPDIR`.
        case reservedByTheRunner
        /// Nowhere, and a `TMPDIR` that is not there to reserve a name in.
        case reservedUnderAMissingFolder
        /// A file in a folder that is not there.
        case underAMissingFolder
        /// The null device: it takes a write and is not a file.
        case notAPlainFile
        /// A plain file its owner may write and may not read.
        case writeOnly
    }

    /// One start of the runner.
    private struct Setup {
        /// What the runner is started with.
        var arguments: [String]
        /// What the stub prints. `nil` puts no `swift` on the child's `PATH`
        /// at all.
        var swiftPrints: String?
        var swiftExits: Int32 = 0
        var log: LogPath = .inScratch
        /// A shell `case` pattern over the arguments of one `grep` call. The
        /// call it matches is killed, the way a read of the log dies under a
        /// machine out of memory; every other call reaches the real `grep`.
        var grepDiesOn: String?
    }

    private static var clean: Setup {
        Setup(arguments: ["--filter", "RemovableScopeTests"], swiftPrints: sequentialLog(removable))
    }

    private static var everyCaseSkipped: Setup {
        Setup(arguments: ["--filter", "LogPageTickChurnBenchmark"], swiftPrints: sequentialLog(benchmark))
    }

    private static var oneOfThreeSkipped: Setup {
        var cases = removable
        cases[1] = cases[1].ended(.skipped)
        return Setup(arguments: ["--filter", "RemovableScopeTests"], swiftPrints: sequentialLog(cases))
    }

    private static var nothingRanWithNoFilter: Setup {
        Setup(arguments: ["--list-tests"], swiftPrints: buildLines.joined(separator: "\n"))
    }

    private static var oneAlternativeRanNothing: Setup {
        let ran = [Case(target: "HelmRuntimeTests", type: "TheMapNamesRealDirectoriesTests",
                        method: "testEveryDirectoryTheMapNamesExists")]
        return Setup(arguments: ["--filter", "TheMapNamesRealDirectoriesTests|NoSuchTestsAtAll"],
                     swiftPrints: sequentialLog(ran))
    }

    private static var aNameFoundOnlyInsideOthers: Setup {
        Setup(arguments: ["--filter", "ScopeTests|RemovableScopeTests"], swiftPrints: sequentialLog(scopes))
    }

    /// One case passed, one failed and one was skipped, so the summary lines
    /// carry a skip count in front of the failure count.
    private static var aFailureLine: Setup {
        var cases = removable
        cases[1] = cases[1].ended(.failed)
        cases[2] = cases[2].ended(.skipped)
        return Setup(arguments: ["--filter", "RemovableScopeTests"], swiftPrints: sequentialLog(cases))
    }

    private static var swiftExitingThree: Setup {
        var setup = clean
        setup.swiftExits = 3
        return setup
    }

    private static var parallel: Setup {
        let cases = removable + [Case(target: "HelmRuntimeTests", type: "RemovableScopeTests",
                                      method: "testTheContainingFoldersAreNeverRemovable")]
        return Setup(arguments: ["--parallel", "--filter", "RemovableScopeTests"], swiftPrints: parallelLog(cases))
    }

    /// Progress lines for two cases, and under them the lines a sequential
    /// run writes for the same two when both skip. Whether a parallel run
    /// ever writes the second half is not known; the row asks what the runner
    /// does if it does.
    private static var parallelWithEveryCaseSkipped: Setup {
        let log = parallelLog(benchmark) + "\n" + benchmark.flatMap(caseLines).joined(separator: "\n")
        return Setup(arguments: ["--parallel", "--filter", "LogPageTickChurnBenchmark"], swiftPrints: log)
    }

    private static var aNewlineInTheFilter: Setup {
        var setup = clean
        setup.arguments = ["--filter", "TheMapNamesRealDirectoriesTests|\nNoSuchTestsAtAll"]
        return setup
    }

    private static func keepingItsLog(_ log: LogPath) -> Setup {
        var setup = clean
        setup.log = log
        return setup
    }

    private static var printingNothing: Setup {
        Setup(arguments: ["--filter", "RemovableScopeTests"], swiftPrints: "")
    }

    private static func withGrepDying(on pattern: String) -> Setup {
        var setup = clean
        setup.grepDiesOn = pattern
        return setup
    }

    /// Four of the reads past the first counts, each by what its `grep` is
    /// asked: the cases that started, the cases that were skipped, how many
    /// lines a list holds, how many of them one alternative matches. The read
    /// of the progress lines is killed by no row.
    private static let readsThatCanDie = [
        (label: "the read of the cases that started", pattern: "*started*"),
        (label: "the read of the cases that were skipped", pattern: "*\"' skipped\"*"),
        (label: "a count of a list's lines", pattern: "'-c .'"),
        (label: "the count of one alternative", pattern: "'-cE -- '*"),
    ]

    // MARK: - Running it

    private struct SetupFailure: Error, CustomStringConvertible {
        let description: String
    }

    /// What one start of the runner left behind.
    private struct Run {
        let setup: Setup
        let status: Int32
        let stdout: [String]
        let stderr: [String]
        /// What the stub was started with, one argument an element; `nil`
        /// when it never ran.
        let swiftArguments: [String]?
        let grepDied: Bool
        let scratch: URL
        /// The child's whole `PATH`.
        let path: String

        var lastLine: String { stdout.last ?? "" }

        var complaints: [String] { stderr.filter { $0.hasPrefix("!! ") } }

        /// The `'<alternative>' -> <count>` lines of standard output.
        var counts: [String: String] {
            var found: [String: String] = [:]
            for line in stdout where line.hasPrefix("    '") {
                let from = line.index(line.startIndex, offsetBy: 5)
                guard let arrow = line.range(of: "' -> ", options: .backwards),
                      arrow.lowerBound >= from else { continue }
                found[String(line[from..<arrow.lowerBound])] = String(line[arrow.upperBound...])
            }
            return found
        }

        /// The child in one line, for a failure message.
        var said: String {
            "exit \(status); last line [\(lastLine)]; !! lines \(complaints)"
        }
    }

    /// The runner's last line, read as its parts.
    private struct Verdict {
        let word: String
        let runnerExit: String
        let swiftExit: String
        let fields: [(name: String, value: String)]

        var names: [String] { fields.map(\.name) }

        func value(_ name: String) -> String? {
            fields.first { $0.name == name }?.value
        }
    }

    private static let script = RepoSource.root.appendingPathComponent("Scripts/test.sh")

    /// Every program the runner starts besides `swift`. These, linked, and
    /// the stub are all the child's `PATH` holds, so a program the runner
    /// starts calling is added here or every row says `command not found`.
    private static let tools = ["grep", "sed", "sort", "mktemp", "mv"]

    private static func systemPath(of tool: String) throws -> String {
        for folder in ["/usr/bin", "/bin"] {
            let path = "\(folder)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        throw SetupFailure(description: "no \(tool) under /usr/bin or /bin to link the child's PATH to")
    }

    private func executable(_ text: String, at url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func lines(_ text: String) -> [String] {
        var all = text.components(separatedBy: "\n")
        while all.last == "" { all.removeLast() }
        return all
    }

    /// Starts the tree's own runner and waits for it.
    ///
    /// The child gets three things and nothing of this process's own: a
    /// `PATH` of one scratch directory, a `TMPDIR` in scratch, and a log path
    /// in scratch unless the row is about the path. Standard input is the
    /// null device, so a read with no file to read ends instead of waiting.
    private func runner(_ setup: Setup) throws -> Run {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: Self.script.path) else {
            throw SetupFailure(description: "no runner at \(Self.script.path)")
        }
        let scratch = scratchDirectory("runner")
        let bin = scratch.appendingPathComponent("bin")
        let tmp = scratch.appendingPathComponent("tmp")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        for tool in Self.tools {
            try fm.createSymbolicLink(atPath: bin.appendingPathComponent(tool).path,
                                      withDestinationPath: try Self.systemPath(of: tool))
        }

        let record = scratch.appendingPathComponent("swift-ran")
        let canned = scratch.appendingPathComponent("swift-prints")
        if let prints = setup.swiftPrints {
            try prints.write(to: canned, atomically: true, encoding: .utf8)
            try executable("""
                #!/bin/bash
                printf '%s\\n' "$@" > '\(record.path)'
                if [ -s '\(canned.path)' ]; then printf '%s\\n' "$(<'\(canned.path)')"; fi
                exit \(setup.swiftExits)

                """, at: bin.appendingPathComponent("swift"))
        }

        let died = scratch.appendingPathComponent("grep-died")
        if let pattern = setup.grepDiesOn {
            let grep = bin.appendingPathComponent("grep")
            let real = try Self.systemPath(of: "grep")
            try fm.removeItem(at: grep)
            try executable("""
                #!/bin/bash
                case "$*" in
                  \(pattern)) printf 'died\\n' > '\(died.path)'; kill -KILL $$ ;;
                esac
                exec '\(real)' "$@"

                """, at: grep)
        }

        var environment = ["PATH": bin.path, "TMPDIR": tmp.path]
        let plain = scratch.appendingPathComponent("run.log")
        switch setup.log {
        case .inScratch:
            environment["HELM_TEST_LOG"] = plain.path
        case .reservedByTheRunner:
            break
        case .reservedUnderAMissingFolder:
            environment["TMPDIR"] = scratch.appendingPathComponent("no-such-folder").path
        case .underAMissingFolder:
            environment["HELM_TEST_LOG"] = scratch.appendingPathComponent("no-such-folder/run.log").path
        case .notAPlainFile:
            environment["HELM_TEST_LOG"] = "/dev/null"
        case .writeOnly:
            try Data().write(to: plain)
            try fm.setAttributes([.posixPermissions: 0o200], ofItemAtPath: plain.path)
            environment["HELM_TEST_LOG"] = plain.path
        }

        let errors = scratch.appendingPathComponent("stderr")
        guard fm.createFile(atPath: errors.path, contents: nil) else {
            throw SetupFailure(description: "could not create \(errors.path)")
        }
        let errorHandle = try FileHandle(forWritingTo: errors)
        defer { try? errorHandle.close() }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [Self.script.path] + setup.arguments
        proc.currentDirectoryURL = scratch
        proc.environment = environment
        let pipe = Pipe()
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = pipe
        proc.standardError = errorHandle
        try proc.run()
        // Read before the wait: a pipe nobody drains is how a test of a child
        // process hangs for ever. Standard error goes to a file, which never
        // fills, so the two are told apart without a second pipe to drain.
        let out = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        proc.waitUntilExit()
        let err = (try? String(contentsOf: errors, encoding: .utf8)) ?? ""
        let ran = (try? String(contentsOf: record, encoding: .utf8)).map(Self.lines)

        return Run(setup: setup, status: proc.terminationStatus,
                   stdout: Self.lines(out), stderr: Self.lines(err),
                   swiftArguments: ran, grepDied: fm.fileExists(atPath: died.path),
                   scratch: scratch, path: bin.path)
    }

    // MARK: - Reading what it said

    /// The last line as a verdict, or a failure when the child's last line is
    /// not one — which is what a child that never ran the runner prints.
    private func judgement(of run: Run, file: StaticString = #filePath, line: UInt = #line) -> Verdict? {
        let last = run.lastLine
        let pattern = #"^==> ([A-Z]+) \(runner exit=([^,)]*), swift test exit=([^)]*)\)(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: last, range: NSRange(last.startIndex..., in: last)),
              match.numberOfRanges == 5 else {
            XCTFail("the child's last line is not the runner's verdict; \(run.said)", file: file, line: line)
            return nil
        }
        func group(_ index: Int) -> String {
            Range(match.range(at: index), in: last).map { String(last[$0]) } ?? ""
        }
        // Fields follow the parenthesis, each behind two spaces.
        let pieces = group(4).components(separatedBy: "  ")
        guard pieces.count > 1, pieces[0].isEmpty else {
            XCTFail("the runner's last line carries no fields; \(run.said)", file: file, line: line)
            return nil
        }
        var fields: [(name: String, value: String)] = []
        for piece in pieces.dropFirst() {
            guard let equals = piece.firstIndex(of: "=") else {
                XCTFail("a field of the last line has no value: [\(piece)]; \(run.said)", file: file, line: line)
                return nil
            }
            fields.append((name: String(piece[..<equals]), value: String(piece[piece.index(after: equals)...])))
        }
        return Verdict(word: group(1), runnerExit: group(2), swiftExit: group(3), fields: fields)
    }

    /// What a row asks of every start of the runner: the runner gave a
    /// verdict, its word and its exit status are the expected ones, the status
    /// the line names is the one the runner exited with, and `swift` was
    /// started with exactly what the runner was given — or, for a refusal, was
    /// never started. Two rows do not come through here:
    /// `testEveryLastLineCarriesTheSameFieldsInTheSameOrder` reads the line's
    /// shape alone, and `testWithNoStubTheChildReachesNoSwift` asks its own
    /// version of this of a child with no stub to start.
    @discardableResult
    private func assertJudged(_ run: Run, _ word: String, exit status: Int32, swiftRan: Bool = true,
                              file: StaticString = #filePath, line: UInt = #line) -> Verdict? {
        guard let verdict = judgement(of: run, file: file, line: line) else { return nil }
        XCTAssertEqual(verdict.word, word, "the last line's word; \(run.said)", file: file, line: line)
        XCTAssertEqual(run.status, status, "the runner's exit status; \(run.said)", file: file, line: line)
        XCTAssertEqual(verdict.runnerExit, String(run.status),
                       "the last line names a status the runner did not exit with; \(run.said)",
                       file: file, line: line)
        if swiftRan {
            XCTAssertEqual(run.swiftArguments, ["test"] + run.setup.arguments,
                           "swift was not started with what the runner was given (nil: never started); \(run.said)",
                           file: file, line: line)
            XCTAssertEqual(verdict.swiftExit, String(run.setup.swiftExits),
                           "the status the last line reports for swift; \(run.said)", file: file, line: line)
        } else {
            XCTAssertNil(run.swiftArguments, "swift was started although the runner refused; \(run.said)",
                         file: file, line: line)
            XCTAssertEqual(verdict.swiftExit, "not run",
                           "the last line of a refusal says swift ran; \(run.said)", file: file, line: line)
        }
        return verdict
    }

    private func assertComplains(_ run: Run, _ beginning: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(run.complaints.contains { $0.hasPrefix(beginning) },
                      "no line on standard error begins [\(beginning)]; \(run.said)", file: file, line: line)
    }

    private func assertSilent(_ run: Run, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(run.complaints, [], "a run that passed left a !! line; \(run.said)", file: file, line: line)
    }

    /// The names a `!!` line lists after its opening words, up to the dash
    /// the sentence goes on behind; `nil` when no line opens that way.
    private func names(after beginning: String, in run: Run) -> [String]? {
        guard let line = run.complaints.first(where: { $0.hasPrefix(beginning) }) else { return nil }
        let rest = String(line.dropFirst(beginning.count))
        let list = rest.components(separatedBy: " \u{2014} ").first ?? rest
        return list.components(separatedBy: " ").filter { !$0.isEmpty }
    }

    private static let ranNothing = "!! filter alternative(s) ran no test case as grep -E reads it: "
    private static let foundOnlyInside =
        "!! filter alternative(s) begin no target, class or method name and were found only inside one: "
    private static let nobodySearched = "!! 0 test case(s) ran and swift test never reported a search"

    // MARK: - A run that asserted nothing

    /// Every selected case skipped is a run that asserted nothing, and a
    /// family behind an environment switch skips whole every time it is named
    /// without the switch. The word must say so and the status must fail, for
    /// a reader who looks for `PASS` and for one who looks at the status.
    func testARunInWhichEveryCaseWasSkippedIsNotAPass() throws {
        let run = try runner(Self.everyCaseSkipped)
        if let verdict = assertJudged(run, "SKIPPED", exit: 1) {
            XCTAssertEqual(verdict.value("selected"), "2", "the cases that started; \(run.said)")
            XCTAssertEqual(verdict.value("skipped"), "2", "the cases that were skipped; \(run.said)")
        }
        XCTAssertEqual(run.counts["LogPageTickChurnBenchmark"], "2",
                       "the family is still counted as selected; \(run.said)")
        assertComplains(run, "!! all 2 selected test case(s) were skipped")

        // One case is a run too.
        let single = try runner(Setup(arguments: ["--filter", "LogPageTickChurnBenchmark"],
                                      swiftPrints: Self.sequentialLog([Self.benchmark[0]])))
        if let verdict = assertJudged(single, "SKIPPED", exit: 1) {
            XCTAssertEqual(verdict.value("skipped"), "1", "the one case that was skipped; \(single.said)")
        }
        assertComplains(single, "!! all 1 selected test case(s) were skipped")
    }

    /// One case that asserted is enough for a pass; what the last line owes
    /// its reader then is the number that did not.
    func testARunInWhichSomeCasesWereSkippedPassesAndCountsThem() throws {
        let run = try runner(Self.oneOfThreeSkipped)
        if let verdict = assertJudged(run, "PASS", exit: 0) {
            XCTAssertEqual(verdict.value("selected"), "3", "the cases that started; \(run.said)")
            XCTAssertEqual(verdict.value("skipped"), "1", "the cases that were skipped; \(run.said)")
        }
        assertSilent(run)

        // All but one skipped is still a run that asserted something.
        var cases = Self.removable
        cases[0] = cases[0].ended(.skipped)
        cases[2] = cases[2].ended(.skipped)
        let most = try runner(Setup(arguments: ["--filter", "RemovableScopeTests"],
                                    swiftPrints: Self.sequentialLog(cases)))
        if let verdict = assertJudged(most, "PASS", exit: 0) {
            XCTAssertEqual(verdict.value("skipped"), "2", "the cases that were skipped; \(most.said)")
        }
        assertSilent(most)
    }

    /// With no filter the runner had nothing to count alternatives against,
    /// and a run in which no case started passed with `selected=0`. The log
    /// here holds the build's lines and nothing after them.
    func testARunWithNoFilterInWhichNothingRanFails() throws {
        let run = try runner(Self.nothingRanWithNoFilter)
        if let verdict = assertJudged(run, "FAIL", exit: 1) {
            XCTAssertEqual(verdict.value("selected"), "0", "the cases that started; \(run.said)")
        }
        assertComplains(run, Self.nobodySearched)
    }

    // MARK: - A name found only inside another

    /// `swift test` reads an alternative as a pattern, so `ScopeTests` runs
    /// every family whose name ends that way; counting the same way reports
    /// the family named `ScopeTests` as run over a log that holds no case of
    /// it.
    func testABareNameFoundOnlyInsideAnotherFamilysNameRanNothing() throws {
        let run = try runner(Self.aNameFoundOnlyInsideOthers)
        assertJudged(run, "FAIL", exit: 1)
        XCTAssertEqual(run.counts["ScopeTests"], "0",
                       "no target, class or method begins with the name; \(run.said)")
        XCTAssertEqual(run.counts["RemovableScopeTests"], "2", "the family that is there; \(run.said)")
        XCTAssertEqual(names(after: Self.foundOnlyInside, in: run), ["ScopeTests"],
                       "the !! line that names what was found only inside a name; \(run.said)")
        XCTAssertNil(names(after: Self.ranNothing, in: run),
                     "a name found inside another is not one that matched nothing; \(run.said)")
    }

    /// The rule behind the row above, over every kind of fragment: the end of
    /// a class name, the middle of one, and a word every name ends in.
    func testABareNameIsCountedOnlyFromTheStartOfAName() throws {
        let log = Self.sequentialLog(Self.eight)
        for fragment in ["ScopeTests", "ScanFootprintTests", "TokensAreTheTrees", "Tests"] {
            let run = try runner(Setup(arguments: ["--filter", fragment], swiftPrints: log))
            assertJudged(run, "FAIL", exit: 1)
            XCTAssertEqual(run.counts[fragment], "0", "\(fragment) begins no name; \(run.said)")
            XCTAssertEqual(names(after: Self.foundOnlyInside, in: run), [fragment],
                           "the !! line that names \(fragment) as found only inside a name; \(run.said)")
        }
    }

    /// The other half of the rule, so that a boundary cannot be bought by
    /// refusing what is spelled today: a whole name, the start of one, a
    /// target, a method and every pattern count as they did, and a name that
    /// matches nothing is still said to have matched nothing.
    func testANameThatBeginsOneAndAPatternAreCountedAsBefore() throws {
        let log = Self.sequentialLog(Self.eight)
        let counted = [
            ("RemovableScopeTests", "1"),
            ("PublishedTokensAreTheTrees", "2"),
            ("HelmRuntimeTests", "3"),
            ("testConcurrentSettingsAndTapsUnderTheSanitiser", "1"),
            ("Module_", "3"),
            (".*ScopeTests", "3"),
            ("DocumentsNameTheTreeTests/testTheExcusedNamesAreStillMentioned", "1"),
            ("HelmUITests.PublishedTokensAreTheTreesTests", "2"),
        ]
        for (alternative, count) in counted {
            let run = try runner(Setup(arguments: ["--filter", alternative], swiftPrints: log))
            assertJudged(run, "PASS", exit: 0)
            XCTAssertEqual(run.counts[alternative], count, "the cases \(alternative) selects; \(run.said)")
            assertSilent(run)
        }

        // An empty alternative is a pattern that matches every case.
        let empty = try runner(Setup(arguments: ["--filter", "|RemovableScopeTests"], swiftPrints: log))
        assertJudged(empty, "PASS", exit: 0)
        XCTAssertEqual(empty.counts[""], "8", "the empty alternative; \(empty.said)")
        XCTAssertEqual(empty.counts["RemovableScopeTests"], "1", "the family beside it; \(empty.said)")

        for missing in ["NoSuchTestsAtAll", "ScopeTests$"] {
            let run = try runner(Setup(arguments: ["--filter", missing], swiftPrints: log))
            assertJudged(run, "FAIL", exit: 1)
            XCTAssertEqual(run.counts[missing], "0", "the cases \(missing) selects; \(run.said)")
            XCTAssertEqual(names(after: Self.ranNothing, in: run), [missing],
                           "the !! line that names what ran nothing; \(run.said)")
            XCTAssertNil(names(after: Self.foundOnlyInside, in: run),
                         "a name that matches nothing was not found inside one; \(run.said)")
        }

        let unparsed = try runner(Setup(arguments: ["--filter", "NoSuch(A"], swiftPrints: log))
        assertJudged(unparsed, "FAIL", exit: 1)
        XCTAssertTrue(unparsed.stderr.contains { $0.hasPrefix("    'NoSuch(A' -> unreadable by grep -E") },
                      "an alternative grep cannot parse is reported as unread; \(unparsed.said)")
        XCTAssertEqual(names(after: "!! filter alternative(s) could not be checked (unreadable by grep -E): ",
                             in: unparsed), ["NoSuch(A"], "the !! line that names it; \(unparsed.said)")
    }

    // MARK: - The last line

    private struct Shape {
        let label: String
        let setup: Setup
        /// How `log=` ends where the runner stopped early: `not written`
        /// before `swift` ran, a reason in parentheses after. It tells the
        /// kinds of early exit apart, not two exits that end alike.
        var ending: String?
        /// `nil`: the runner knows of skips what it knows of the selection,
        /// so the field says what `selected=` says.
        var skipped: String?
    }

    private static let fieldsInOrder = ["failure-lines", "selected", "skipped", "log"]

    /// One line, one shape. A reader takes the fields by position as readily
    /// as by name, and the runner prints its last line from every place
    /// `command grep -cE 'echo "==> (FAIL|\$VERDICT) \(runner exit=' Scripts/test.sh`
    /// counts: the exits that stop before a verdict and the verdict itself.
    /// Each exit that scratch can reach is taken here.
    func testEveryLastLineCarriesTheSameFieldsInTheSameOrder() throws {
        var rows = [
            Shape(label: "nothing skipped", setup: Self.clean, skipped: "0"),
            Shape(label: "every case skipped", setup: Self.everyCaseSkipped, skipped: "2"),
            Shape(label: "one of three skipped", setup: Self.oneOfThreeSkipped, skipped: "1"),
            Shape(label: "no filter and nothing ran", setup: Self.nothingRanWithNoFilter, skipped: "0"),
            Shape(label: "an alternative that ran nothing", setup: Self.oneAlternativeRanNothing, skipped: "0"),
            Shape(label: "a name found only inside others", setup: Self.aNameFoundOnlyInsideOthers,
                  skipped: "0"),
            Shape(label: "a failure line", setup: Self.aFailureLine, skipped: "1"),
            Shape(label: "swift exiting 3", setup: Self.swiftExitingThree, skipped: "0"),
            Shape(label: "a parallel run", setup: Self.parallel, skipped: "unknown"),
            Shape(label: "a newline in the filter", setup: Self.aNewlineInTheFilter,
                  ending: "not written", skipped: "0"),
            Shape(label: "no folder to reserve a log in", setup: Self.keepingItsLog(.reservedUnderAMissingFolder),
                  ending: "not written"),
            Shape(label: "a log path that takes no write", setup: Self.keepingItsLog(.underAMissingFolder),
                  ending: "not written"),
            Shape(label: "a log that is a device", setup: Self.keepingItsLog(.notAPlainFile),
                  ending: "(not a plain file)", skipped: "unknown"),
            Shape(label: "a log grep cannot open", setup: Self.keepingItsLog(.writeOnly),
                  ending: "(unreadable)", skipped: "unknown"),
            Shape(label: "a log read back empty", setup: Self.printingNothing, ending: "(empty on read-back)"),
        ]
        for read in Self.readsThatCanDie {
            rows.append(Shape(label: "grep killed on \(read.label)", setup: Self.withGrepDying(on: read.pattern),
                              ending: "(unreadable)", skipped: "unknown"))
        }
        for row in rows {
            let run = try runner(row.setup)
            guard let verdict = judgement(of: run) else { continue }
            if let ending = row.ending {
                XCTAssertTrue(verdict.value("log")?.hasSuffix(ending) == true,
                              "\(row.label): the runner left by another exit than the row is about; \(run.said)")
            }
            guard verdict.names == Self.fieldsInOrder else {
                XCTFail("\(row.label): the last line's fields are \(verdict.names), not \(Self.fieldsInOrder); "
                        + run.said)
                continue
            }
            XCTAssertEqual(verdict.value("skipped"), row.skipped ?? verdict.value("selected"),
                           "\(row.label): the skip count; \(run.said)")
        }
    }

    /// The runner counts skips from the lines a sequential run writes for a
    /// case, and a parallel run is not known to write them, so over a
    /// parallel log it must say it does not know rather than say zero.
    func testAParallelRunStatesNoSkipCount() throws {
        for setup in [Self.parallel, Self.parallelWithEveryCaseSkipped] {
            let run = try runner(setup)
            guard let verdict = assertJudged(run, "PASS", exit: 0) else { continue }
            XCTAssertEqual(verdict.value("skipped"), "unknown",
                           "a skip count stated over a parallel log; \(run.said)")
        }
    }

    /// A count the runner does not state cannot carry a verdict: where the
    /// log has progress lines, cases whose every sequential line says
    /// `skipped` still leave the word as it was.
    func testAParallelRunIsNeverCalledAllSkipped() throws {
        let run = try runner(Self.parallelWithEveryCaseSkipped)
        if let verdict = assertJudged(run, "PASS", exit: 0) {
            XCTAssertEqual(verdict.value("selected"), "2",
                           "a case named by both shapes is one case; \(run.said)")
        }
        XCTAssertEqual(run.counts["LogPageTickChurnBenchmark"], "2", "the family is counted; \(run.said)")

        let plain = try runner(Self.parallel)
        if let verdict = assertJudged(plain, "PASS", exit: 0) {
            XCTAssertEqual(verdict.value("selected"), "4", "one case a progress line; \(plain.said)")
        }
        assertSilent(plain)
    }

    // MARK: - What already failed closed

    /// `swift test` exits 0 when only some alternatives of a filter match;
    /// the runner is what names the one that ran nothing.
    func testAFilterAlternativeThatRanNothingFailsTheRun() throws {
        let run = try runner(Self.oneAlternativeRanNothing)
        assertJudged(run, "FAIL", exit: 1)
        XCTAssertEqual(run.counts["TheMapNamesRealDirectoriesTests"], "1", "the family that ran; \(run.said)")
        XCTAssertEqual(run.counts["NoSuchTestsAtAll"], "0", "the one that did not; \(run.said)")
        XCTAssertEqual(names(after: Self.ranNothing, in: run), ["NoSuchTestsAtAll"],
                       "the !! line that names what ran nothing; \(run.said)")
    }

    /// A filter under which nothing started, with no word from `swift test`
    /// that it looked: the line the no-filter row above asks for, on the
    /// path where the runner has always printed it.
    func testAFilterUnderWhichNothingRanFails() throws {
        let run = try runner(Setup(arguments: ["--filter", "NoSuchTestsAtAll"],
                                   swiftPrints: Self.buildLines.joined(separator: "\n")))
        assertJudged(run, "FAIL", exit: 1)
        assertComplains(run, Self.nobodySearched)
    }

    /// `swift test` says so itself when no alternative matched anything, and
    /// then the runner must not also say that nobody searched. The warning is
    /// spelled as the runner's own count looks for it.
    func testASearchThatMatchedNothingFailsAndIsNotCalledSilent() throws {
        let log = Self.sequentialLog([]) + "\nwarning: No matching test cases were run"
        let run = try runner(Setup(arguments: ["--filter", "NoSuchTestsAtAll"], swiftPrints: log))
        assertJudged(run, "FAIL", exit: 1)
        assertComplains(run, "!! log carries \"No matching test cases were run\" (1)")
        XCTAssertFalse(run.complaints.contains { $0.hasPrefix(Self.nobodySearched) },
                       "swift test reported its search and the runner says it never did; \(run.said)")
    }

    /// The null device takes every write and gives nothing back, so a log
    /// kept there must fail the run rather than read as a clean one.
    func testALogThatIsNotAPlainFileFails() throws {
        let run = try runner(Self.keepingItsLog(.notAPlainFile))
        if let verdict = assertJudged(run, "FAIL", exit: 1) {
            XCTAssertEqual(verdict.value("log"), "/dev/null (not a plain file)", "where it says it left; \(run.said)")
        }
        assertComplains(run, "!! the log at /dev/null is not a plain file")
    }

    /// A path can take a write and refuse a read. A count that could not be
    /// taken is not a count of zero.
    func testALogTheRunnerCannotOpenFails() throws {
        let run = try runner(Self.keepingItsLog(.writeOnly))
        let log = run.scratch.appendingPathComponent("run.log").path
        let mode = try FileManager.default.attributesOfItem(atPath: log)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o200, "the log stopped being write-only, so nothing refused the read")
        if let verdict = assertJudged(run, "FAIL", exit: 1) {
            XCTAssertEqual(verdict.value("log"), "\(log) (unreadable)", "where it says it left; \(run.said)")
        }
        assertComplains(run, "!! cannot read the log at \(log) after swift test ran")
    }

    /// Every real run leaves at least the build's lines behind, so a log with
    /// no line in it is the runner failing to see what was written.
    func testALogThatReadsBackEmptyFails() throws {
        let run = try runner(Self.printingNothing)
        if let verdict = assertJudged(run, "FAIL", exit: 1) {
            XCTAssertTrue(verdict.value("log")?.hasSuffix("(empty on read-back)") == true,
                          "where it says it left; \(run.said)")
        }
        XCTAssertTrue(run.complaints.contains { $0.contains("read back with no lines after swift test ran") },
                      "no !! line says the log read back empty; \(run.said)")
    }

    /// A `grep` killed mid-read answers nothing, and nothing once read as a
    /// clean count. Each read `readsThatCanDie` names is killed in turn; the
    /// stand-in leaves a mark, so the row knows the read it was about really
    /// died.
    func testAReadOfTheLogThatDiesFails() throws {
        for read in Self.readsThatCanDie {
            let run = try runner(Self.withGrepDying(on: read.pattern))
            XCTAssertTrue(run.grepDied, "\(read.label) was never asked for, so nothing died; \(run.said)")
            if let verdict = assertJudged(run, "FAIL", exit: 1) {
                XCTAssertTrue(verdict.value("log")?.hasSuffix("(unreadable)") == true,
                              "\(read.label): where it says it left; \(run.said)")
            }
            assertComplains(run, "!! cannot read ")
        }
    }

    /// `grep` reads a pattern holding a newline as two patterns, and the
    /// empty one matches every case, so a misspelled alternative behind a
    /// newline counted as run. The value is refused before the run is spent:
    /// the proof here is that the stub left no record.
    func testANewlineInAFilterValueIsRefusedBeforeSwiftRuns() throws {
        var joined = Self.aNewlineInTheFilter
        joined.arguments = ["--filter=TheMapNamesRealDirectoriesTests|\nNoSuchTestsAtAll"]
        for setup in [Self.aNewlineInTheFilter, joined] {
            let run = try runner(setup)
            if let verdict = assertJudged(run, "FAIL", exit: 1, swiftRan: false) {
                XCTAssertEqual(verdict.value("log"), "not written", "where it says it left; \(run.said)")
            }
            assertComplains(run, "!! --filter value contains a newline byte, refused before swift test runs")
        }
    }

    /// A log path that cannot be had is refused before the run too: with no
    /// folder to reserve a name in, and with a path that takes no write.
    func testALogPathThatCannotBeHadIsRefusedBeforeSwiftRuns() throws {
        let unreserved = try runner(Self.keepingItsLog(.reservedUnderAMissingFolder))
        assertJudged(unreserved, "FAIL", exit: 1, swiftRan: false)
        assertComplains(unreserved, "!! mktemp failed to reserve a log path under ")

        let unwritable = try runner(Self.keepingItsLog(.underAMissingFolder))
        assertJudged(unwritable, "FAIL", exit: 1, swiftRan: false)
        assertComplains(unwritable, "!! cannot write the log at ")
    }

    // MARK: - Controls

    /// The other side of every row above: a run in which cases ran and none
    /// was skipped passes, without a word on standard error.
    func testACleanRunPasses() throws {
        let run = try runner(Self.clean)
        if let verdict = assertJudged(run, "PASS", exit: 0) {
            XCTAssertEqual(verdict.value("selected"), "3", "the cases that started; \(run.said)")
            XCTAssertEqual(verdict.value("failure-lines"), "0", "the failure lines; \(run.said)")
        }
        XCTAssertEqual(run.counts["RemovableScopeTests"], "3", "the family; \(run.said)")
        assertSilent(run)
    }

    /// A rule about a run with no filter in which nothing ran must leave the
    /// run with no filter in which cases ran alone: that one is the suite.
    func testARunWithNoFilterInWhichCasesRanPasses() throws {
        let run = try runner(Setup(arguments: [],
                                   swiftPrints: Self.sequentialLog(Self.eight, top: "All tests")))
        if let verdict = assertJudged(run, "PASS", exit: 0) {
            XCTAssertEqual(verdict.value("selected"), "8", "the cases that started; \(run.said)")
        }
        XCTAssertEqual(run.counts, [:], "alternatives counted with no filter given; \(run.said)")
        assertSilent(run)
    }

    /// The summary line of a run with a failure and a skip names the skips
    /// first, and a pattern written for the plain line reads it as clean. The
    /// log alone must fail the run, whatever `swift test` exited with.
    func testALogWithAFailureLineFails() throws {
        var setup = Self.aFailureLine
        for status in [Int32(0), 1] {
            setup.swiftExits = status
            let run = try runner(setup)
            if let verdict = assertJudged(run, "FAIL", exit: 1) {
                XCTAssertGreaterThan(Int(verdict.value("failure-lines") ?? "") ?? 0, 0,
                                     "the failure lines; \(run.said)")
            }
            assertComplains(run, "!! log carries a failure line")
        }
    }

    /// The runner's status is `swift test`'s own when that one failed, and no
    /// reading of the log outranks it: a run that exited non-zero with every
    /// case skipped has failed, it has not been skipped.
    func testASwiftThatExitsNonZeroFailsWithItsStatus() throws {
        var skipped = Self.everyCaseSkipped
        skipped.swiftExits = 3
        for setup in [Self.swiftExitingThree, skipped] {
            let run = try runner(setup)
            assertJudged(run, "FAIL", exit: 3)
            assertComplains(run, "!! swift test itself exited 3")
        }
    }

    /// With no log path given the runner reserves one, and it must land under
    /// the child's `TMPDIR` and hold what `swift` printed — the path a row
    /// that names a log of its own never takes.
    func testTheRunnerReservesItsOwnLogUnderTheChildsTMPDIR() throws {
        let run = try runner(Self.keepingItsLog(.reservedByTheRunner))
        guard let verdict = assertJudged(run, "PASS", exit: 0), let log = verdict.value("log") else { return }
        let reserved = run.scratch.appendingPathComponent("tmp").path + "/helm-test."
        XCTAssertTrue(log.hasPrefix(reserved) && log.hasSuffix(".log"),
                      "the log is not a name reserved under the child's TMPDIR; \(run.said)")
        let written = try String(contentsOfFile: log, encoding: .utf8)
        XCTAssertTrue(written == (run.setup.swiftPrints ?? "") + "\n",
                      "the reserved log does not hold what swift printed (\(Self.lines(written).count) lines)")
    }

    /// The property the whole harness stands on. With no stub in the
    /// directory the child finds no `swift` anywhere: the shell says so into
    /// the log and the run fails with the shell's own status. The runner is
    /// asked for a version only, so a `PATH` that did reach a real `swift`
    /// would print a line here rather than build.
    func testWithNoStubTheChildReachesNoSwift() throws {
        let run = try runner(Setup(arguments: ["--version"], swiftPrints: nil))
        XCTAssertFalse(run.path.contains(":"), "the child's PATH is more than one directory: \(run.path)")
        XCTAssertTrue(run.path.hasPrefix(run.scratch.path + "/"), "the child's PATH leaves scratch: \(run.path)")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: run.path).sorted(), Self.tools.sorted(),
                       "the child's PATH holds something beside the runner's tools")

        XCTAssertNil(run.swiftArguments, "a stub ran where none was written; \(run.said)")
        guard let verdict = judgement(of: run) else { return }
        XCTAssertEqual(verdict.word, "FAIL", "the last line's word; \(run.said)")
        XCTAssertEqual(run.status, 127, "the shell's status for a command it cannot find; \(run.said)")
        XCTAssertEqual(verdict.swiftExit, "127", "the status the last line reports for swift; \(run.said)")
        assertComplains(run, "!! swift test itself exited 127")

        let log = Self.lines(try String(contentsOf: run.scratch.appendingPathComponent("run.log"), encoding: .utf8))
        XCTAssertEqual(log.count, 1, "the log holds more than the shell's one line: \(log.prefix(3))")
        XCTAssertTrue(log.first?.hasSuffix("swift: command not found") == true,
                      "the log does not say that no swift was found: \(log.prefix(3))")
    }
}
