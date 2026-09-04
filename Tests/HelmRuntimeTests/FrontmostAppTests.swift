import XCTest
@testable import HelmRuntime

/// The frontmost application, readable from any thread.
///
/// `NSWorkspace` is main-thread-only, and reading it elsewhere does not return
/// stale data — it takes the process down. That is written into ARCHITECTURE.md
/// because the VPN engine did it for four releases. The Keyboard module then did
/// it again: `frontmostBundleID` read `NSWorkspace.shared.frontmostApplication`
/// wherever it was called, and the gesture that fixes selected text was moved
/// onto a background queue, which made every use of it a coin toss.
///
/// Same answer as `RunningApps`: refresh on main, read the snapshot anywhere.
///
/// **The snapshot also gains a way to say it changed.** A module that wants to
/// act on an application coming forward had no way to hear about it and would
/// have added a second observer for the same notification this type already
/// owns. The channel tests below are driven through `setForTesting` rather
/// than through AppKit: they are about delivery, not about the workspace.
@MainActor
final class FrontmostAppTests: XCTestCase {

    override func tearDown() {
        FrontmostApp.shared.setForTesting("")
        super.tearDown()
    }

    func testOffTheMainThreadItReadsTheSnapshotAndNeverAppKit() {
        let expectation = expectation(description: "read off main")
        FrontmostApp.shared.setForTesting("com.example.one")
        DispatchQueue.global().async {
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(FrontmostApp.shared.bundleID(), "com.example.one")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    /// Off the main thread it is the snapshot and nothing else — the point of
    /// the type. On the main thread it deliberately reads live, so these have
    /// to ask from somewhere else to see what was stored.
    func testOffMainItIsWhateverWasLastStored() {
        for value in ["com.example.two", "com.example.three", ""] {
            FrontmostApp.shared.setForTesting(value)
            let read = expectation(description: "read \(value)")
            DispatchQueue.global().async {
                XCTAssertEqual(FrontmostApp.shared.bundleID(), value)
                read.fulfill()
            }
            wait(for: [read], timeout: 2)
        }
    }

    /// On the main thread it answers from AppKit, which is the only thread
    /// allowed to ask. Whatever it returns, it must not be the stale value the
    /// snapshot was seeded with.
    func testOnMainItReadsLiveRatherThanTheSnapshot() {
        FrontmostApp.shared.setForTesting("com.example.stale")
        XCTAssertNotEqual(FrontmostApp.shared.bundleID(), "com.example.stale")
    }

    func testAWatcherHearsTheChange() {
        var heard: [String] = []
        let token = FrontmostApp.shared.onChange { heard.append($0) }
        defer { FrontmostApp.shared.stopWatching(token) }

        FrontmostApp.shared.setForTesting("ru.keepcoder.Telegram")
        XCTAssertEqual(heard, ["ru.keepcoder.Telegram"])
    }

    /// The same application twice is not a change. Without this the module
    /// would ask for a layout selection every time the person came back to a
    /// window they were already in.
    func testTheSameApplicationTwiceIsSaidOnce() {
        var heard: [String] = []
        let token = FrontmostApp.shared.onChange { heard.append($0) }
        defer { FrontmostApp.shared.stopWatching(token) }

        FrontmostApp.shared.setForTesting("com.apple.Safari")
        FrontmostApp.shared.setForTesting("com.apple.Safari")
        XCTAssertEqual(heard, ["com.apple.Safari"])
    }

    /// A watcher that has stopped hears nothing — the half a `deinit` depends
    /// on, and the half that is usually missing.
    func testAStoppedWatcherHearsNothing() {
        var heard: [String] = []
        let token = FrontmostApp.shared.onChange { heard.append($0) }
        FrontmostApp.shared.stopWatching(token)

        FrontmostApp.shared.setForTesting("com.apple.Safari")
        XCTAssertTrue(heard.isEmpty)
    }

    func testTwoWatchersBothHear() {
        var first: [String] = []
        var second: [String] = []
        let a = FrontmostApp.shared.onChange { first.append($0) }
        let b = FrontmostApp.shared.onChange { second.append($0) }
        defer { FrontmostApp.shared.stopWatching(a); FrontmostApp.shared.stopWatching(b) }

        FrontmostApp.shared.setForTesting("com.apple.Terminal")
        XCTAssertEqual(first, ["com.apple.Terminal"])
        XCTAssertEqual(second, ["com.apple.Terminal"])
    }
}
