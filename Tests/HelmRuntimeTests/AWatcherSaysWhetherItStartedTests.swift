import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// `FolderWatcher.start` threw away `FSEventStreamStart`'s return and returned
/// silently when `FSEventStreamCreate` answered nil, so two engines logged that
/// they were watching a folder with nothing to say whether they were.
///
/// The answer arrives on the watcher's own queue rather than as a return value,
/// and that is deliberate: `watch` hands its work to that queue, where the change
/// callbacks it delivers also run — and one of those can take as long as
/// Autopilot's `folders` getter, which reads a keychain item. A `queue.sync` here
/// would park whoever asked, up to and including the thread that draws, waiting
/// for a change notification to finish.
final class AWatcherSaysWhetherItStartedTests: XCTestCase {

    /// The answer, waited for rather than assumed: it comes back on the watcher's
    /// queue. Nil if it never came, which is a different failure from `false`.
    private func started(_ watcher: FolderWatcher, _ folders: [String]) -> Bool? {
        let arrived = expectation(description: "the watcher said whether it started")
        let box = Box()
        watcher.watch(folders) { ok in
            box.value = ok
            arrived.fulfill()
        }
        guard XCTWaiter.wait(for: [arrived], timeout: 5) == .completed else { return nil }
        return box.value
    }

    private final class Box: @unchecked Sendable { var value: Bool? }

    /// A real directory: an FSEvents stream over one is what the engines build.
    func testAWatcherOnARealFolderSaysItStarted() throws {
        let root = scratchDirectory("watcher-started")
        let watcher = FolderWatcher { _ in }
        defer { watcher.stop() }

        XCTAssertEqual(started(watcher, [root.path]), true,
                       "a stream over a real folder reported that it never started")
    }

    /// And watching nothing is not watching. `watch([])` is what both engines
    /// reach when their folder list is empty, and it used to be indistinguishable
    /// from a stream that was running.
    func testAWatcherWithNoFoldersSaysItIsNotWatching() throws {
        let watcher = FolderWatcher { _ in }
        defer { watcher.stop() }

        XCTAssertEqual(started(watcher, []), false,
                       "a watcher with nothing to watch reported itself as started")
    }

    /// Replacing the folders answers again, so the flag a caller keeps is a
    /// reading of the stream that exists now — not of the first one it built.
    func testEachCallAnswersForItself() throws {
        let root = scratchDirectory("watcher-again")
        let watcher = FolderWatcher { _ in }
        defer { watcher.stop() }

        XCTAssertEqual(started(watcher, [root.path]), true, "precondition: the first one started")
        XCTAssertEqual(started(watcher, []), false,
                       "the second call left the caller believing the first stream's answer")
        XCTAssertEqual(started(watcher, [root.path]), true, "and it can start again")
    }
}
