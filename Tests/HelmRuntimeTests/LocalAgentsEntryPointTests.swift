import Foundation
import HelmTestSupport
import XCTest

final class LocalAgentsEntryPointTests: XCTestCase {
    private let projectRules = "# Fixture project rules\n\nCheck the fixture input.\n"
    private let sharedRules = "# Shared fixture rules\n\nUse a scratch directory.\n"

    func testRelativeBacktickedEntryReturnsProjectRules() throws {
        let root = scratchDirectory("relative-agents")
        let checkout = root.appendingPathComponent("Helm")
        try put(sharedRules, at: root.appendingPathComponent("Core/AGENTS.md"))
        try put(projectRules, at: root.appendingPathComponent("Core/helm/AGENTS.md"))
        try putRelativeEntry(in: checkout)

        XCTAssertEqual(try RepoSource.rules(from: checkout), projectRules)
    }

    func testScaffoldedAbsoluteEntryReturnsProjectRulesFromConfiguredCore() throws {
        let root = scratchDirectory("absolute-agents")
        let checkout = root.appendingPathComponent("Helm")
        let core = root.appendingPathComponent("Fixture Core")
        let configured = root.appendingPathComponent("Core Alias")
        try put(sharedRules, at: core.appendingPathComponent("AGENTS.md"))
        try put(projectRules, at: core.appendingPathComponent("helm/AGENTS.md"))
        try FileManager.default.createSymbolicLink(at: configured, withDestinationURL: core)
        try putAbsoluteEntry(in: checkout, core: core.resolvingSymlinksInPath())

        XCTAssertEqual(try RepoSource.rules(from: checkout, coreDirectory: configured), projectRules)
    }

    func testRelativeEntryWithMissingProjectTargetThrows() throws {
        let root = scratchDirectory("missing-relative-agents")
        let checkout = root.appendingPathComponent("Helm")
        try put(sharedRules, at: root.appendingPathComponent("Core/AGENTS.md"))
        try putRelativeEntry(in: checkout)

        XCTAssertThrowsError(try RepoSource.rules(from: checkout))
    }

    func testAbsoluteEntryWithMissingProjectTargetThrows() throws {
        let root = scratchDirectory("missing-absolute-agents")
        let checkout = root.appendingPathComponent("Helm")
        let core = root.appendingPathComponent("Core")
        try put(sharedRules, at: core.appendingPathComponent("AGENTS.md"))
        try putAbsoluteEntry(in: checkout, core: core)

        XCTAssertThrowsError(try RepoSource.rules(from: checkout))
    }

    func testDirectRulesDocumentReturnsItsContents() throws {
        let checkout = scratchDirectory("direct-agents")
        try put(projectRules, at: checkout.appendingPathComponent("AGENTS.md"))

        XCTAssertEqual(try RepoSource.rules(from: checkout), projectRules)
    }

    func testSymlinkReturnsRulesFromItsTarget() throws {
        let root = scratchDirectory("symlinked-agents")
        let checkout = root.appendingPathComponent("Helm")
        let target = root.appendingPathComponent("Outside/AGENTS.md")
        try put(projectRules, at: target)
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: checkout.appendingPathComponent("AGENTS.md"),
                                                    withDestinationURL: target)

        XCTAssertEqual(try RepoSource.rules(from: checkout), projectRules)
    }

    func testCloneWithoutLocalEntryReturnsNil() throws {
        let root = scratchDirectory("clone-without-agents")
        let checkout = root.appendingPathComponent("Helm")
        try put("ref: refs/heads/main\n", at: checkout.appendingPathComponent(".git/HEAD"))
        try put(projectRules, at: root.appendingPathComponent("Core/helm/AGENTS.md"))

        XCTAssertNil(try RepoSource.rules(from: checkout))
    }

    func testLinkedWorktreeResolvesRelativeEntryFromMainCheckout() throws {
        let root = scratchDirectory("worktree-agents")
        let checkout = root.appendingPathComponent("Helm")
        let worktree = root.appendingPathComponent("worktrees/topic")
        let gitdir = checkout.appendingPathComponent(".git/worktrees/topic")
        try put("gitdir: \(gitdir.path)\n", at: worktree.appendingPathComponent(".git"))
        try put("../..\n", at: gitdir.appendingPathComponent("commondir"))
        try put(sharedRules, at: root.appendingPathComponent("Core/AGENTS.md"))
        try put(projectRules, at: root.appendingPathComponent("Core/helm/AGENTS.md"))
        try putRelativeEntry(in: checkout)

        XCTAssertEqual(try RepoSource.rules(from: worktree), projectRules)
    }

    func testManagedEntryReadsLegacyRulesFromSiblingCore() throws {
        let root = scratchDirectory("legacy-agents")
        let checkout = root.appendingPathComponent("Helm")
        let core = root.appendingPathComponent("Core")
        let target = core.appendingPathComponent("helm/CLAUDE.md")
        try put(projectRules, at: target)
        try putAbsoluteEntry(in: checkout, core: core, target: target)

        XCTAssertEqual(try RepoSource.rules(from: checkout), projectRules)
    }

    func testManagedEntryRefusesRulesOutsideSiblingCore() throws {
        let root = scratchDirectory("outside-core-agents")
        let checkout = root.appendingPathComponent("Helm")
        let core = root.appendingPathComponent("Core")
        let outside = root.appendingPathComponent("Other Core/helm/AGENTS.md")
        try put(projectRules, at: core.appendingPathComponent("helm/AGENTS.md"))
        try put(sharedRules, at: outside)
        try putAbsoluteEntry(in: checkout, core: core, target: outside)

        XCTAssertThrowsError(try RepoSource.rules(from: checkout))
    }

    func testRelativeEntryRefusesAnotherProjectInCore() throws {
        let root = scratchDirectory("other-project-agents")
        let checkout = root.appendingPathComponent("Helm")
        try put(projectRules, at: root.appendingPathComponent("Core/helm/AGENTS.md"))
        try put(sharedRules, at: root.appendingPathComponent("Core/other/AGENTS.md"))
        try putRelativeEntry(in: checkout, project: "other")

        XCTAssertThrowsError(try RepoSource.rules(from: checkout))
    }

    func testManagedEntryRefusesProjectDirectorySymlinkOutsideHelm() throws {
        let root = scratchDirectory("project-link-agents")
        let checkout = root.appendingPathComponent("Helm")
        let core = root.appendingPathComponent("Core")
        let otherProject = core.appendingPathComponent("other")
        try put(sharedRules, at: otherProject.appendingPathComponent("AGENTS.md"))
        try FileManager.default.createSymbolicLink(at: core.appendingPathComponent("helm"),
                                                    withDestinationURL: otherProject)
        try putAbsoluteEntry(in: checkout, core: core)

        XCTAssertThrowsError(try RepoSource.rules(from: checkout))
    }

    func testManagedEntryRefusesRulesFileSymlinkOutsideHelm() throws {
        let root = scratchDirectory("file-link-agents")
        let checkout = root.appendingPathComponent("Helm")
        let core = root.appendingPathComponent("Core")
        let project = core.appendingPathComponent("helm")
        let outside = root.appendingPathComponent("Outside/AGENTS.md")
        try put(sharedRules, at: outside)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: project.appendingPathComponent("AGENTS.md"),
                                                    withDestinationURL: outside)
        try putAbsoluteEntry(in: checkout, core: core)

        XCTAssertThrowsError(try RepoSource.rules(from: checkout))
    }

    private func putRelativeEntry(in checkout: URL, project: String = "helm") throws {
        try put("""
            # Local agent entry point

            Read these fixture files from the checkout:

            - `../Core/AGENTS.md`
            - `../Core/\(project)/AGENTS.md`

            """, at: checkout.appendingPathComponent("AGENTS.md"))
    }

    private func putAbsoluteEntry(in checkout: URL, core: URL, target: URL? = nil) throws {
        let path = target ?? core.appendingPathComponent("helm/AGENTS.md")
        try put("""
            # Local agent entry point

            Read the fixture instructions:

            - Core (if present): \(core.appendingPathComponent("AGENTS.md").path)
            - Project: \(path.path)

            """, at: checkout.appendingPathComponent("AGENTS.md"))
    }

    private func put(_ text: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
