import XCTest
@testable import HelmRuntime

/// `NSWorkspace.runningApplications` is main-thread-only, and Helm's VPN engine
/// read it from its own serial queue for four releases. It crashed the process
/// the first time an app quit while the engine happened to be looking —
/// `EXC_BAD_ACCESS` inside `_cow_copy`, with the main thread mutating the same
/// array. These cover the rule that replaced it: off the main thread, answer
/// from the snapshot and do not touch AppKit at all.
final class RunningAppsTests: XCTestCase {

    func testABackgroundReadAnswersFromTheSnapshot() {
        let apps = RunningApps.shared
        apps.seed(["com.apple.Safari", "com.helm.app"])

        let read = expectation(description: "read off the main thread")
        var seen: Set<String> = []
        DispatchQueue.global().async {
            seen = apps.bundleIDs()
            read.fulfill()
        }
        wait(for: [read], timeout: 2)
        XCTAssertEqual(seen, ["com.apple.Safari", "com.helm.app"])
    }

    func testManyBackgroundReadersAgainstAWriterDoNotTear() {
        let apps = RunningApps.shared
        apps.seed(["a"])
        let done = expectation(description: "readers finished")
        done.expectedFulfillmentCount = 16

        for index in 0..<16 {
            DispatchQueue.global().async {
                // Interleaved with writes: the set must always be one of the
                // whole values written, never a half-built one.
                for _ in 0..<200 {
                    let ids = apps.bundleIDs()
                    XCTAssertTrue(ids == ["a"] || ids == ["a", "b"], "\(ids)")
                }
                done.fulfill()
                _ = index
            }
        }
        for _ in 0..<400 {
            apps.seed(["a", "b"])
            apps.seed(["a"])
        }
        wait(for: [done], timeout: 10)
    }

    func testAnEmptySnapshotIsDistinguishableFromNothingRunning() {
        // A background caller before the first refresh gets an empty set. That
        // is indistinguishable from "no apps are running" by value, so the flag
        // is how a caller that cares can tell.
        let apps = RunningApps.shared
        apps.seed([])
        XCTAssertTrue(apps.hasSnapshot)
        // Read off the main thread: on it, `bundleIDs()` refreshes from AppKit
        // and would answer with every process on this Mac.
        let read = expectation(description: "read off the main thread")
        var seen: Set<String> = ["not read"]
        DispatchQueue.global().async {
            seen = apps.bundleIDs()
            read.fulfill()
        }
        wait(for: [read], timeout: 2)
        XCTAssertEqual(seen, [])
    }

    /// The main thread reads the live list, so a main-thread read is allowed to
    /// disagree with the snapshot — it refreshes it. What it must never do is
    /// return something the process did not build.
    func testAMainThreadReadRefreshesTheSnapshot() {
        let apps = RunningApps.shared
        apps.seed(["stale"])
        let live = apps.bundleIDs()   // on the main thread, in a test
        XCTAssertFalse(live.contains("stale"), "the snapshot was returned instead of refreshed")
        XCTAssertTrue(apps.hasSnapshot)
    }
}
