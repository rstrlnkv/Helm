import XCTest
@testable import HelmRuntime

/// `~/Library/Logs/Helm/helm.log` is a product surface, and a suite run used to
/// write into it.
///
/// The engine wire, since removed, logged at `error` when a reply would not encode,
/// and when it still read payloads it logged one that would not decode — and its own tests, since
/// cut, exercised exactly that, because that was the behaviour they were written
/// for. The lines landed in the file every dev build
/// is triaged against before it ships, wearing the same shape as a real fault,
/// and four of them were investigated as a defect that did not exist.
///
/// The guard stands where the log resolves its destination, not at any call
/// site: any test that switches the log on and reaches logging code writes.
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
        for id in ["com.helm.app", nil] as [String?] {
            XCTAssertEqual(LogDestination.directory(home: URL(fileURLWithPath: "/Users/anna"),
                                                    temporary: URL(fileURLWithPath: "/tmp"),
                                                    underTest: false, bundleIdentifier: id).path,
                           "/Users/anna/Library/Logs/Helm", "\(id ?? "nil")")
        }
    }

    func testHelmDevLogsInAFolderOfItsOwn() {
        let folder = LogDestination.directory(home: URL(fileURLWithPath: "/Users/anna"),
                                              temporary: URL(fileURLWithPath: "/tmp"),
                                              underTest: false,
                                              bundleIdentifier: "com.helm.app.dev")
        XCTAssertEqual(folder.path, "/Users/anna/Library/Logs/Helm Dev")
        XCTAssertNotEqual(folder.path, "/Users/anna/Library/Logs/Helm")
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
    /// Asserting that the marker is absent passes for free when nothing was
    /// written at all, so the line is proven to exist first — in the tail, which
    /// is filled from the same parts the file line is spelled from. The file's
    /// size and date are not compared: a Helm or Helm Dev running on the same Mac
    /// writes that file and would turn the test red with no defect.
    func testAnErrorLoggedByATestDoesNotReachTheFileWeTriage() {
        let marker = "log destination guard \(UUID().uuidString)"

        HelmLog.shared.setEnabled(true)
        HelmLog.shared.error("engine", marker)
        // `recentEntries` takes the log's own queue, so it returns once the
        // write has run rather than once it was scheduled.
        let entries = HelmLog.shared.recentEntries()

        XCTAssertTrue(entries.contains { $0.message == marker },
                      "nothing was logged, so nothing below is a test of anything")
        if let text = try? String(contentsOf: shippingLog, encoding: .utf8) {
            XCTAssertFalse(text.contains(marker),
                           "a test's own error text is in the file people triage")
        }
    }
}
