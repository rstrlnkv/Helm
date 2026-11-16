// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport

/// **The channel a bundle belongs to is written by the packaging script and read
/// back by the disk-image script, because a bare version cannot tell a dev build
/// from a beta.**
///
/// `Scripts/package-app.sh` is run for real against throwaway repositories, as
/// `TheBuildNumberGateRefusesTests` does, with a `swift` that does nothing and an
/// `xcrun` that stops the script right after it wrote `Info.plist`, so the staged
/// plist is what is read back. `Scripts/make-dmg.sh` is run against a tiny
/// ad-hoc-signed bundle with a `swift` that records its arguments and stops: the
/// `--dev` flag on the background drawing is what the case reads.
///
/// Past defect: a DEV build carried `0.11.2`, no `-dev` suffix, and got the
/// non-dev window and the Beta badge.
final class ThePackagedBundleNamesItsChannelTests: XCTestCase {

    private struct SetupFailure: Error, CustomStringConvertible { let description: String }

    private var realScripts: URL { RepoSource.root.appendingPathComponent("Scripts") }

    // MARK: - Repositories

    private func git(_ args: [String], in dir: URL) throws {
        let env = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(),
                   "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
                   "GIT_AUTHOR_NAME": "Helm Test", "GIT_AUTHOR_EMAIL": "test@helm.invalid",
                   "GIT_COMMITTER_NAME": "Helm Test", "GIT_COMMITTER_EMAIL": "test@helm.invalid"]
        let r = try runChild("/usr/bin/git", args, environment: env, directory: dir, mergeStderr: true)
        guard r.status == 0 else {
            throw SetupFailure(description: "git \(args.joined(separator: " ")): \(r.output)")
        }
    }

    /// A repository on `branch` (nil: detached at its only-but-one commit) with
    /// everything the script copies before the icon step.
    private func repo(branch: String?, label: String) throws -> URL {
        let dir = scratchDirectory(label)
        try git(["init", "-q", "-b", "scratch-initial"], in: dir)
        let fm = FileManager.default
        try write("f.txt", in: dir)
        try write("NOTICE.md", in: dir)
        try write(".build/release/HelmApp", in: dir)
        try fm.createDirectory(at: dir.appendingPathComponent(".build/release/Fake.bundle"),
                               withIntermediateDirectories: true)
        try write("Resources/Icon/Helm.icon/Assets/helm-ring.svg", in: dir)
        try fm.createDirectory(at: dir.appendingPathComponent("Resources/HelmApp"),
                               withIntermediateDirectories: true)
        try fm.copyItem(at: RepoSource.root.appendingPathComponent("Resources/HelmApp/Info.plist"),
                        to: dir.appendingPathComponent("Resources/HelmApp/Info.plist"))
        try fm.createDirectory(at: dir.appendingPathComponent("Scripts"), withIntermediateDirectories: true)
        try fm.copyItem(at: realScripts.appendingPathComponent("package-app.sh"),
                        to: dir.appendingPathComponent("Scripts/package-app.sh"))
        try git(["add", "-A", "-f"], in: dir)
        try git(["commit", "-q", "-m", "c1"], in: dir)
        try write("f.txt", in: dir, bytes: 4, filler: 0x42)
        try git(["commit", "-q", "-am", "c2"], in: dir)
        if let branch {
            try git(["checkout", "-q", "-B", branch], in: dir)
        } else {
            try git(["checkout", "-q", "--detach"], in: dir)
        }
        return dir
    }

    private func stub(_ name: String, _ body: String, in bin: URL) throws {
        let url = bin.appendingPathComponent(name)
        try "#!/bin/bash\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private struct Packaged {
        let result: ChildResult
        let tmp: URL
        var stagedPlist: String { tmp.appendingPathComponent("helm-package/Helm.app/Contents/Info.plist").path }
    }

    /// `swift` succeeds silently; `xcrun` ends the script right after the plist
    /// was written, so a run that got that far prints the stub's marker.
    private func package(_ repo: URL, channel: String? = nil) throws -> Packaged {
        let bin = scratchDirectory("channel-stubs")
        try stub("swift", "exit 0", in: bin)
        try stub("xcrun", "echo 'STUB XCRUN — the plist is written by now' >&2; exit 19", in: bin)
        let tmp = scratchDirectory("channel-tmpdir")
        var env = ["PATH": "\(bin.path):/usr/bin:/bin", "TMPDIR": tmp.path, "HOME": NSHomeDirectory(),
                   "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]
        if let channel { env["HELM_CHANNEL"] = channel }
        let r = try runChild("/bin/bash", [repo.appendingPathComponent("Scripts/package-app.sh").path],
                             environment: env, mergeStderr: true)
        return Packaged(result: r, tmp: tmp)
    }

    private func channelKey(_ p: Packaged) throws -> String? {
        let r = try runChild("/usr/libexec/PlistBuddy", ["-c", "Print :HelmChannel", p.stagedPlist],
                             mergeStderr: true)
        return r.status == 0 ? r.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    private func assertWrote(_ channel: String, _ p: Packaged, because why: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(p.result.output.contains("STUB XCRUN"),
                      "\(why): the script never reached the end of the plist step: \(p.result.output)",
                      file: file, line: line)
        XCTAssertEqual(try channelKey(p), channel, "\(why): \(p.result.output)", file: file, line: line)
    }

    private func assertRefusedBeforeCompile(_ p: Packaged, mentioning word: String, because why: String,
                                            file: StaticString = #filePath, line: UInt = #line) {
        let out = p.result.output
        XCTAssertNotEqual(p.result.status, 0, "\(why), but exited 0: \(out)", file: file, line: line)
        XCTAssertTrue(out.components(separatedBy: "\n").contains { $0.hasPrefix("!!") && $0.contains(word) },
                      "\(why), but no `!!` line names \(word): \(out)", file: file, line: line)
        XCTAssertFalse(out.contains("==> Building release binary"),
                       "\(why), but the compile started: \(out)", file: file, line: line)
        XCTAssertFalse(out.contains("STUB XCRUN"), "\(why), but the script ran on: \(out)", file: file, line: line)
    }

    // MARK: - package-app.sh: where the channel comes from

    func testTheBetaBranchPackagesABetaBundle() throws {
        try assertWrote("BETA", package(repo(branch: "beta", label: "ch-beta")), because: "branch beta")
    }

    func testTheMainBranchPackagesAStableBundle() throws {
        try assertWrote("STABLE", package(repo(branch: "main", label: "ch-main")), because: "branch main")
    }

    func testAnyOtherNamedBranchPackagesADevBundle() throws {
        try assertWrote("DEV", package(repo(branch: "fix/dev-build-reads-its-channel", label: "ch-fix")),
                        because: "a feature branch")
        try assertWrote("DEV", package(repo(branch: "dev", label: "ch-dev")), because: "branch dev")
        // Near-misses of the two named branches are other branches.
        try assertWrote("DEV", package(repo(branch: "beta2", label: "ch-beta2")), because: "branch beta2")
        try assertWrote("DEV", package(repo(branch: "Main", label: "ch-Main")), because: "branch Main")
    }

    func testTheEnvironmentOverridesTheBranch() throws {
        try assertWrote("STABLE", package(repo(branch: "dev", label: "ch-env-stable"), channel: "STABLE"),
                        because: "HELM_CHANNEL=STABLE on branch dev")
        try assertWrote("DEV", package(repo(branch: "beta", label: "ch-env-dev"), channel: "DEV"),
                        because: "HELM_CHANNEL=DEV on branch beta")
    }

    func testADetachedHeadWithAnExplicitChannelPackages() throws {
        try assertWrote("BETA", package(repo(branch: nil, label: "ch-detached-env"), channel: "BETA"),
                        because: "detached HEAD with HELM_CHANNEL=BETA")
    }

    // MARK: - package-app.sh: what it refuses before compiling

    func testADetachedHeadWithNoChannelRefuses() throws {
        assertRefusedBeforeCompile(try package(repo(branch: nil, label: "ch-detached")),
                                   mentioning: "HELM_CHANNEL",
                                   because: "a detached HEAD names no channel and none was given")
    }

    func testAChannelThatIsNotExactlyOneOfThreeRefuses() throws {
        for bad in ["dev", "Beta", "RELEASE", "DEV ", "STABLE\n", "BETA,DEV"] {
            assertRefusedBeforeCompile(try package(repo(branch: "dev", label: "ch-bad"), channel: bad),
                                       mentioning: "HELM_CHANNEL",
                                       because: "HELM_CHANNEL=\(bad.debugDescription) is not DEV, BETA or STABLE")
        }
    }

    /// A variable that is set and empty is a channel that is present and wrong,
    /// not an absent one: a CI step that exports `HELM_CHANNEL=` from an unset
    /// secret must not fall through to the branch and package silently.
    func testAnEmptyChannelVariableRefusesRatherThanFallingToTheBranch() throws {
        assertRefusedBeforeCompile(try package(repo(branch: "beta", label: "ch-empty"), channel: ""),
                                   mentioning: "HELM_CHANNEL",
                                   because: "HELM_CHANNEL is set to the empty string on branch beta")
    }

    // MARK: - make-dmg.sh: which background the key picks

    /// A minimal ad-hoc-signed bundle the staged-bundle check accepts, and a
    /// `swift` that records the arguments of the background drawing.
    private func dmgArguments(channel: String?, version: String) throws -> String {
        let r = try stagedRun(script: "make-dmg.sh", channel: channel, version: version)
        guard let args = r.args else {
            throw SetupFailure(description: "make-dmg.sh never reached the background drawing: \(r.output)")
        }
        return args
    }

    /// Runs `Scripts/<script>` (make-dmg.sh or make-zip.sh) in a scratch repo on
    /// the staged bundle; returns its merged output and the `swift` arguments, if any.
    private func stagedRun(script: String, channel: String?, version: String) throws -> (output: String, args: String?) {
        let repo = scratchDirectory("ch-dmg-repo")
        let scripts = repo.appendingPathComponent("Scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        for name in [script, "staged-bundle.sh"] {
            try FileManager.default.copyItem(at: realScripts.appendingPathComponent(name),
                                             to: scripts.appendingPathComponent(name))
        }
        let tmp = scratchDirectory("ch-dmg-tmp")
        let app = tmp.appendingPathComponent("helm-package/Helm.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"),
                                                withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"),
                                         to: app.appendingPathComponent("Contents/MacOS/x"))
        let key = channel.map { "<key>HelmChannel</key><string>\($0)</string>" } ?? ""
        try """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>CFBundleExecutable</key><string>x</string>
            <key>CFBundleIdentifier</key><string>invalid.helm.channel.test</string>
            <key>CFBundleShortVersionString</key><string>\(version)</string>
            \(key)
            </dict></plist>
            """.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        let signed = try runChild("/usr/bin/codesign", ["--force", "--sign", "-", app.path], mergeStderr: true)
        guard signed.status == 0 else { throw SetupFailure(description: "codesign: \(signed.output)") }

        let bin = scratchDirectory("ch-dmg-stubs")
        let record = tmp.appendingPathComponent("swift-args.txt")
        try stub("swift", "echo \"$*\" >> '\(record.path)'; exit 17", in: bin)
        let r = try runChild("/bin/bash", [scripts.appendingPathComponent(script).path],
                             environment: ["PATH": "\(bin.path):/usr/bin:/bin", "TMPDIR": tmp.path,
                                           "HOME": NSHomeDirectory()], mergeStderr: true)
        return (r.output, try? String(contentsOf: record, encoding: .utf8))
    }

    func testADevChannelWithABareVersionDrawsTheDevWindow() throws {
        let args = try dmgArguments(channel: "DEV", version: "0.11.2")
        XCTAssertTrue(args.contains("--dev"), "HelmChannel=DEV must draw the dev window: \(args)")
    }

    func testABetaChannelWithADevSuffixedVersionDrawsTheReleaseWindow() throws {
        let args = try dmgArguments(channel: "BETA", version: "0.11.1-dev.17")
        XCTAssertFalse(args.contains("--dev"), "the key wins over the version suffix: \(args)")
    }

    func testAStableChannelDrawsTheReleaseWindow() throws {
        let args = try dmgArguments(channel: "STABLE", version: "0.11.1")
        XCTAssertFalse(args.contains("--dev"), args)
    }

    func testABundleWithNoKeyKeepsTheVersionSuffixRule() throws {
        XCTAssertTrue(try dmgArguments(channel: nil, version: "0.11.1-dev.17").contains("--dev"))
        XCTAssertFalse(try dmgArguments(channel: nil, version: "0.11.1").contains("--dev"))
    }

    // MARK: - the channel line the release notes are checked against

    private func channelLines(_ output: String) -> [String] {
        output.components(separatedBy: "\n").filter { $0.hasPrefix("==> Channel:") }
    }

    func testMakeZipPrintsTheBundlesChannel() throws {
        let r = try stagedRun(script: "make-zip.sh", channel: "BETA", version: "0.11.1")
        XCTAssertEqual(channelLines(r.output), ["==> Channel: BETA"], r.output)
    }

    func testMakeDmgPrintsTheBundlesChannel() throws {
        let r = try stagedRun(script: "make-dmg.sh", channel: "DEV", version: "0.11.2")
        XCTAssertEqual(channelLines(r.output), ["==> Channel: DEV"], r.output)
    }

    func testBothScriptsSayWhenTheBundlePredatesTheKey() throws {
        for script in ["make-zip.sh", "make-dmg.sh"] {
            let r = try stagedRun(script: script, channel: nil, version: "0.11.1")
            XCTAssertEqual(channelLines(r.output), ["==> Channel: none (bundle predates the key)"],
                           "\(script): \(r.output)")
        }
    }

    // MARK: - package-dev.sh: Helm Dev says DEV on any branch

    /// `package-dev.sh` is copied beside a `package-app.sh` that records the
    /// `HELM_CHANNEL` it was handed and stops the run.
    func testPackageDevHandsPackageAppTheDevChannelWhateverTheEnvironmentSays() throws {
        for inherited in [nil, "BETA", "STABLE"] {
            let scripts = scratchDirectory("ch-pkgdev").appendingPathComponent("Scripts")
            try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: realScripts.appendingPathComponent("package-dev.sh"),
                                             to: scripts.appendingPathComponent("package-dev.sh"))
            let tmp = scratchDirectory("ch-pkgdev-tmp")
            let record = tmp.appendingPathComponent("channel.txt")
            try "echo \"channel=[${HELM_CHANNEL-unset}]\" > '\(record.path)'; exit 19\n"
                .write(to: scripts.appendingPathComponent("package-app.sh"), atomically: true, encoding: .utf8)
            var env = ["PATH": "/usr/bin:/bin", "TMPDIR": tmp.path, "HOME": NSHomeDirectory()]
            if let inherited { env["HELM_CHANNEL"] = inherited }
            _ = try runChild("/bin/bash", [scripts.appendingPathComponent("package-dev.sh").path, "--no-launch"],
                             environment: env, mergeStderr: true)
            XCTAssertEqual(try? String(contentsOf: record, encoding: .utf8), "channel=[DEV]\n",
                           "inherited HELM_CHANNEL=\(inherited ?? "unset")")
        }
    }
}
