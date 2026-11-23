import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// The real catalog over a real folder: an app arriving is heard once the watch is held, and nothing is heard after the token is dropped.
final class ACatalogWatchLetsGoWhenDroppedTests: XCTestCase {
    /// By a child process: the folder watcher ignores this process's own writes, and an app arriving is somebody else's.
    private func makeApp(_ name: String, in root: URL) throws {
        let made = try runChild("/bin/mkdir", ["-p", root.appendingPathComponent("\(name).app/Contents").path])
        XCTAssertEqual(made.status, 0, made.errors)
    }

    func testAWatchHearsAnAppArriveAndHearsNothingAfterItIsDropped() async throws {
        let root = scratchDirectory("watch")
        let heard = LockedCount()
        var token: AnyObject? = FileSystemAppCatalog(roots: [root]).observeChanges { heard.bump() }
        // The stream starts on its own queue: an app made before it runs is not an event.
        try await Task.sleep(for: .milliseconds(500))
        try makeApp("First", in: root)
        await waitUntilWithin("a change heard while the token is held", .seconds(8)) { heard.value > 0 }
        token = nil
        // The stop is queued behind the stream's callbacks; let it run, then count from here.
        try await Task.sleep(for: .seconds(1.5))
        let before = heard.value
        try makeApp("Second", in: root)
        await grace(2.5)
        XCTAssertEqual(heard.value, before, "a dropped token still called")
        _ = token
    }
}
