// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport

/// The build-number gate at the top of `Scripts/package-app.sh`, run for real
/// against throwaway repositories, the way `AFailedCopyKeepsTheInstalledAppTests`
/// drives the swap script.
///
/// Most cases are a history the gate must refuse *before* the compile: a tree
/// that answers the two git questions from somewhere other than itself (a
/// foreign `GIT_DIR`, an ancestor's `.git`, its own `core.worktree` pointed
/// elsewhere), or a history that reads shorter than it is (shallow, grafted).
/// The rest are controls that must build: a healthy layout reached through a
/// worktree, a symlink, another case of its spelling, or with a trace running,
/// so a gate that refuses too eagerly is caught as surely as one that refuses
/// too little. A gate that let a bad case through would run a real
/// `swift build -c release` and `rm -rf` under `$TMPDIR/helm-package`, so the
/// script always gets a stub `swift` that fails at once and a `TMPDIR` in
/// scratch.
final class TheBuildNumberGateRefusesTests: XCTestCase {

    private struct SetupFailure: Error, CustomStringConvertible {
        let description: String
    }

    private var scriptPath: URL {
        RepoSource.root.appendingPathComponent("Scripts/package-app.sh")
    }

    // MARK: - Building the repositories the gate is asked to judge

    /// A throwaway identity, and no `~/.gitconfig`: a real one can name
    /// `core.hooksPath` or set `commit.gpgsign = true`, turning `git commit`
    /// here into a call to a real hook or signer, and `GIT_AUTHOR_*` alone does
    /// not stop that. `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`
    /// do.
    private func git(_ args: [String], in dir: URL, env extra: [String: String] = [:]) throws -> String {
        var environment = [
            "PATH": "/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Helm Test", "GIT_AUTHOR_EMAIL": "test@helm.invalid",
            "GIT_COMMITTER_NAME": "Helm Test", "GIT_COMMITTER_EMAIL": "test@helm.invalid",
        ]
        for (key, value) in extra { environment[key] = value }
        let result = try runChild("/usr/bin/git", args, environment: environment, directory: dir, mergeStderr: true)
        guard result.status == 0 else {
            throw SetupFailure(description: "git \(args.joined(separator: " ")) failed "
                               + "(\(result.status)): \(result.output)")
        }
        return result.output
    }

    /// A repository with `count` commits on its only branch, one byte of
    /// filler changing each time so every commit is really new.
    private func repoWithCommits(_ count: Int, label: String) throws -> URL {
        let dir = scratchDirectory(label)
        _ = try git(["init", "-q"], in: dir)
        for i in 1...count {
            try write("f.txt", in: dir, bytes: 4, filler: UInt8(i % 256))
            _ = try git(["add", "f.txt"], in: dir)
            _ = try git(["commit", "-q", "-m", "c\(i)"], in: dir)
        }
        return dir
    }

    // MARK: - Running the real script

    /// Copies the real script under `repo/Scripts/`, so `SCRIPT_DIR/..`
    /// resolves to `repo` exactly as it does in the tree, then runs it with a
    /// `swift` that refuses instantly and a `TMPDIR` inside scratch — so a
    /// gate that wrongly passes fails fast rather than building or deleting
    /// anything real.
    private func run(in repo: URL, extraEnv: [String: String] = [:]) throws -> ChildResult {
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

        // As in `git(_:in:env:)`: a real ~/.gitconfig could steer the
        // script's own git calls.
        var environment = [
            "PATH": "\(stubBin.path):/usr/bin:/bin",
            "TMPDIR": tmp.path,
            "HOME": NSHomeDirectory(),
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
        ]
        for (key, value) in extraEnv { environment[key] = value }
        return try runChild("/bin/bash", [copy.path], environment: environment, mergeStderr: true)
    }

    private func lineCount(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: "\n").filter { $0.contains(needle) }.count
    }

    /// The two facts every case below asserts: the gate refused (a status
    /// and a refusal line are both the subject having happened, not only its
    /// absence), and the compile it guards never started.
    private func assertRefused(_ result: ChildResult, because why: String,
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
    private func assertBuilt(_ result: ChildResult, trueCount: String, because why: String,
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
    /// `gitformat-commit-graph`'s Commit Data chunk). Built here so the tree
    /// holds no binary fixture.
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
        // The refusal quotes what git said rather than guessing a cause: git's
        // reason may be dubious ownership or a permission denial.
        XCTAssertTrue(result.output.contains("git said:"),
                      "the refusal must quote git's own standard error: \(result.output)")
        XCTAssertFalse(result.output.contains("no .git anywhere above it either"),
                       "the refusal must not claim a cause it has not established: \(result.output)")
    }

    func testAShallowCloneRefuses() throws {
        let source = try repoWithCommits(10, label: "gate-shallow-source")
        let clone = scratchDirectory("gate-shallow-clone")
        _ = try git(["clone", "-q", "--depth", "3", "file://\(source.path)", clone.path], in: source)
        let result = try run(in: clone)
        assertRefused(result, because: "a shallow clone counts only the commits it fetched")
    }

    /// The shallow refusal survives a trace running alongside it. Every
    /// `GIT_TRACE*` name is unset before the gate's first git call, so
    /// `GIT_TRACE=/dev/stdout` behaves the same
    /// (`testAHealthyRepositorySurvivesGitTraceToStandardOut`).
    func testAShallowCloneRefusesWithATraceRunning() throws {
        let source = try repoWithCommits(10, label: "gate-shallow-trace-source")
        let clone = scratchDirectory("gate-shallow-trace-clone")
        _ = try git(["clone", "-q", "--depth", "3", "file://\(source.path)", clone.path], in: source)
        let result = try run(in: clone, extraEnv: ["GIT_TRACE": "1"])
        assertRefused(result, because: "a shallow clone must refuse whether or not GIT_TRACE is set")
    }

    func testARepositoryWithNoCommitsRefuses() throws {
        let repo = scratchDirectory("gate-no-commits")
        _ = try git(["init", "-q"], in: repo)
        let result = try run(in: repo)
        assertRefused(result, because: "a fresh `git init` over sources has no HEAD to count")
        // No guessed cause in the message.
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
        _ = try git(["replace", "--graft", "HEAD~5"], in: repo)
        let result = try run(in: repo)
        assertRefused(result, because: "a replacement ref can give a commit a shorter parent chain")
    }

    /// The older mechanism `--no-replace-objects` does not reach: `info/grafts`,
    /// refused, like a replacement ref, for being present.
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
    /// way a graft does, but it is neutralised at the count itself
    /// (`-c core.commitGraph=false`) rather than refused, so the expected
    /// outcome is a build announcing the true count. A refusal is accepted
    /// too; a silent undercount is not.
    func testAForgedCommitGraphDoesNotUndercount() throws {
        let repo = try repoWithCommits(10, label: "gate-forged-commit-graph")
        let trueCount = try git(["rev-list", "--count", "HEAD"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ancestor = try git(["rev-parse", "HEAD~5"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try git(["commit-graph", "write", "--reachable"], in: repo)
        try forgeCommitGraphDroppingParent(of: ancestor, in: repo)
        let result = try run(in: repo)
        // Not `result.status`: the stub `swift` exits 17 on the path that
        // reaches the compile, so only the refusal line tells the two apart.
        if lineCount("!! Build number:", in: result.output) == 0 {
            assertBuilt(result, trueCount: trueCount,
                       because: "a forged commit-graph must not undercount if the gate lets the build through")
        } else {
            assertRefused(result, because: "a forged commit-graph can shorten a commit's parent chain")
        }
    }

    // MARK: - Cases: an ancestor's config, not its own .git, answering for a tree

    /// `core.worktree` in an ancestor's config can make `rev-parse
    /// --show-toplevel` answer with a path that has no `.git` of its own, and
    /// the top-level comparison alone reads that as this checkout's own top
    /// level.
    func testAnAncestorsCoreWorktreeCannotStandInForOurOwnGit() throws {
        let ancestor = try repoWithCommits(30, label: "gate-worktree-config-ancestor")
        let inner = ancestor.appendingPathComponent("inner/sub")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        _ = try git(["config", "core.worktree", inner.path], in: ancestor)
        let result = try run(in: inner)
        assertRefused(result, because: "inner/sub has no .git of its own even though an ancestor's "
                      + "core.worktree makes rev-parse --show-toplevel answer inner/sub")
    }

    /// An empty directory named `.git` is not a repository, and plain
    /// discovery walks past it and answers with the ancestor's count; the
    /// `--git-dir` pin refuses it (`GIT_DIR_ARG` in the script).
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

    /// The repository's *own* `core.worktree`, not an ancestor's: the repo
    /// has a real `.git`, so the pin resolves it directly, and its own config
    /// sends `--show-toplevel` to another existing directory. Only the `-ef`
    /// comparison catches it, so the assertion reads that line's own text: the
    /// cases above refuse at the earlier `--git-dir` pin whether or not the
    /// `-ef` check runs.
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

    /// The environment guard's line says "is set in the environment", a
    /// phrase no other refusal uses. Without the guard, `GIT_WORK_TREE` alone
    /// is still refused further down by the top-level compare, so only this
    /// line tells the guard from that check. An empty `GIT_DIR` is caught
    /// nowhere else: with `--git-dir` on the command line git ignores
    /// `GIT_DIR`, so `assertRefused` alone catches its loss.
    private func assertRefusedByTheEnvironmentGuard(_ result: ChildResult, because why: String,
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
    /// reads it as set; `${GIT_DIR:-}` and `-n` would not). Once `--git-dir`
    /// is on the command line git ignores `GIT_DIR`, so this guard is the only
    /// refusal an empty `GIT_DIR` gets.
    func testAnEmptyGitDirRefusesEvenThoughItIsSetToNothing() throws {
        let repo = try repoWithCommits(3, label: "gate-empty-gitdir")
        let result = try run(in: repo, extraEnv: ["GIT_DIR": ""])
        assertRefusedByTheEnvironmentGuard(result, because: "GIT_DIR set to the empty string is still set")
    }

    // MARK: - Cases: a healthy layout must build, whatever else is true of the environment

    /// `GIT_TRACE=/dev/stdout` writes into the descriptor a value is captured
    /// from, which would make `rev-parse --show-toplevel` print more than one
    /// line. Every `GIT_TRACE*` name is unset before the gate's first git
    /// call, so a healthy repository must build and announce its true count,
    /// with no second acceptable outcome.
    func testAHealthyRepositorySurvivesGitTraceToStandardOut() throws {
        let repo = try repoWithCommits(4, label: "gate-trace-healthy")
        let trueCount = try git(["rev-list", "--count", "HEAD"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try run(in: repo, extraEnv: ["GIT_TRACE": "/dev/stdout"])
        assertBuilt(result, trueCount: trueCount,
                   because: "GIT_TRACE=/dev/stdout must not turn a healthy repository into a false refusal")
    }

    /// `run`'s `GIT_CONFIG_GLOBAL=/dev/null` would also close the route
    /// `export GIT_TRACE2=0 GIT_TRACE2_PERF=0 GIT_TRACE2_EVENT=0` exists for: a
    /// `trace2.normalTarget` set in a config file. So this case points
    /// `GIT_CONFIG_GLOBAL` at a file carrying only `[trace2] normalTarget =
    /// /dev/stdout`, and the healthy repository must still build and announce
    /// its true count. Without the export, trace2's preamble lands ahead of
    /// `rev-parse --show-toplevel`'s answer and the gate refuses.
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
    /// standard error carries trace2's preamble (an `elapsed:` line only
    /// trace2 prints) before git's `fatal:` line.
    func testANoCommitsRefusalWithTrace2ToStandardErrorCarriesNoTraceLine() throws {
        let repo = scratchDirectory("gate-trace2-config-nocommits")
        _ = try git(["init", "-q"], in: repo)
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

    /// A repository with `count` commits at an exact leaf name (where
    /// `repoWithCommits` folds in a UUID), so a caller can reach it through
    /// another case of the same name.
    private func repoWithCommits(_ count: Int, namedExactly name: String, under label: String) throws -> URL {
        let dir = scratchDirectory(label).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try git(["init", "-q"], in: dir)
        for i in 1...count {
            try write("f.txt", in: dir, bytes: 4, filler: UInt8(i % 256))
            _ = try git(["add", "f.txt"], in: dir)
            _ = try git(["commit", "-q", "-m", "c\(i)"], in: dir)
        }
        return dir
    }

    /// Bash's builtin `pwd -P` keeps the spelling the `cd` argument had,
    /// where git reads the on-disk spelling, so on a case-insensitive volume
    /// a string comparison of the two refuses a healthy checkout entered
    /// through another case of its name. The gate compares with `-ef`.
    func testAPathReachedThroughAnotherCaseOfItsOwnSpellingBuildsAndAnnouncesTheTrueCount() throws {
        let lower = try repoWithCommits(4, namedExactly: "case-repo", under: "gate-control-case")
        let trueCount = try git(["rev-list", "--count", "HEAD"], in: lower)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let upperSpelling = lower.deletingLastPathComponent().appendingPathComponent("CASE-REPO")
        let result = try run(in: upperSpelling)
        assertBuilt(result, trueCount: trueCount,
                   because: "a healthy repository reached through another case of its own directory name must build")
    }

    // No NFC/NFD control: `URL` normalises a path component to NFD before it
    // reaches `FileManager` or `Process`, so these helpers cannot build the
    // two spellings and such a test would pass for the wrong reason. The `-ef`
    // comparison builds a repository entered through an NFD spelling of its
    // NFC name (checked with raw shell paths).
}
