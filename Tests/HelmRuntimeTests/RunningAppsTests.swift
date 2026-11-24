import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// `NSWorkspace.runningApplications` is main-thread-only: read from another
/// queue while an app quits, it crashes inside `_cow_copy` with the main thread
/// mutating the same array. Off the main thread, `RunningApps` answers from the
/// snapshot and does not touch AppKit at all.
final class RunningAppsTests: XCTestCase {

    func testABackgroundReadAnswersFromTheSnapshot() {
        let apps = RunningApps.shared
        apps.seed(["com.apple.Safari", "com.helm.app"])

        let read = expectation(description: "read off the main thread")
        let seen = Locked<Set<String>>([])
        DispatchQueue.global().async {
            seen.value = apps.bundleIDs()
            read.fulfill()
        }
        wait(for: [read], timeout: 2)
        XCTAssertEqual(seen.value, ["com.apple.Safari", "com.helm.app"])
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
        let seen = Locked<Set<String>>(["not read"])
        DispatchQueue.global().async {
            seen.value = apps.bundleIDs()
            read.fulfill()
        }
        wait(for: [read], timeout: 2)
        XCTAssertEqual(seen.value, [])
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

    /// The order the VPN engine's observer leans on: `refreshOnMain` from a
    /// background queue hops to the main thread, refreshes, and only then runs
    /// the completion — so the engine's queue, woken by that completion, reads
    /// a snapshot the refresh already replaced. Completion-before-refresh
    /// would hand it the stale seed and re-open the very window the KVO
    /// handler exists to close.
    func testRefreshOnMainRunsTheCompletionAfterTheRefresh() {
        let apps = RunningApps.shared
        apps.seed(["stale.sentinel"])
        let done = expectation(description: "completion ran")
        // A locked box rather than a captured var: the reads happen on a
        // detached thread and Swift 6 rightly refuses the bare capture.
        let atCompletion = Locked<Set<String>>(["not read"])
        DispatchQueue.global().async {
            apps.refreshOnMain {
                // Read as the engine reads, through the snapshot, off the
                // main thread: `bundleIDs()` on main would refresh a second
                // time and hide a mis-ordering, and `global().sync` may run
                // on the calling thread. A detached thread is never main, and
                // waiting for it here holds main, so a refresh ordered after
                // the completion cannot slip in first.
                let readDone = DispatchSemaphore(value: 0)
                Thread.detachNewThread {
                    atCompletion.value = apps.bundleIDs()
                    readDone.signal()
                }
                readDone.wait()
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
        XCTAssertFalse(atCompletion.value.contains("stale.sentinel"),
                       "the completion observed the seed the refresh should have replaced")
    }
}
