// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport

/// The build-number gate at the top of `Scripts/package-app.sh`, run for real
/// against throwaway repositories, the way `AFailedCopyKeepsTheInstalledAppTests`
/// drives the swap script.
///
/// Most cases here are a history the gate must refuse *before* the compile: a
/// tree that answers the two git questions from somewhere other than itself
/// (a foreign `GIT_DIR`, an ancestor's `.git` reached by walking up, its own
/// `core.worktree` pointed elsewhere), or a history that reads shorter than
/// it is (shallow, grafted). The rest are controls that must build instead —
/// a healthy layout reached through a worktree, a symlink, another case of
/// its own spelling, or with a trace mechanism running alongside it — so a
/// fix that refuses too eagerly is caught here as surely as one that refuses
/// too little. A gate that wrongly let a bad case through would run a real
/// `swift build -c release` and then `rm -rf` under `$TMPDIR/helm-package` —
/// so the script is always given a stub `swift` that fails at once and a
/// `TMPDIR` confined to scratch, and a red run here costs a second and
/// touches nothing real.
final class TheBuildNumberGateRefusesTests: XCTestCase {

    private struct Run {
        let status: Int32
        let output: String
    }

    private struct SetupFailure: Error, CustomStringConvertible {
        let description: String
    }

    private var scriptPath: URL {
        RepoSource.root.appendingPathComponent("Scripts/package-app.sh")
    }

    // MARK: - Building the repositories the gate is asked to judge

    /// A throwaway identity so `git commit` never falls back to reading
    /// `~/.gitconfig`, which this suite does not control — and `GIT_AUTHOR_*`
    /// / `GIT_COMMITTER_*` alone do not make that true: a real `~/.gitconfig`
    /// on the machine running this suite can still name `core.hooksPath` or
    /// set `commit.gpgsign = true`, and either turns `git commit` here into a
    /// call to a real hook or a real signer (measured elsewhere: `commit`
    /// exiting 128 for exactly this reason). `GIT_CONFIG_GLOBAL=/dev/null`
    /// and `GIT_CONFIG_NOSYSTEM=1` are what actually close that off, by
    /// pointing the global config at a file with nothing in it and refusing
    /// the system one outright.
    private func git(_ args: [String], in dir: URL, env extra: [String: String] = [:]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = args
        proc.currentDirectoryURL = dir
        var environment = [
            "PATH": "/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Helm Test", "GIT_AUTHOR_EMAIL": "test@helm.invalid",
            "GIT_COMMITTER_NAME": "Helm Test", "GIT_COMMITTER_EMAIL": "test@helm.invalid",
        ]
        for (key, value) in extra { environment[key] = value }
        proc.environment = environment
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw SetupFailure(description: "git \(args.joined(separator: " ")) failed "
                               + "(\(proc.terminationStatus)): \(output)")
        }
        return output
    }

    /// A repository with `count` commits on its only branch, one byte of
    /// filler changing each time so every commit is really new.
    private func repoWithCommits(_ count: Int, label: String) throws -> URL {
        let dir = scratchDirectory(label)
        try git(["init", "-q"], in: dir)
        for i in 1...count {
            try write("f.txt", in: dir, bytes: 4, filler: UInt8(i % 256))
            try git(["add", "f.txt"], in: dir)
            try git(["commit", "-q", "-m", "c\(i)"], in: dir)
        }
        return dir
    }

    // MARK: - Running the real script

    /// Copies the real script under `repo/Scripts/`, so `SCRIPT_DIR/..`
    /// resolves to `repo` exactly as it does in the tree, then runs it with a
    /// `swift` that refuses instantly and a `TMPDIR` inside scratch — so a
    /// gate that wrongly passes fails fast rather than building or deleting
    /// anything real.
    private func run(in repo: URL, extraEnv: [String: String] = [:]) throws -> Run {
        let scriptsDir = repo.appendingPathComponent("Scripts")
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        let copy = scriptsDir.appendingPathComponent("package-app.sh")
        try FileManager.default.copyItem(at: scriptPath, to: copy)

        let stubBin = scratchDirectory("gate-stub-swift")
        let stubSwift = stubBin.appendingPathComponent("swift")
        try """
            #!/bin/bash
            echo 'STUB SWIFT — the gate should never have let this run' >&2
            exit 17
            """.write(to: stubSwift, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stubSwift.path)

        let tmp = scratchDirectory("gate-tmpdir")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [copy.path]
        // GIT_CONFIG_GLOBAL/GIT_CONFIG_NOSYSTEM here for the same reason as
        // in `git(_:in:env:)` above: the script under test makes five git
        // calls of its own, and without these a real ~/.gitconfig on the
        // machine running this suite can steer any of them.
        var environment = [
            "PATH": "\(stubBin.path):/usr/bin:/bin",
            "TMPDIR": tmp.path,
            "HOME": NSHomeDirectory(),
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
        ]
        for (key, value) in extraEnv { environment[key] = value }
        proc.environment = environment
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        // Read before the wait: the refusal messages are short, but a pipe
        // nobody drains is how a test of a child process hangs for ever.
        let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        proc.waitUntilExit()
        return Run(status: proc.terminationStatus, output: output)
    }

    private func lineCount(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: "\n").filter { $0.contains(needle) }.count
    }

    /// The two facts every case below asserts: the gate refused (a status
    /// and a refusal line are both the subject having happened, not only its
    /// absence), and the compile it guards never started.
    private func assertRefused(_ result: Run, because why: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(result.status, 0, "\(why), but the gate exited 0: \(result.output)",
                          file: file, line: line)
        XCTAssertEqual(lineCount("!! Build number:", in: result.output), 1,
                       "\(why), but no refusal line was printed: \(result.output)",
                       file: file, line: line)
        XCTAssertEqual(lineCount("==> Building release binary", in: result.output), 0,
                       "\(why), but the gate let the build start anyway: \(result.output)",
                       file: file, line: line)
    }

    /// The mirror of `assertRefused` for a layout the gate must let through:
    /// the compile started, the stub that stands in for `swift` is the thing
    /// that actually stopped it (never a refusal line), and the number
    /// printed before the compile is the repository's true count.
    private func assertBuilt(_ result: Run, trueCount: String, because why: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lineCount("!! Build number:", in: result.output), 0,
                       "\(why), but the gate refused: \(result.output)", file: file, line: line)
        XCTAssertEqual(lineCount("==> Build number: \(trueCount)", in: result.output), 1,
                       "\(why), but the announced count does not match the true count "
                       + "\(trueCount): \(result.output)", file: file, line: line)
        XCTAssertEqual(lineCount("==> Building release binary", in: result.output), 1,
                       "\(why), but the gate never reached the compile: \(result.output)",
                       file: file, line: line)
        XCTAssertEqual(lineCount("STUB SWIFT — the gate should never have let this run", in: result.output), 1,
                       "\(why), but the stub's own marker line is missing, "
                       + "so the compile it stands in for may not have run: \(result.output)",
                       file: file, line: line)
    }

    /// Flips the stored first-parent pointer of `commitHex` inside `repo`'s
    /// commit-graph cache to git's own "no parent" sentinel (`0x70000000`,
    /// `gitformat-commit-graph`'s Commit Data chunk) — the same tamper
    /// measured by hand against this gate (a true count of 10 read back as
    /// 6, the same figure the script's own comment above `BUILD_NO` cites),
    /// built here so the case can be red against the mutant and green after
    /// without a binary fixture checked into the tree.
    private func forgeCommitGraphDroppingParent(of commitHex: String, in repo: URL) throws {
        let path = repo.appendingPathComponent(".git/objects/info/commit-graph")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path.path)
        var bytes = [UInt8](try Data(contentsOf: path))
        func be64(_ offset: Int) -> Int {
            var value: UInt64 = 0
            for i in 0..<8 { value = (value << 8) | UInt64(bytes[offset + i]) }
            return Int(value)
        }
        guard bytes[5] == 1 else {
            throw SetupFailure(description: "commit-graph hash version \(bytes[5]), this forge only knows SHA-1 (1)")
        }
        let hashLength = 20
        let numChunks = Int(bytes[6])
        var chunkOffset: [String: Int] = [:]
        var tableOffset = 8
        for _ in 0...numChunks {
            let id = String(decoding: bytes[tableOffset..<(tableOffset + 4)], as: UTF8.self)
            chunkOffset[id] = be64(tableOffset + 4)
            tableOffset += 12
        }
        guard let oidlOffset = chunkOffset["OIDL"], let cdatOffset = chunkOffset["CDAT"] else {
            throw SetupFailure(description: "commit-graph has no OIDL/CDAT chunk to forge")
        }
        var targetIndex: Int?
        let hexChars = Array(commitHex)
        let target = stride(from: 0, to: hexChars.count, by: 2).map {
            UInt8(String(hexChars[$0...($0 + 1)]), radix: 16) ?? 0
        }
        var i = 0
        while oidlOffset + (i + 1) * hashLength <= cdatOffset {
            let start = oidlOffset + i * hashLength
            if Array(bytes[start..<(start + hashLength)]) == target { targetIndex = i; break }
            i += 1
        }
        guard let idx = targetIndex else {
            throw SetupFailure(description: "commit \(commitHex) is not in this commit-graph's OIDL")
        }
        let parent1Offset = cdatOffset + idx * (hashLength + 16) + hashLength
        bytes[parent1Offset] = 0x70; bytes[parent1Offset + 1] = 0
        bytes[parent1Offset + 2] = 0; bytes[parent1Offset + 3] = 0
        try Data(bytes).write(to: path)
    }

    // MARK: - Cases

    func testATreeWithNoGitHistoryAtAllRefuses() throws {
        let repo = scratchDirectory("gate-no-history")
        try write("f.txt", in: repo)
        let result = try run(in: repo)
        assertRefused(result, because: "an unpacked archive has no .git anywhere above it")
        // This case pins that the refusal quotes what git actually said
        // rather than guessing a cause ("no .git anywhere above it either"
        // used to be printed here whatever git's own reason was, including
        // dubious ownership and a permission denial).
        XCTAssertTrue(result.output.contains("git said:"),
                      "the refusal must quote git's own standard error: \(result.output)")
        XCTAssertFalse(result.output.contains("no .git anywhere above it either"),
                       "the refusal must not claim a cause it has not established: \(result.output)")
    }

    func testAShallowCloneRefuses() throws {
        let source = try repoWithCommits(10, label: "gate-shallow-source")
        let clone = scratchDirectory("gate-shallow-clone")
        try git(["clone", "-q", "--depth", "3", "file://\(source.path)", clone.path], in: source)
        let result = try run(in: clone)
        assertRefused(result, because: "a shallow clone counts only the commits it fetched")
    }

    /// `GIT_TRACE=1` writes to standard error, which the gate never reads —
    /// this pins that the shallow refusal survives a trace running alongside
    /// it. `GIT_TRACE=/dev/stdout` is no longer a separate, unverified case:
    /// every `GIT_TRACE*` name is unset before the gate's first git call, so
    /// it behaves exactly like `GIT_TRACE=1` here too, verified directly by
    /// `testAHealthyRepositorySurvivesGitTraceToStandardOut` below rather
    /// than only asserted by hand.
    func testAShallowCloneRefusesWithATraceRunning() throws {
        let source = try repoWithCommits(10, label: "gate-shallow-trace-source")
        let clone = scratchDirectory("gate-shallow-trace-clone")
        try git(["clone", "-q", "--depth", "3", "file://\(source.path)", clone.path], in: source)
        let result = try run(in: clone, extraEnv: ["GIT_TRACE": "1"])
        assertRefused(result, because: "a shallow clone must refuse whether or not GIT_TRACE is set")
    }

    func testARepositoryWithNoCommitsRefuses() throws {
        let repo = scratchDirectory("gate-no-commits")
        try git(["init", "-q"], in: repo)
        let result = try run(in: repo)
        assertRefused(result, because: "a fresh `git init` over sources has no HEAD to count")
        // Same as testATreeWithNoGitHistoryAtAllRefuses above: no guessed
        // cause survives in the message.
        XCTAssertTrue(result.output.contains("git said:"),
                      "the refusal must quote git's own standard error: \(result.output)")
        XCTAssertFalse(result.output.contains("no HEAD to count"),
                       "the refusal must not claim a cause it has not established: \(result.output)")
    }

    func testATreeNestedInsideAnotherRepositoryRefuses() throws {
        let outer = try repoWithCommits(3, label: "gate-nested-outer")
        let inner = outer.appendingPathComponent("inner/sub")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let result = try run(in: inner)
        assertRefused(result, because: "inner/sub has no .git of its own, only an ancestor's")
    }

    func testAForeignGitDirRefuses() throws {
        let victim = try repoWithCommits(5, label: "gate-gitdir-victim")
        let target = scratchDirectory("gate-gitdir-target")
        let result = try run(in: target, extraEnv: ["GIT_DIR": victim.appendingPathComponent(".git").path])
        assertRefused(result, because: "GIT_DIR named a repository other than the checkout being packaged")
    }

    func testAGraftedHistoryRefuses() throws {
        let repo = try repoWithCommits(10, label: "gate-graft")
        try git(["replace", "--graft", "HEAD~5"], in: repo)
        let result = try run(in: repo)
        assertRefused(result, because: "a replacement ref can give a commit a shorter parent chain")
    }

    /// The older mechanism `--no-replace-objects` does not reach: `info/grafts`,
    /// refused on the same finding as the replacement-ref case above —
    /// present (the script's own words for this check).
    func testAnOldStyleGraftsFileRefuses() throws {
        let repo = try repoWithCommits(10, label: "gate-grafts-file")
        let ancestor = try git(["rev-parse", "HEAD~5"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try ancestor.write(to: repo.appendingPathComponent(".git/info/grafts"),
                           atomically: true, encoding: .utf8)
        let result = try run(in: repo)
        assertRefused(result, because: "info/grafts can shorten a commit's parent chain "
                      + "and --no-replace-objects does not disable it")
    }

    /// A forged commit-graph shortens `rev-list --count HEAD`'s answer the
    /// same way a graft does (measured: a true count of 10 read back as 6),
    /// but it is neutralised at the count itself (`-c core.commitGraph=false`)
    /// rather than refused outright, so the healthy outcome here is a build
    /// announcing the true count — a refusal is accepted too, since nothing
    /// requires the gate to prefer one over the other, but silently
    /// undercounting is what this pins against.
    func testAForgedCommitGraphDoesNotUndercount() throws {
        let repo = try repoWithCommits(10, label: "gate-forged-commit-graph")
        let trueCount = try git(["rev-list", "--count", "HEAD"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ancestor = try git(["rev-parse", "HEAD~5"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try git(["commit-graph", "write", "--reachable"], in: repo)
        try forgeCommitGraphDroppingParent(of: ancestor, in: repo)
        let result = try run(in: repo)
        // Never `result.status == 0`: the stub `swift` itself exits 17 on the
        // path that reaches the compile, so a successful pass through the
        // gate is a *nonzero* status here — the refusal line is what tells
        // the two outcomes apart.
        if lineCount("!! Build number:", in: result.output) == 0 {
            assertBuilt(result, trueCount: trueCount,
                       because: "a forged commit-graph must not undercount if the gate lets the build through")
        } else {
            assertRefused(result, because: "a forged commit-graph can shorten a commit's parent chain")
        }
    }

    // MARK: - Cases: an ancestor's config, not its own .git, answering for a tree

    /// `core.worktree` in an ancestor's config can make `rev-parse
    /// --show-toplevel` answer with a path that has no `.git` of its own at
    /// all — the top-level comparison alone reads that as "this checkout's
    /// own top level" (measured: an ancestor 30 commits deep, `inner/sub`
    /// with no `.git`, `show-toplevel` from `inner/sub` answers `inner/sub`).
    func testAnAncestorsCoreWorktreeCannotStandInForOurOwnGit() throws {
        let ancestor = try repoWithCommits(30, label: "gate-worktree-config-ancestor")
        let inner = ancestor.appendingPathComponent("inner/sub")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        _ = try git(["config", "core.worktree", inner.path], in: ancestor)
        let result = try run(in: inner)
        assertRefused(result, because: "inner/sub has no .git of its own even though an ancestor's "
                      + "core.worktree makes rev-parse --show-toplevel answer inner/sub")
    }

    /// An empty directory named `.git` is not a working repository on its
    /// own, and plain discovery does not stop there either — it keeps
    /// walking up and answers from the ancestor instead (measured against
    /// the unpinned gate: EXIT=17, `==> Build number: 30`, the ancestor's
    /// own count rather than a refusal); the `--git-dir` pin refuses
    /// outright on exactly this case instead (the script's own comment
    /// above `GIT_DIR_ARG` names an empty directory named `.git` among the
    /// four layouts it tested).
    func testAnAncestorsCoreWorktreeCannotStandInForOurOwnGitEvenWithAHollowDotGit() throws {
        let ancestor = try repoWithCommits(30, label: "gate-worktree-hollow-ancestor")
        let inner = ancestor.appendingPathComponent("inner/sub")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        _ = try git(["config", "core.worktree", inner.path], in: ancestor)
        try FileManager.default.createDirectory(at: inner.appendingPathComponent(".git"),
                                                withIntermediateDirectories: true)
        let result = try run(in: inner)
        assertRefused(result, because: "inner/sub/.git exists but is empty, and an ancestor's "
                      + "core.worktree must not be allowed to answer for it")
    }

    /// The repository's *own* `core.worktree`, not an ancestor's — the case
    /// the two tests above do not reach: `inner/sub` here has a real `.git`
    /// of its own, so the pin resolves it directly rather than walking up,
    /// and it is that own config which sends `--show-toplevel` to a
    /// different, existing directory. Caught only by the `-ef` comparison at
    /// the bottom of the toplevel block — asserted here by that line's own
    /// text ("is not the same directory as"), because a mutant that skips
    /// the `-ef` check entirely (`if false; then` in place of the real
    /// condition) still refuses both cases above at the earlier `--git-dir`
    /// pin and would otherwise read as green against this file.
    func testOwnCoreWorktreePointingElsewhereRefusesAtTheEfComparison() throws {
        let repo = try repoWithCommits(3, label: "gate-ownwt-repo")
        let elsewhere = scratchDirectory("gate-ownwt-elsewhere")
        _ = try git(["config", "core.worktree", elsewhere.path], in: repo)
        let result = try run(in: repo)
        assertRefused(result, because: "the repository's own core.worktree names a directory other "
                      + "than the checkout itself, which only the -ef comparison catches")
        XCTAssertTrue(result.output.contains("is not the same directory as"),
                      "the refusal must be the -ef comparison's own line, not an earlier one: \(result.output)")
    }

    // MARK: - Cases: GIT_DIR/GIT_WORK_TREE set but not caught by the -n test

    /// The environment message names both variables and quotes "is set in
    /// the environment" — a phrase no other refusal in the gate uses. The
    /// two cases below differ once this guard is set aside: `GIT_WORK_TREE`
    /// alone would still be refused further down, by the top-level compare
    /// (the script's own comment above the guard: the `--git-dir` pin does
    /// not stop it from steering `--show-toplevel`), so `assertRefused`
    /// alone cannot tell this guard from that check and only the second
    /// assertion below does — dropping the `GIT_WORK_TREE` half of the
    /// guard's condition still leaves that run refused, by the wrong line.
    /// An empty `GIT_DIR` is not caught further down at all: once
    /// `--git-dir` is on the command line, git ignores `GIT_DIR` entirely,
    /// empty or not (the same comment), so removing `${GIT_DIR+x}` for
    /// `${GIT_DIR:-}` lets it build straight through, which `assertRefused`
    /// alone already catches.
    private func assertRefusedByTheEnvironmentGuard(_ result: Run, because why: String,
                                                     file: StaticString = #filePath, line: UInt = #line) {
        assertRefused(result, because: why, file: file, line: line)
        XCTAssertTrue(result.output.contains("is set in the environment, which would steer every git call below"),
                      "\(why), but the refusal that fired was not the environment guard's own line: "
                      + "\(result.output)", file: file, line: line)
    }

    func testGitWorkTreeAloneRefuses() throws {
        let repo = try repoWithCommits(3, label: "gate-worktree-alone")
        let result = try run(in: repo, extraEnv: ["GIT_WORK_TREE": "/tmp"])
        assertRefusedByTheEnvironmentGuard(result, because: "GIT_WORK_TREE alone still resolves a work tree "
                      + "wherever -C points, which the top-level check cannot be relied on to catch")
    }

    /// `GIT_DIR=` with nothing after the `=` is still set (`${GIT_DIR+x}`
    /// reads it as set; `${GIT_DIR:-}` would not). Once `--git-dir` is on
    /// the command line further down, git ignores `GIT_DIR` entirely,
    /// empty or not, so nothing downstream catches this either — this guard
    /// is the only refusal an empty `GIT_DIR` gets, and the `-n` test the
    /// gate used to use read it as absent on top of that.
    func testAnEmptyGitDirRefusesEvenThoughItIsSetToNothing() throws {
        let repo = try repoWithCommits(3, label: "gate-empty-gitdir")
        let result = try run(in: repo, extraEnv: ["GIT_DIR": ""])
        assertRefusedByTheEnvironmentGuard(result, because: "GIT_DIR set to the empty string is still set")
    }

    // MARK: - Cases: a healthy layout must build, whatever else is true of the environment

    /// `GIT_TRACE=/dev/stdout` writes straight into the descriptor a value
    /// below is captured from, which used to turn a healthy repository into
    /// a refusal for the wrong reason ("printed more than one line" for
    /// `rev-parse --show-toplevel`, measured against the unfixed script).
    /// Every `GIT_TRACE*` name is unset before the gate's first git call now,
    /// so a healthy repository must build and announce its true count
    /// exactly as it would with no trace running at all — this is asserted
    /// unconditionally, not as one of two acceptable outcomes, because that
    /// is the one thing the fix guarantees.
    func testAHealthyRepositorySurvivesGitTraceToStandardOut() throws {
        let repo = try repoWithCommits(4, label: "gate-trace-healthy")
        let trueCount = try git(["rev-list", "--count", "HEAD"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try run(in: repo, extraEnv: ["GIT_TRACE": "/dev/stdout"])
        assertBuilt(result, trueCount: trueCount,
                   because: "GIT_TRACE=/dev/stdout must not turn a healthy repository into a false refusal")
    }

    /// The `run` helper's own `GIT_CONFIG_GLOBAL=/dev/null` (set so a real
    /// `~/.gitconfig` cannot steer the gate's five git calls) also happens to
    /// close the one route `export GIT_TRACE2=0 GIT_TRACE2_PERF=0
    /// GIT_TRACE2_EVENT=0` exists for: a `trace2.normalTarget` set in a
    /// config file rather than the environment. This case points
    /// `GIT_CONFIG_GLOBAL` at a file of its own instead, carrying only
    /// `[trace2] normalTarget = /dev/stdout` — no hooks, no signing, so the
    /// hermetic intent of the base setup stays — and the healthy repository
    /// underneath it must still build and announce its true count. Removing
    /// the export line makes trace2's own multi-line preamble land ahead of
    /// `rev-parse --show-toplevel`'s answer, which the toplevel block reads
    /// as "printed more than one line" and refuses on (measured).
    func testAHealthyRepositorySurvivesTrace2ConfiguredThroughGitConfigGlobal() throws {
        let repo = try repoWithCommits(4, label: "gate-trace2-config-healthy")
        let trueCount = try git(["rev-list", "--count", "HEAD"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let globalConfig = scratchDirectory("gate-trace2-config-global").appendingPathComponent("gitconfig")
        try "[trace2]\n\tnormalTarget = /dev/stdout\n".write(to: globalConfig, atomically: true, encoding: .utf8)
        let result = try run(in: repo, extraEnv: ["GIT_CONFIG_GLOBAL": globalConfig.path])
        assertBuilt(result, trueCount: trueCount,
                   because: "trace2.normalTarget set through GIT_CONFIG_GLOBAL must not turn a healthy "
                   + "repository into a false refusal")
    }

    /// The mirror case on the refusal side: a repository with no commits,
    /// `trace2.normalTarget = /dev/stderr` this time, so the trace lines land
    /// on the same descriptor the gate quotes back in its own refusal
    /// (`git said: ...`). Without the export line, `rev-list --count HEAD`'s
    /// standard error is trace2's own multi-line preamble followed by git's
    /// `fatal:` line rather than the `fatal:` line alone (measured: the
    /// quoted text then contains an `elapsed:` line trace2 alone prints).
    func testANoCommitsRefusalWithTrace2ToStandardErrorCarriesNoTraceLine() throws {
        let repo = scratchDirectory("gate-trace2-config-nocommits")
        try git(["init", "-q"], in: repo)
        let globalConfig = scratchDirectory("gate-trace2-config-nocommits-global").appendingPathComponent("gitconfig")
        try "[trace2]\n\tnormalTarget = /dev/stderr\n".write(to: globalConfig, atomically: true, encoding: .utf8)
        let result = try run(in: repo, extraEnv: ["GIT_CONFIG_GLOBAL": globalConfig.path])
        assertRefused(result, because: "a fresh `git init` over sources has no HEAD to count, "
                      + "trace2 routed to standard error or not")
        XCTAssertTrue(result.output.contains("git said:"),
                      "the refusal must quote git's own standard error: \(result.output)")
        XCTAssertFalse(result.output.contains("elapsed:"),
                       "no trace2 line (its own \"elapsed:\" marker) may appear anywhere in the output: "
                       + "\(result.output)")
    }

    func testAPlainRepositoryBuildsAndAnnouncesTheTrueCount() throws {
        let repo = try repoWithCommits(4, label: "gate-control-plain")
        let trueCount = try git(["rev-list", "--count", "HEAD"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try run(in: repo)
        assertBuilt(result, trueCount: trueCount, because: "a plain healthy repository must build")
    }

    func testAWorktreeOfAHealthyRepositoryBuildsAndAnnouncesTheTrueCount() throws {
        let main = try repoWithCommits(5, label: "gate-control-worktree-main")
        let worktree = scratchDirectory("gate-control-worktree-extra")
        _ = try git(["worktree", "add", "-q", "-b", "gate-control-branch", worktree.path, "HEAD"], in: main)
        let trueCount = try git(["rev-list", "--count", "HEAD"], in: worktree)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try run(in: worktree)
        assertBuilt(result, trueCount: trueCount, because: "a git worktree of a healthy repository must build")
    }

    func testASymlinkedRootOfAHealthyRepositoryBuildsAndAnnouncesTheTrueCount() throws {
        let real = try repoWithCommits(6, label: "gate-control-symlink-real")
        let link = scratchDirectory("gate-control-symlink-holder").appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let trueCount = try git(["rev-list", "--count", "HEAD"], in: real)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try run(in: link)
        assertBuilt(result, trueCount: trueCount, because: "a root reached through a symlink must build")
    }

    /// A repository with `count` commits, at an exact leaf name under a fresh
    /// scratch holder — unlike `repoWithCommits`, which folds a UUID into the
    /// directory name itself, this leaves the leaf spelled exactly as asked so
    /// a caller can hand back an alias of the same directory in another case
    /// or normalisation.
    private func repoWithCommits(_ count: Int, namedExactly name: String, under label: String) throws -> URL {
        let dir = scratchDirectory(label).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try git(["init", "-q"], in: dir)
        for i in 1...count {
            try write("f.txt", in: dir, bytes: 4, filler: UInt8(i % 256))
            try git(["add", "f.txt"], in: dir)
            try git(["commit", "-q", "-m", "c\(i)"], in: dir)
        }
        return dir
    }

    /// The regression this fix closes: the top-level comparison used to
    /// resolve both sides with bash's own `pwd -P` and compare the two
    /// strings, but bash's builtin does not consult the filesystem for a
    /// directory's on-disk spelling the way `/bin/pwd -P` or git itself does
    /// — it keeps whatever spelling the `cd` argument already had. On a
    /// case-insensitive volume that makes the two differ for a checkout
    /// entered through another case of its own name (measured on this
    /// script, run through `/bin/bash` exactly as the real script is:
    /// `RESOLVED_ROOT` came back spelled the way the invocation typed it, not
    /// the way the directory is actually spelled on disk), and the gate
    /// refused a healthy tree as "a work tree other than $REPO_ROOT itself".
    func testAPathReachedThroughAnotherCaseOfItsOwnSpellingBuildsAndAnnouncesTheTrueCount() throws {
        let lower = try repoWithCommits(4, namedExactly: "case-repo", under: "gate-control-case")
        let trueCount = try git(["rev-list", "--count", "HEAD"], in: lower)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let upperSpelling = lower.deletingLastPathComponent().appendingPathComponent("CASE-REPO")
        let result = try run(in: upperSpelling)
        assertBuilt(result, trueCount: trueCount,
                   because: "a healthy repository reached through another case of its own directory name must build")
    }

    // An NFC/NFD control was tried here and dropped: `URL.appendingPathComponent`
    // and `URL(fileURLWithPath:)` both normalise a path component to NFD before
    // it ever reaches `FileManager` or `Process` (measured — an NFC and an NFD
    // Swift string produce byte-identical `.path` output), so a test built on
    // top of this suite's `URL`-typed helpers cannot construct the two distinct
    // on-disk spellings it would need to tell apart, and would pass against the
    // unfixed script for the wrong reason. Checked by hand instead, with raw
    // shell paths that bypass `URL` entirely: the unfixed script refuses a
    // healthy repository entered through an NFD spelling of its own NFC name,
    // and `Scripts/package-app.sh`'s `-ef` comparison builds it.
}
