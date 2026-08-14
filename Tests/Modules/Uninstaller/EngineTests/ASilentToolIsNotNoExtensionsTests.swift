import HelmRuntime
import XCTest
import HelmTestSupport
@testable import Module_Uninstaller_Engine

/// **`systemextensionsctl`'s silence was read as «no extensions», and it cost the
/// module its one actionable reason.**
///
/// `SystemExtensionCLI.listing()` answers nil when the tool's exit status is not
/// 0; `listOutput()` folded that to `""`, and the host lookup was built on the
/// folded reader. So a bundle macOS refused *because its extension is live* was
/// classified from the bare Cocoa code, and the failure sheet's «Open
/// Extensions…» button — the one thing on that screen a person can act on — did
/// not appear.
///
/// The repair is on the port, the `PowerSource.supply()` precedent:
/// `activeExtensionHosts()` answers `Set<String>?`, nil for «the tool did not
/// answer». Two things follow, and both are below: a silence is said out loud
/// instead of being taken for an empty list, and it is **not** remembered for the
/// rest of the batch, so one transient failure does not take the extension reason
/// away from every bundle after it.
private final class ToolThatMaySayNothing: SystemExtensionPort, @unchecked Sendable {
    private let lock = NSLock()
    /// One answer per call, the last repeating — so «it failed, then it worked»
    /// is a state this fake can be in. A single stored value could not say it,
    /// and that is the state the whole finding is about.
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

    func installedExtensions() -> [SystemExtensionInfo] { [] }
}

/// Refuses every bundle, so the classification is what the test is about.
private struct RefusingTrash: TrashPort {
    func trashItem(_ url: URL) -> TrashOutcome {
        // 513 = NSFileWriteNoPermissionError, what macOS answers for a bundle it
        // will not move.
        TrashOutcome(succeeded: false, errorCode: 513, message: "denied")
    }
}
private struct AnyFS: FileSystemPort {
    func exists(_ url: URL) -> Bool { true }
    func size(_ url: URL) -> Int { 0 }
    func glob(_ pattern: URL) -> [URL] { [] }
    func children(of url: URL) -> [URL] { [] }
}
private struct NoLister: AppLister {
    func installedApps() -> [InstalledApp] { [] }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
    func installedBundleIDs() -> Set<String> { [] }
    func isKnownToSystem(bundleID: String) -> Bool { false }
}

final class ASilentToolIsNotNoExtensionsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("silent-extensions")
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var logged: [String] {
        HelmLog.shared.recentEntries()
            .filter { $0.category == UninstallerEngine.moduleID }
            .map(\.message)
    }

    /// A bundle whose `Info.plist` the engine can read — the id it blames a
    /// refusal on comes from there.
    private func makeApp(named name: String, bundleID: String) throws -> String {
        let app = root.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try (["CFBundleIdentifier": bundleID] as NSDictionary)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return app.path
    }

    private func engine(_ tool: ToolThatMaySayNothing) -> UninstallerEngine {
        UninstallerEngine(home: root, apps: NoLister(), fs: AnyFS(),
                          trash: RefusingTrash(), running: NoRunning(), extensions: tool)
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

    /// **The harm, made observable.** One silence used to be remembered as an
    /// empty list for the whole batch, so every bundle after it lost the reason —
    /// and with it the «Open Extensions…» button, the only thing on that screen
    /// anybody can act on.
    /// Both bundles host an extension, and the tool is silent only the first time
    /// it is asked. Which of the two `HelmTrash` reaches first is its business, so
    /// the assertion is on the pair: one of them was judged while nothing had been
    /// read — that one keeps macOS's own reason — and the other was judged from an
    /// answer that arrived because the silence was not remembered. With the
    /// silence stored, **both** would read as «no permission».
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

    /// The half that keeps the retry above from becoming a shell-out per path: an
    /// answer is an answer, and it is read once for the batch.
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
