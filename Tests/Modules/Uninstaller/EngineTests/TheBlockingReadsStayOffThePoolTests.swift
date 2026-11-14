import XCTest
@testable import Module_Uninstaller_Engine

/// **The hop to `offTheCooperativePool` is seen only from the thread that makes
/// the call.**
///
/// `waitUntilGone` polls the running list and the force quit asks AppKit to
/// terminate: both are blocking AppKit reads, and both were moved behind
/// `offTheCooperativePool` (ARCHITECTURE.md § Running applications). Nothing in a
/// result shows that — an engine that calls them on the pool returns the same
/// values — so the fake records the label of the queue it was called on. The
/// global queue `offTheCooperativePool` uses is `com.apple.root.user-initiated-qos`;
/// a call made on the pool says `...cooperative`.
final class TheBlockingReadsStayOffThePoolTests: XCTestCase {

    /// Every call, with the label of the queue it arrived on.
    private final class Recording: RunningAppsPort, @unchecked Sendable {
        private let lock = NSLock()
        private var up: Bool
        private(set) var calls: [(what: String, queue: String)] = []
        private var polls = 0
        init(up: Bool) { self.up = up }

        func isRunning(bundleID: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            calls.append(("isRunning", String(cString: __dispatch_queue_get_label(nil))))
            polls += 1
            // Gone after a few polls, so the wait has something to poll for.
            if polls > 3 { up = false }
            return up
        }

        func quit(bundleID: String, force: Bool) {
            lock.lock(); defer { lock.unlock() }
            calls.append(("quit", String(cString: __dispatch_queue_get_label(nil))))
        }
    }

    private func assertAllHopped(_ rec: Recording, _ what: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(rec.calls.isEmpty, "precondition: the port was asked", file: file, line: line)
        for call in rec.calls {
            XCTAssertEqual(call.queue, "com.apple.root.user-initiated-qos",
                           "\(what): \(call.what) ran on the caller's own thread, not behind "
                           + "offTheCooperativePool", file: file, line: line)
        }
    }

    private func engine(_ rec: Recording, home: URL) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: FakeApps(), fs: FakeFS(existing: [:]),
                          trash: FakeTrash(), running: rec)
    }

    func testEveryPollOfTheWaitIsAskedOffThePool() async {
        let rec = Recording(up: true)
        let engine = engine(rec, home: URL(fileURLWithPath: NSTemporaryDirectory()))

        await Task.detached {
            await engine.waitUntilGone(bundleID: "com.acme.editor", deadline: 5, poll: 0.01)
        }.value

        XCTAssertGreaterThan(rec.calls.count, 1, "precondition: the wait polled more than once")
        assertAllHopped(rec, "waitUntilGone")
    }

    func testTheForceQuitOfABatchIsAskedOffThePool() async throws {
        let home = scratchDirectory("offpool")
        let app = home.appendingPathComponent("Applications/Editor.app")
        _ = try write("Applications/Editor.app/Contents/MacOS/Editor", in: home, bytes: 64)
        try (["CFBundleIdentifier": "com.acme.editor"] as NSDictionary)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let rec = Recording(up: true)
        let engine = engine(rec, home: home)

        _ = await Task.detached {
            await engine.trashPaths([app.path], quittingRunningApps: true)
        }.value

        XCTAssertTrue(rec.calls.contains { $0.what == "quit" }, "precondition: the app was force quit")
        assertAllHopped(rec, "trashPaths")
    }
}
