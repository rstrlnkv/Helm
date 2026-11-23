import XCTest
@testable import HelmRuntime

/// The frontmost application, readable from any thread.
///
/// `NSWorkspace` is main-thread-only, and reading it elsewhere does not return
/// stale data — it takes the process down (ARCHITECTURE.md § Running
/// applications; the doc comment of `RunningApps` holds the stack trace from the
/// VPN engine's crash). The Layout module (shown as Keyboard) then did it again:
/// `frontmostBundleID` read `NSWorkspace.shared.frontmostApplication` wherever it
/// was called, and the gesture that fixes selected text was moved onto a
/// background queue, so the first use with text selected took the process down.
///
/// Same answer as `RunningApps`: refresh on main, read the snapshot anywhere.
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
}
