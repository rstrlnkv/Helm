import XCTest
@testable import HelmRuntime

/// `~/Library/Logs/Helm/helm.log` is a product surface, and a suite run used to
/// write into it.
///
/// `EngineReply` logs at `error` when a payload will not decode or a reply will
/// not encode — and its own tests exercise exactly that, because that is the
/// behaviour they were written for. The lines landed in the file every dev build
/// is triaged against before it ships, wearing the same shape as a real fault,
/// and four of them were investigated as a defect that did not exist.
///
/// The guard belongs here rather than beside those tests: any test that reaches
/// any logging code writes, so the thing to hold still is where the log resolves
/// its destination, not which four call sites happen to log today.
final class TheSuiteDoesNotWriteTheUsersLogTests: XCTestCase {

    /// Spelled out rather than read off `HelmLog`, which is the thing on trial.
    /// Taking the path from the subject would make every assertion below agree
    /// with whatever the subject decided, including "the shipping file".
    private var shippingFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Helm", isDirectory: true)
    }
    private var shippingLog: URL { shippingFolder.appendingPathComponent("helm.log") }

    override func tearDown() {
        HelmLog.shared.setEnabled(false)
        HelmLog.shared.clearTail()
        super.tearDown()
    }

    // MARK: - The rule

    func testTheShippingBuildLogsWhereMacOSUsersLook() {
        let folder = LogDestination.directory(home: URL(fileURLWithPath: "/Users/anna"),
                                              temporary: URL(fileURLWithPath: "/tmp"),
                                              underTest: false)
        XCTAssertEqual(folder.path, "/Users/anna/Library/Logs/Helm")
    }

    func testATestRunLogsAnywhereButThere() {
        let home = URL(fileURLWithPath: "/Users/anna")
        let folder = LogDestination.directory(home: home,
                                              temporary: URL(fileURLWithPath: "/tmp"),
                                              underTest: true)
        XCTAssertFalse(folder.path.hasPrefix(home.path),
                       "a test run would write under somebody's home directory")
    }

    /// The mechanism has to be on for this process, or everything below is a
    /// test of a rule nobody applied.
    func testThisProcessIsResolvedAsATestRun() {
        XCTAssertNotEqual(HelmLog.directory, shippingFolder)
        XCTAssertNotEqual(HelmLog.fileURL, shippingLog)
    }

    // MARK: - The guard

    /// The one that would have caught it.
    ///
    /// Asserting that the file did not grow passes for free when nothing was
    /// written at all, so the line is proven to exist first — in the tail, which
    /// is filled from the same parts the file line is spelled from.
    func testAnErrorLoggedByATestDoesNotReachTheFileWeTriage() {
        let before = shippingLogState()
        let marker = "log destination guard \(UUID().uuidString)"

        HelmLog.shared.setEnabled(true)
        HelmLog.shared.error("engine", marker)
        // `recentEntries` takes the log's own queue, so it returns once the
        // write has run rather than once it was scheduled.
        let entries = HelmLog.shared.recentEntries()

        XCTAssertTrue(entries.contains { $0.message == marker },
                      "nothing was logged, so nothing below is a test of anything")
        XCTAssertEqual(shippingLogState(), before,
                       "a test run appended to \(shippingLog.path)")
        if let text = try? String(contentsOf: shippingLog, encoding: .utf8) {
            XCTAssertFalse(text.contains(marker),
                           "a test's own error text is in the file people triage")
        }
    }

    /// Size and modification date together: a rewrite of the same length moves
    /// one and not the other.
    private struct FileState: Equatable {
        let size: Int
        let modified: Date?
    }

    /// `size: -1` is the absent file, which is a state worth telling from an
    /// empty one.
    private func shippingLogState() -> FileState {
        let attributes = try? FileManager.default.attributesOfItem(atPath: shippingLog.path)
        return FileState(size: (attributes?[.size] as? Int) ?? -1,
                         modified: attributes?[.modificationDate] as? Date)
    }
}
