import XCTest

/// The two copies of the crew, checked as data.
///
/// The agent definitions exist twice: `.claude/agents/` is what this checkout
/// uses, and `plugins/helm-crew/agents/` is what the plugin installs. A bare
/// `.claude/agents/` directory is not picked up when the crew is installed as a
/// plugin, and the plugin copy is not what a plain checkout reads — so both have
/// to exist, and the README says they are "kept in step" by hand.
///
/// By hand is how they drift. Editing one and forgetting the other leaves an
/// agent working from a map that is right in one place and wrong in the other,
/// which is the same class of defect as CLAUDE.md's list of helpers that were
/// each written twice before they moved: nothing errors, the answer is just
/// quietly wrong for whoever reads the stale copy.
///
/// This is a guard rather than prose because prose does not fail.
final class CrewInStepTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HelmUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
    }

    /// Both copies live in whatever checkout this test is running from — a
    /// worktree included, because both directories are tracked.
    ///
    /// The first version of this walked up out of a worktree to "the real
    /// repository", which sounded careful and was worse than useless: it checked
    /// a different tree from the one being edited, so it passed green while the
    /// two copies here had genuinely drifted. A guard that looks somewhere other
    /// than at the change is a guard that lies.
    private func agentDirs() throws -> (checkout: URL, plugin: URL) {
        let checkout = repo.appendingPathComponent(".claude/agents")
        let plugin = repo.appendingPathComponent("plugins/helm-crew/agents")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: checkout.path)
                && FileManager.default.fileExists(atPath: plugin.path),
            "the crew is not in this checkout")
        return (checkout, plugin)
    }

    private func agents(_ dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("helm-") && $0.hasSuffix(".md") }
            .sorted()
    }

    func testBothCopiesHoldTheSameAgents() throws {
        let (checkout, plugin) = try agentDirs()
        let a = try agents(checkout), b = try agents(plugin)
        XCTAssertFalse(a.isEmpty, "no agents found — the path is wrong, not the crew")
        XCTAssertEqual(a, b, "one copy has an agent the other does not")
    }

    func testEveryAgentIsByteIdenticalInBothCopies() throws {
        let (checkout, plugin) = try agentDirs()
        for name in try agents(checkout) {
            let one = try Data(contentsOf: checkout.appendingPathComponent(name))
            let two = try Data(contentsOf: plugin.appendingPathComponent(name))
            XCTAssertEqual(one, two, "\(name) has drifted between the two copies")
        }
    }

    /// An agent that names a skill must be able to invoke one. The frontmatter
    /// is the whole of that permission, and a prompt that says "invoke X via the
    /// Skill tool" without `Skill` in `tools:` is an instruction the agent
    /// cannot follow — and nothing at runtime says so.
    func testAnAgentThatNamesASkillDeclaresTheSkillTool() throws {
        let (checkout, _) = try agentDirs()
        for name in try agents(checkout) {
            let text = try String(contentsOf: checkout.appendingPathComponent(name),
                                  encoding: .utf8)
            guard text.contains("via the Skill tool") else { continue }
            guard let tools = text.split(separator: "\n")
                .first(where: { $0.hasPrefix("tools:") }) else {
                XCTFail("\(name) names a skill and declares no tools at all")
                continue
            }
            XCTAssertTrue(tools.contains("Skill"),
                          "\(name) tells the agent to use the Skill tool but does not grant it: \(tools)")
        }
    }
}
