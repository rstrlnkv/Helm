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
/// **How.** Each case starts the tree's own script, or a copy of it beside a
/// `Tests/` of the row's making, with a `swift` that is a stub: it records the
/// arguments it was started with, prints a canned log and exits with a canned
/// status. The logs are spelled here, in the lines `swift test` writes, so a
/// row says in one place what the runner was shown and what it must answer.
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
/// line's shape and never the stub's record, and the two rows that read a
/// tier's expansion, which read the stub's record and the tier's own line and
/// not the verdict.
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
        /// Files of a `Tests/` of the child's own, by path under it. With
        /// some, the child runs a copy of the runner that lies beside that
        /// `Tests/` in scratch, so a tier is read off these files and not off
        /// the tree.
        var tree: [String: String]?
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

        var script = Self.script
        if let tree = setup.tree {
            let scripts = scratch.appendingPathComponent("Scripts")
            try fm.createDirectory(at: scripts, withIntermediateDirectories: true)
            script = scripts.appendingPathComponent("test.sh")
            try fm.copyItem(at: Self.script, to: script)
            for (relative, text) in tree {
                let file = scratch.appendingPathComponent("Tests").appendingPathComponent(relative)
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: file, atomically: true, encoding: .utf8)
            }
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
        proc.arguments = [script.path] + setup.arguments
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
    /// never started. Rows that do not come through here:
    /// `testEveryLastLineCarriesTheSameFieldsInTheSameOrder` reads the line's
    /// shape alone, `testWithNoStubTheChildReachesNoSwift` asks its own
    /// version of this of a child with no stub to start, and the rows of a
    /// named tier ask theirs — `swift` is handed a rewritten `--filter` where a
    /// tier starts it (`assertJudgedTier`) — all but
    /// `testANewlineInATierValueIsRefusedBeforeSwiftRuns`, a refusal that never
    /// starts `swift` and comes through here.
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
            Shape(label: "a tier nobody named", setup: Setup(arguments: ["--tier", "NoSuchTier"],
                                                             swiftPrints: Self.sequentialLog(Self.removable)),
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

    // MARK: - A named tier

    /// `--tier <name>` asks for a set of families by where they lie, and the
    /// runner turns it into one `--filter` of `Target\.Class/` addresses for
    /// `swift test`. The rows below hold it, and none of them keeps a list of
    /// a directory's classes: `testEveryNameATierHandsSwiftIsATestClassUnderTests`
    /// and `testEveryTestClassIsInExactlyTheTiersItsPlaceSays` read the tree
    /// itself, through `SwiftSource`, and hold what the runner handed the stub
    /// against that reading; the others hold the runner to the families it
    /// handed over, to its refusals, and to a `Tests/` of the row's own making
    /// for the tiers the tree has none of.
    ///
    /// **The window words are spelled in pieces.** A family whose file holds
    /// one of the words that order a window is left out of every tier but
    /// `windows`, and the runner reads the raw text of the file, comments
    /// included. This file computes the same rule, so a word spelled whole here
    /// would take this class into `windows` and out of `HelmRuntimeTests`; so
    /// would the name of a class that orders a window, written with a dot and a
    /// letter behind it. `testEveryTestClassIsInExactlyTheTiersItsPlaceSays`
    /// says where this class lies.
    ///
    /// The five calls that order a window or make it key or main. A file
    /// holding one of them and no test class is a window rig.
    private static let windowWords = [
        "order" + "Front", "order" + "Back", "make" + "Key", "make" + "Main", "NSApp" + #"\."# + "activate",
    ].joined(separator: "|")

    /// The four spellings through which a test puts a window of the product on
    /// the screen. They mark a class, and make no rig.
    private static let productWindowWords = [
        #"\."# + "show" + #"\(\)"#, #"\."# + "openMenu" + #"\(\)"#, "windowed" + ": " + "true", "PanelRig" + #"\."# + "rig",
    ].joined(separator: "|")

    /// What a file says when it reads the standing documents, spelled in two
    /// pieces for the reason above.
    private static let documentsWord = "Standing" + "Documents"

    /// The tiers that lie over the directories rather than being one.
    private static let laidOverTiers = ["docs", "strings", "windows"]

    /// Fewer classes than this under `Tests/` means the reader read nothing.
    private static let censusFloor = 500

    /// One test class of the tree and where its file lies.
    private struct Family {
        /// What `swift test` calls the bundle: a directory of `Tests/`, or
        /// `Module_<Name>_<EngineTests|UITests>`.
        let target: String
        let name: String
        /// The tier the file's place names: its directory of `Tests/`, or the module's.
        let place: String
        /// The file holds one of the nine window words.
        let hasWindowWord: Bool
        /// The file names something a window rig declares.
        let usesWindowRig: Bool
        /// The file names a member of a class that the nine words or a rig
        /// found, one step deep.
        let namesAWindowMember: Bool
        /// The file names the standing documents.
        let readsTheDocuments: Bool

        var address: String { "\(target).\(name)" }
        var ordersAWindow: Bool { hasWindowWord || usesWindowRig || namesAWindowMember }
    }

    /// Every test class under `Tests/`, by its address.
    private struct Census {
        let families: [String: Family]

        var places: [String] { Set(families.values.map(\.place)).sorted() }
    }

    /// The census, read once a process.
    ///
    /// A class is `final class X: XCTestCase` with any attributes before it,
    /// read off the file with comments and string bodies blanked. A window
    /// word and the standing documents are read off the raw text: a window
    /// word is any of the nine, the five calls and the four spellings. A rig
    /// is a file with one of the five and no test class, and a class names it
    /// when it uses, as a whole word, anything the rig declares at column one.
    /// A class found by a window word or a rig is a seed, and a file that names
    /// a member of a seed (the seed's name as a whole word, a dot, a letter or
    /// an underscore) marks its classes too. The step is taken once: a class it
    /// marks is no seed.
    private static let census = Result { try readCensus() }

    private static func readCensus() throws -> Census {
        let classLine = try NSRegularExpression(
            pattern: #"^(@[A-Za-z]+ )*(final )?class ([A-Za-z0-9_]+) *: *XCTestCase"#,
            options: [.anchorsMatchLines])
        let orderingWord = try NSRegularExpression(pattern: windowWords)
        let windowWord = try NSRegularExpression(pattern: windowWords + "|" + productWindowWords)
        let declaration = try NSRegularExpression(
            pattern: #"^(?:(?:public|private|fileprivate|internal|final|nonisolated|@[A-Za-z]+)[ \t]+)*(?:func|let|var|struct|enum|class|actor|protocol|typealias)[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#,
            options: [.anchorsMatchLines])
        func matches(_ regex: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        }
        func group(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }

        struct Reading {
            let path: String
            let raw: String
            let classes: [String]
            /// One of the five calls: what makes a file with no class a rig.
            let hasOrderingWord: Bool
            /// One of the nine: a mark of its own, beside naming a rig and
            /// naming a member of a class so marked.
            let hasWindowWord: Bool
        }
        var readings: [Reading] = []
        for file in try SwiftSource.code(under: "Tests") {
            let classes = matches(classLine, in: file.text).compactMap { group(3, of: $0, in: file.text) }
            let raw = try RepoSource.text(of: file.path)
            readings.append(Reading(path: file.path, raw: raw, classes: classes,
                                    hasOrderingWord: !matches(orderingWord, in: raw).isEmpty,
                                    hasWindowWord: !matches(windowWord, in: raw).isEmpty))
        }

        var rigNames: Set<String> = []
        for rig in readings where rig.hasOrderingWord && rig.classes.isEmpty {
            for match in matches(declaration, in: rig.raw) {
                if let name = group(1, of: match, in: rig.raw) { rigNames.insert(name) }
            }
        }
        let rigUse = rigNames.isEmpty ? nil : try NSRegularExpression(
            pattern: #"\b(?:"# + rigNames.sorted().map(NSRegularExpression.escapedPattern(for:))
                .joined(separator: "|") + #")\b"#)

        func usesRig(_ reading: Reading) -> Bool {
            rigUse.map { !matches($0, in: reading.raw).isEmpty } ?? false
        }
        var seeds: [String] = []
        for reading in readings where reading.hasWindowWord || usesRig(reading) {
            seeds += reading.classes
        }
        let memberOfASeed = seeds.isEmpty ? nil : try NSRegularExpression(
            pattern: #"(^|[^A-Za-z0-9_])("# + Set(seeds).sorted().map(NSRegularExpression.escapedPattern(for:))
                .joined(separator: "|") + #")\.[A-Za-z_]"#,
            options: [.anchorsMatchLines])

        var families: [String: Family] = [:]
        for reading in readings where !reading.classes.isEmpty {
            let parts = reading.path.split(separator: "/").map(String.init)
            var place = "", target = ""
            if parts.count >= 5, parts[0] == "Tests", parts[1] == "Modules" {
                place = parts[2]
                target = "Module_\(parts[2])_\(parts[3])"
            } else if parts.count >= 3, parts[0] == "Tests", parts[1] != "Modules" {
                place = parts[1]
                target = parts[1]
            } else {
                throw SetupFailure(description: "\(reading.path) holds a test class and lies in no target's directory")
            }
            let namesAMember = memberOfASeed.map { !matches($0, in: reading.raw).isEmpty } ?? false
            for name in reading.classes {
                let family = Family(target: target, name: name, place: place,
                                    hasWindowWord: reading.hasWindowWord, usesWindowRig: usesRig(reading),
                                    namesAWindowMember: namesAMember,
                                    readsTheDocuments: reading.raw.contains(documentsWord))
                families[family.address] = family
            }
        }
        return Census(families: families)
    }

    /// The census, or a failure that says the reader read nothing.
    private func censusOrFail(file: StaticString = #filePath, line: UInt = #line) throws -> Census? {
        let census = try Self.census.get()
        guard census.families.count >= Self.censusFloor else {
            XCTFail("the census read \(census.families.count) classes under Tests/ \u{2014} the reader read nothing",
                    file: file, line: line)
            return nil
        }
        return census
    }

    /// Names for a failure message, as many as one line can carry.
    private static func listed(_ names: [String], limit: Int = 8) -> String {
        let shown = names.sorted().prefix(limit).joined(separator: ", ")
        return names.count > limit ? "\(shown) and \(names.count - limit) more" : shown
    }

    private static let tierRanNothing = "!! tier family(ies) ran no test case: "

    /// The line a refusal before the run ends on, the same whatever it refused.
    private static let refusedLastLine =
        "==> FAIL (runner exit=1, swift test exit=not run)  failure-lines=0  selected=0  skipped=0  log=not written"

    /// The `--filter` values among arguments, in either spelling.
    private static func filterValues(in arguments: [String]) -> [String] {
        var found: [String] = []
        for (index, argument) in arguments.enumerated() {
            if argument == "--filter" {
                found.append(index + 1 < arguments.count ? arguments[index + 1] : "")
            } else if argument.hasPrefix("--filter=") {
                found.append(String(argument.dropFirst("--filter=".count)))
            }
        }
        return found
    }

    /// One passing case of a family, by its address.
    private static func oneCase(_ address: String) -> Case {
        let parts = address.components(separatedBy: ".")
        return Case(target: parts[0], type: parts.dropFirst().joined(separator: "."), method: "testOne")
    }

    /// What the runner handed `swift` for one tier.
    private struct Expansion {
        let run: Run
        /// The alternatives of the one `--filter`, as handed.
        let alternatives: [String]
        /// `Target.Class` of each alternative that has the shape `Target\.Class/`.
        let addresses: [String]
        /// The alternatives that do not have it.
        let malformed: [String]
        /// The tier's own line on standard output, before the run.
        let announcement: String?
    }

    /// Starts the runner with `--tier <name>` over a stub and reads what the
    /// stub was given. Every way the subject can be wholly absent fails here
    /// in words of its own: `swift` never ran, it was handed `--tier`, no
    /// `--filter` reached it, the tier handed it nothing, the tier did not say
    /// how many families it holds.
    private func expand(_ tier: String, file: StaticString = #filePath, line: UInt = #line) throws -> Expansion? {
        let run = try runner(Setup(arguments: ["--tier", tier], swiftPrints: Self.sequentialLog([Self.removable[0]])))
        guard let started = run.swiftArguments else {
            XCTFail("swift never ran for --tier \(tier); \(run.said)", file: file, line: line)
            return nil
        }
        if started.contains(where: { $0 == "--tier" || $0.hasPrefix("--tier=") }) {
            XCTFail("swift was started with --tier (arguments: \(started.dropFirst().joined(separator: " "))); \(run.said)",
                    file: file, line: line)
            return nil
        }
        let filters = Self.filterValues(in: started)
        guard filters.count == 1 else {
            XCTFail(filters.isEmpty ? "no --filter reached swift for --tier \(tier); \(run.said)"
                                    : "\(filters.count) --filter arguments reached swift for --tier \(tier), one is the rule; \(run.said)",
                    file: file, line: line)
            return nil
        }
        let shape = try NSRegularExpression(pattern: #"^([A-Za-z0-9_]+)\\\.([A-Za-z0-9_]+)/$"#)
        var addresses: [String] = [], malformed: [String] = []
        let alternatives = filters[0].components(separatedBy: "|")
        for alternative in alternatives {
            if let match = shape.firstMatch(in: alternative, range: NSRange(alternative.startIndex..., in: alternative)),
               let target = Range(match.range(at: 1), in: alternative),
               let name = Range(match.range(at: 2), in: alternative) {
                addresses.append("\(alternative[target]).\(alternative[name])")
            } else {
                malformed.append(alternative)
            }
        }
        XCTAssertFalse(addresses.isEmpty, "tier \(tier) handed swift 0 names; \(run.said)", file: file, line: line)

        let prefix = "==> tier '\(tier)': "
        let announced = run.stdout.first { $0.hasPrefix(prefix) }
        if let announced {
            let rest = announced.dropFirst(prefix.count)
            let digits = rest.prefix { $0.isNumber }
            let leftOut = announced.contains("left to --tier windows")
            if let count = Int(digits), rest.dropFirst(digits.count).hasPrefix(" famil") {
                XCTAssertTrue(leftOut ? count >= addresses.count : count == addresses.count,
                              "tier \(tier) says [\(announced)] and handed swift \(addresses.count) names; \(run.said)",
                              file: file, line: line)
            } else {
                XCTFail("tier \(tier) says [\(announced)], not \"==> tier '<name>': <N> families\" (\"1 family\" for one); \(run.said)",
                        file: file, line: line)
            }
        } else {
            XCTFail("tier \(tier) did not say, before the run, \"==> tier '\(tier)': <N> families\" (\"1 family\" for one); \(run.said)",
                    file: file, line: line)
        }
        return Expansion(run: run, alternatives: alternatives, addresses: addresses,
                         malformed: malformed, announcement: announced)
    }

    /// What a row asks of a tier's run: a verdict with the expected word and
    /// status, the status the line names, and a `swift` that exited 0. The
    /// arguments `swift` got are the row's own business, since a tier is
    /// rewritten into a `--filter` before it gets there.
    @discardableResult
    private func assertJudgedTier(_ run: Run, _ word: String, exit status: Int32,
                                  file: StaticString = #filePath, line: UInt = #line) -> Verdict? {
        guard let verdict = judgement(of: run, file: file, line: line) else { return nil }
        XCTAssertEqual(verdict.word, word, "the last line's word; \(run.said)", file: file, line: line)
        XCTAssertEqual(run.status, status, "the runner's exit status; \(run.said)", file: file, line: line)
        XCTAssertEqual(verdict.runnerExit, String(run.status),
                       "the last line names a status the runner did not exit with; \(run.said)", file: file, line: line)
        XCTAssertEqual(verdict.swiftExit, "0", "the status the last line reports for swift; \(run.said)",
                       file: file, line: line)
        return verdict
    }

    /// A tier expands into the families it names, and the runner holds the
    /// run to them: a family none of whose cases started fails the run and is
    /// named on a line of its own. Two tiers are taken, one of them
    /// hand-listed and one of them a whole target.
    func testATierRunsItsFamiliesAndOneThatRanNothingFailsTheRun() throws {
        for tier in ["strings", "HelmContractTests"] {
            // Start 1: what the runner expands the tier into.
            guard let found = try expand(tier) else { continue }
            let families = found.addresses
            guard families.count > 1, let last = families.last else {
                XCTFail("tier \(tier) handed swift \(families.count) names, too few to leave one out")
                continue
            }

            // Start 2: every family has a case that started.
            let all = try runner(Setup(arguments: ["--tier", tier],
                                       swiftPrints: Self.sequentialLog(families.map(Self.oneCase))))
            if let verdict = assertJudgedTier(all, "PASS", exit: 0) {
                XCTAssertEqual(verdict.value("selected"), String(families.count),
                               "tier \(tier): one case a family; \(all.said)")
                XCTAssertEqual(verdict.value("skipped"), "0", "tier \(tier): the cases that were skipped; \(all.said)")
            }
            assertSilent(all)
            let again = Self.filterValues(in: all.swiftArguments ?? [])
            XCTAssertEqual(again, [found.alternatives.joined(separator: "|")],
                           "tier \(tier) expanded into another filter the second time; \(all.said)")
            XCTAssertFalse((all.swiftArguments ?? []).contains { $0 == "--tier" || $0.hasPrefix("--tier=") },
                           "swift was started with --tier; \(all.said)")

            // Start 3: the last family has no case in the log.
            let short = try runner(Setup(arguments: ["--tier", tier],
                                         swiftPrints: Self.sequentialLog(families.dropLast().map(Self.oneCase))))
            if let verdict = assertJudgedTier(short, "FAIL", exit: 1) {
                XCTAssertEqual(verdict.value("selected"), String(families.count - 1),
                               "tier \(tier): the cases that started; \(short.said)")
            }
            XCTAssertEqual(names(after: Self.tierRanNothing, in: short), [last],
                           "tier \(tier): the !! line that names the family that ran nothing; \(short.said)")
            XCTAssertNil(names(after: Self.ranNothing, in: short),
                         "tier \(tier): a tier family is not a filter alternative; \(short.said)")

            // A family whose only case was skipped did run.
            var skipping = families.map(Self.oneCase)
            skipping[skipping.count - 1] = skipping[skipping.count - 1].ended(.skipped)
            let skipped = try runner(Setup(arguments: ["--tier", tier], swiftPrints: Self.sequentialLog(skipping)))
            if let verdict = assertJudgedTier(skipped, "PASS", exit: 0) {
                XCTAssertEqual(verdict.value("skipped"), "1", "tier \(tier): the one case that was skipped; \(skipped.said)")
                XCTAssertEqual(verdict.value("selected"), String(families.count),
                               "tier \(tier): the cases that started; \(skipped.said)")
            }
            XCTAssertNil(names(after: Self.tierRanNothing, in: skipped),
                         "tier \(tier): a family with a skipped case is named as one that ran nothing; \(skipped.said)")
        }
    }

    /// A tier that is not a directory of `Tests/` or of `Tests/Modules/`, or
    /// one of the three laid over them, is refused before anything runs. The
    /// name is compared as the exact string: the volume is case-insensitive,
    /// so `disk` finds the folder of `Disk`, and two of the folders named
    /// here hold no test class of their own.
    func testAnUnknownTierIsRefusedBeforeSwiftRuns() throws {
        let refused: [(arguments: [String], name: String)] = [
            (["--tier", "NoSuchTier"], "NoSuchTier"),
            (["--tier=NoSuchTier"], "NoSuchTier"),
            (["--tier", "Support"], "Support"),
            (["--tier", "Modules"], "Modules"),
            (["--tier", "disk"], "disk"),
            (["--tier", "Modules/Disk"], "Modules/Disk"),
            (["--tier"], ""),
            (["--tier", ""], ""),
        ]
        for (arguments, name) in refused {
            let run = try runner(Setup(arguments: arguments, swiftPrints: Self.sequentialLog(Self.removable)))
            if let started = run.swiftArguments {
                XCTFail("swift ran with [\(started.dropFirst().joined(separator: ", "))] after \(arguments); \(run.said)")
            }
            XCTAssertEqual(run.lastLine, Self.refusedLastLine, "\(arguments): the last line of a refusal; \(run.said)")
            XCTAssertEqual(run.status, 1, "\(arguments): the runner's exit status; \(run.said)")
            assertComplains(run, "!! unknown tier '\(name)'")
        }

        // The control: a tier that exists starts swift, and is not refused.
        let known = try runner(Setup(arguments: ["--tier", "strings"], swiftPrints: Self.sequentialLog(Self.removable)))
        XCTAssertNotNil(known.swiftArguments, "swift never ran for a tier that exists; \(known.said)")
        XCTAssertNotEqual(known.lastLine, Self.refusedLastLine, "a tier that exists was refused; \(known.said)")
        XCTAssertFalse(known.complaints.contains { $0.hasPrefix("!! unknown tier") },
                       "a tier that exists was called unknown; \(known.said)")
    }

    /// A tier is looked up in a list of the tiers joined by newlines, so the
    /// names of two neighbouring tiers with a newline between them pass for
    /// one name that is in the list. A `--tier` value carrying a newline is
    /// refused whole, as a `--filter` one is, before the tree is read and
    /// before `swift` could start: in the `--tier X` form, in the `--tier=X`
    /// form, and as the second of two tiers whose first is good. The control
    /// asks for the same two tiers one at a time, so the lookup alone would
    /// have let the value through and `swift` starts.
    func testANewlineInATierValueIsRefusedBeforeSwiftRuns() throws {
        let joined = "Disk\nHosts"
        let refusal = "!! --tier value contains a newline byte, refused before swift test runs: $'Disk\\nHosts'"
        for arguments in [["--tier", joined], ["--tier=\(joined)"], ["--tier", "strings", "--tier", joined]] {
            let run = try runner(Setup(arguments: arguments, swiftPrints: Self.sequentialLog(Self.removable)))
            if let verdict = assertJudged(run, "FAIL", exit: 1, swiftRan: false) {
                XCTAssertEqual(verdict.value("log"), "not written", "\(arguments): where it says it left; \(run.said)")
            }
            XCTAssertEqual(run.lastLine, Self.refusedLastLine, "\(arguments): the last line of a refusal; \(run.said)")
            XCTAssertEqual(run.complaints, [refusal], "\(arguments): the !! lines of a refusal; \(run.said)")
        }

        let control = try runner(Setup(arguments: ["--tier", "Disk", "--tier", "Hosts"],
                                       swiftPrints: Self.sequentialLog(Self.removable)))
        XCTAssertNotNil(control.swiftArguments, "swift never ran for two tiers that exist; \(control.said)")
        XCTAssertFalse(control.complaints.contains { $0.hasPrefix("!! --tier value") || $0.hasPrefix("!! unknown tier") },
                       "two tiers that exist were refused as one with a newline or as unknown; \(control.said)")
    }

    /// A file of a `Tests/` of the child's own: one test class, with the
    /// given text in its one method.
    private static func classFile(_ name: String, saying body: String = "") -> [String: String] {
        ["HelmRuntimeTests/\(name).swift":
            "import XCTest\nfinal class \(name): XCTestCase {\n    func testOne() { \(body) }\n}\n"]
    }

    /// A tier that would hand `swift` nothing, or one family short of what it
    /// is listed to hold, is refused before anything runs. The tree today has
    /// no such tier, so each is made in a `Tests/` of the child's own, beside a
    /// copy of the runner. Where a refusal has a control it stands on the line
    /// after it: the other tier over the same tree, or the same tier with the
    /// class it lacked added, and that one starts `swift`.
    func testATierThatWouldBeEmptyOrShortIsRefusedBeforeSwiftRuns() throws {
        func refused(_ run: Run, _ beginning: String, _ what: String) {
            if let started = run.swiftArguments {
                XCTFail("\(what): swift ran with [\(started.dropFirst().joined(separator: ", "))]; \(run.said)")
            }
            XCTAssertEqual(run.lastLine, Self.refusedLastLine, "\(what): the last line of a refusal; \(run.said)")
            XCTAssertEqual(run.status, 1, "\(what): the runner's exit status; \(run.said)")
            assertComplains(run, beginning)
        }
        func started(_ run: Run, _ filter: String, _ what: String) {
            XCTAssertEqual(Self.filterValues(in: run.swiftArguments ?? []), [filter],
                           "\(what): the control did not start swift with the tier's family (nil: never started); \(run.said)")
            XCTAssertEqual(run.status, 0, "\(what): the control's exit status; \(run.said)")
        }
        /// `ran` are the families the stub reports a case for.
        func tier(_ name: String, over tree: [String: String], ran: [String] = []) throws -> Run {
            var setup = Setup(arguments: ["--tier", name], swiftPrints: Self.sequentialLog(ran.map(Self.oneCase)))
            setup.tree = tree
            return try runner(setup)
        }

        // Every class of the place orders a window, so nothing is left to run.
        let ordering = Self.classFile("AWindowTests", saying: "window." + "order" + "Front(nil)")
        refused(try tier("HelmRuntimeTests", over: ordering),
                "!! tier 'HelmRuntimeTests' holds no family to run; 1 that order a window are left to --tier windows",
                "a place whose only class orders a window")
        started(try tier("windows", over: ordering, ran: ["HelmRuntimeTests.AWindowTests"]),
                "HelmRuntimeTests\\.AWindowTests/", "windows over that tree")

        // No class orders a window, so `windows` is empty.
        let plain = Self.classFile("APlainTests")
        refused(try tier("windows", over: plain), "!! tier 'windows' holds no family to run",
                "windows over a tree with no window class")
        started(try tier("HelmRuntimeTests", over: plain, ran: ["HelmRuntimeTests.APlainTests"]),
                "HelmRuntimeTests\\.APlainTests/", "a place over that tree")

        // A class listed by hand that no file declares leaves its tier short.
        let docs = Self.classFile("ListsAgreeWithTheTreeTests")
        refused(try tier("docs", over: docs),
                "!! NoDocCommentIsDetachedTests is listed by hand for tier 'docs'", "docs short of one class")
        started(try tier("docs", over: docs.merging(Self.classFile("NoDocCommentIsDetachedTests")) { $1 },
                         ran: ["HelmRuntimeTests.ListsAgreeWithTheTreeTests", "HelmRuntimeTests.NoDocCommentIsDetachedTests"]),
                "HelmRuntimeTests\\.ListsAgreeWithTheTreeTests/|HelmRuntimeTests\\.NoDocCommentIsDetachedTests/",
                "docs with both classes")
        let strings = Self.classFile("PunctuationIsTerminologyTests")
            .merging(Self.classFile("StringsCoverageTests")) { $1 }
        refused(try tier("strings", over: strings),
                "!! NoOrphanTranslationsTests is listed by hand for tier 'strings'", "strings short of one class")

        // A tree with no class in it is no tree to expand a tier from.
        refused(try tier("HelmRuntimeTests", over: ["HelmRuntimeTests/Notes.swift": "import XCTest\n"]),
                "!! no test class found under ", "a tree with no test class")
    }

    /// Whatever a tier hands `swift` is a test class the tree has: the
    /// address has the shape `Target\.Class/`, the pair is in the census, a
    /// tier hands at least one, and none hands the same twice. The tiers are
    /// the census's own places and the three laid over them.
    func testEveryNameATierHandsSwiftIsATestClassUnderTests() throws {
        guard let census = try censusOrFail() else { return }
        for tier in census.places + Self.laidOverTiers {
            guard let found = try expand(tier) else { continue }
            XCTAssertEqual(found.malformed, [],
                           "tier \(tier) handed swift names that are not Target\\.Class/: \(Self.listed(found.malformed))")
            let unknown = found.addresses.filter { census.families[$0] == nil }
            XCTAssertEqual(unknown, [],
                           "tier \(tier) handed swift names that are no test class under Tests/: \(Self.listed(unknown))")
            XCTAssertEqual(Set(found.addresses).count, found.addresses.count,
                           "tier \(tier) handed swift a name twice; \(found.run.said)")
        }
    }

    /// The owner's row: every test class lies in the tier of its directory,
    /// or in `windows` when it orders a window, and nowhere else. A class is a
    /// window class here when its file holds one of the nine window words, or
    /// names what a rig declares, or names a member of a class so found (the
    /// class's name as a whole word, a dot, then a letter or an underscore),
    /// one step deep. The runner may hold more in `windows`, and asked is
    /// only that none of them is also a class of its directory's tier.
    func testEveryTestClassIsInExactlyTheTiersItsPlaceSays() throws {
        guard let census = try censusOrFail() else { return }
        var tiers: [String: Set<String>] = [:]
        var announcements: [String: String] = [:]
        for tier in census.places + Self.laidOverTiers {
            guard let found = try expand(tier) else { return }
            tiers[tier] = Set(found.addresses)
            announcements[tier] = found.announcement
        }
        let windows = tiers["windows"] ?? []

        var inBoth: [String] = [], inNone: [String] = []
        for (address, family) in census.families {
            let inPlace = tiers[family.place]?.contains(address) == true
            let inWindows = windows.contains(address)
            if inPlace && inWindows { inBoth.append(address) }
            if !inPlace && !inWindows { inNone.append(address) }
        }
        XCTAssertEqual(inNone, [],
                       "\(inNone.count) classes are in no tier: \(Self.listed(inNone))")
        XCTAssertEqual(inBoth, [],
                       "\(inBoth.count) classes lie in both their directory's tier and windows: \(Self.listed(inBoth))")

        for place in census.places {
            let foreign = (tiers[place] ?? []).filter { census.families[$0]?.place != place }
            XCTAssertEqual(foreign.sorted(), [],
                           "tier \(place) holds classes of another directory: \(Self.listed(Array(foreign)))")
        }

        let byWord = census.families.values.filter { $0.hasWindowWord && !windows.contains($0.address) }
        XCTAssertEqual(byWord.map(\.address), [],
                       "\(byWord.count) classes whose file holds one of the nine window words are not in windows: "
                       + Self.listed(byWord.map(\.address)))
        let byRig = census.families.values.filter { $0.usesWindowRig && !windows.contains($0.address) }
        XCTAssertEqual(byRig.map(\.address), [],
                       "\(byRig.count) classes whose file names what a window rig declares are not in windows: "
                       + Self.listed(byRig.map(\.address)))
        let byMember = census.families.values.filter { $0.namesAWindowMember && !windows.contains($0.address) }
        XCTAssertEqual(byMember.map(\.address), [],
                       "\(byMember.count) classes whose file names a member of a window class are not in windows: "
                       + Self.listed(byMember.map(\.address)))

        for (tier, addresses) in tiers.sorted(by: { $0.key < $1.key }) where tier != "windows" {
            let shared = addresses.intersection(windows)
            XCTAssertEqual(shared.sorted(), [],
                           "windows meets tier \(tier): \(Self.listed(Array(shared)))")
        }

        let unread = census.families.values.filter {
            $0.readsTheDocuments && tiers["docs"]?.contains($0.address) != true && !windows.contains($0.address)
        }
        XCTAssertEqual(unread.map(\.address), [],
                       "\(unread.count) classes whose file reads the standing documents are not in docs: "
                       + Self.listed(unread.map(\.address)))

        for place in census.places {
            let left = census.families.values.filter { $0.place == place && $0.ordersAWindow }
            if !left.isEmpty {
                XCTAssertTrue(announcements[place]?.contains("left to --tier windows") == true,
                              "tier \(place) leaves \(left.count) window classes out and does not say so: "
                              + Self.listed(left.map(\.address)))
            }
        }

        // This class is read by the rule it holds, so it is asked about by name.
        let own = String(reflecting: type(of: self))
        XCTAssertEqual(census.families[own]?.ordersAWindow, false,
                       "\(own) is a window class by its own file, or is not in the census: window words belong spelled in pieces, and no seed class is named with a dot behind it")
        XCTAssertTrue(tiers[census.families[own]?.place ?? ""]?.contains(own) == true,
                      "\(own) is not in the tier of its directory")
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
