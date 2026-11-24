import HelmRuntime
import XCTest
import HelmTestSupport
@testable import Module_Uninstaller_Engine

/// `systemextensionsctl`'s silence is not «no extensions»: read so, a bundle
/// refused for a live extension loses the sheet's «Open Extensions…», the one
/// thing a person can act on. `activeExtensionHosts()` answers nil for it; the
/// silence is logged, and not remembered for the rest of the batch.
private final class ToolThatMaySayNothing: SystemExtensionPort, @unchecked Sendable {
    private let lock = NSLock()
    /// One answer per call, the last repeating, so «it failed, then it worked»
    /// is a state this fake can be in.
    private var answers: [Set<String>?]
    private var count = 0

    init(_ answers: [Set<String>?]) { self.answers = answers }

    var asked: Int { lock.withLock { count } }

    func activeExtensionHosts() -> Set<String>? {
        lock.withLock {
            let answer = answers[min(count, answers.count - 1)]
            count += 1
            return answer
        }
    }

}

final class ASilentToolIsNotNoExtensionsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("silent-extensions")
        tailTheLog()
    }

    private var logged: [String] {
        loggedLines(UninstallerEngine.moduleID)
    }

    /// A bundle whose `Info.plist` the engine can read — the id it blames a
    /// refusal on comes from there.
    private func makeApp(named name: String, bundleID: String) throws -> String {
        try writeAppBundle(root.appendingPathComponent("\(name).app"), id: bundleID)
    }

    private func engine(_ tool: ToolThatMaySayNothing) -> UninstallerEngine {
        UninstallerEngine(home: root, apps: FakeApps(), fs: FakeFS(everyPathExistsAt: 0),
                          trash: RefusesEverything(), running: NoRunning(), extensions: tool)
    }

    // MARK: -

    /// A tool that did not answer says so, rather than being taken for a Mac with
    /// no extensions on it.
    func test_a_tool_that_did_not_answer_reaches_the_log() async throws {
        let path = try makeApp(named: "Vendor", bundleID: "com.vendor.app")
        let tool = ToolThatMaySayNothing([nil])

        let result = await engine(tool).trashPaths([path])

        XCTAssertEqual(result.failures.count, 1, "precondition: the bundle really was refused")
        XCTAssertEqual(tool.asked, 1, "precondition: the extension list was looked up at all")
        XCTAssertTrue(logged.contains { $0.contains("extension list") }, """
            the one lookup that could have named the actionable reason failed silently, \
            and nothing in the log says the tool was asked: \(logged)
            """)
    }

    /// And it claims nothing either way: macOS's own reason is what the sheet
    /// shows, not a guess built from a list Helm never read.
    func test_a_tool_that_did_not_answer_keeps_macos_own_reason() async throws {
        let path = try makeApp(named: "Vendor", bundleID: "com.vendor.app")

        let result = await engine(ToolThatMaySayNothing([nil])).trashPaths([path])

        XCTAssertEqual(result.failures.first?.reason, TrashFailure.Reason.noPermission,
                       "a reading Helm never got was turned into a claim about the bundle")
    }

    /// Both bundles host an extension, and the tool is silent only the first
    /// time. Which one `HelmTrash` reaches first is its business, so the assertion
    /// is on the pair: one keeps macOS's own reason, the other is judged from the
    /// answer that came because the silence was not remembered. Stored, both
    /// would read as «no permission».
    func test_a_silence_is_not_remembered_for_the_rest_of_the_batch() async throws {
        let first = try makeApp(named: "First", bundleID: "com.vendor.first")
        let second = try makeApp(named: "Second", bundleID: "com.vendor.second")
        let tool = ToolThatMaySayNothing([nil, ["com.vendor.first", "com.vendor.second"]])

        let result = await engine(tool).trashPaths([first, second])

        XCTAssertEqual(result.failures.count, 2, "precondition: both bundles were refused")
        XCTAssertEqual(tool.asked, 2,
                       "a tool that did not answer was never asked again inside the batch")
        let reasons = result.failures.map(\.reason)
        XCTAssertEqual(reasons.filter { $0 == .activeSystemExtension }.count, 1, """
            a bundle whose extension is live was classified from the bare Cocoa code, because \
            an earlier path in the same batch had recorded a silence as «this Mac has no \
            extensions» — so the sheet offers nothing to act on: \(reasons)
            """)
        XCTAssertEqual(reasons.filter { $0 == .noPermission }.count, 1,
                       "and the one judged before any answer arrived keeps macOS's own reason")
    }

    /// An answer is read once for the batch, so the retry is not a shell-out per path.
    func test_an_answer_is_read_once_for_the_whole_batch() async throws {
        let one = try makeApp(named: "One", bundleID: "com.vendor.one")
        let two = try makeApp(named: "Two", bundleID: "com.vendor.two")
        let tool = ToolThatMaySayNothing([["com.vendor.one"]])

        let result = await engine(tool).trashPaths([one, two])

        XCTAssertEqual(result.failures.count, 2, "precondition: both bundles were refused")
        XCTAssertEqual(tool.asked, 1,
                       "the lookup shells out, and it was run once per failing path")
    }
}
