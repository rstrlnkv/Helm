import Foundation
import HelmTestSupport
import XCTest
@testable import HelmUI

/// The one helper five view models follow an engine stream through.
///
/// What it must keep: a stream taken before the first suspension loses nothing;
/// `cancel()` ends the subscription and an element already buffered is not
/// applied after it; a model dropped without `cancel()` is released and takes
/// the subscription with it (no cycle, `deinit` as the backstop).
@MainActor
final class StreamFollowerTests: XCTestCase {

    private final class Owner {
        var got: [Int] = []
        var follower: StreamFollower?
    }

    private struct Feed {
        let stream: AsyncStream<Int>
        let continuation: AsyncStream<Int>.Continuation
        let terminated: Locked<Bool>
    }

    private func feed() -> Feed {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        let terminated = Locked(false)
        continuation.onTermination = { _ in terminated.value = true }
        return Feed(stream: stream, continuation: continuation, terminated: terminated)
    }

    private func follow(_ feed: Feed, _ owner: Owner) -> StreamFollower {
        StreamFollower(feed.stream, owner: owner) { $0.got.append($1) }
    }

    func testAValueYieldedBeforeAndRightAfterTheFollowerIsAppliedOnceInOrder() async {
        let f = feed()
        let owner = Owner()
        f.continuation.yield(1)
        let follower = follow(f, owner)
        f.continuation.yield(2)          // before any await: the task has not run yet
        await waitUntil("both values applied") { owner.got.count == 2 }
        f.continuation.yield(3)
        await waitUntil("a third value applied") { owner.got.count == 3 }
        XCTAssertEqual(owner.got, [1, 2, 3])
        follower.cancel()
    }

    func testCancelStopsApplyingAndGivesTheSubscriberBack() async {
        let f = feed()
        let owner = Owner()
        let follower = follow(f, owner)
        f.continuation.yield(1)
        await waitUntil("first value applied") { owner.got == [1] }
        XCTAssertFalse(f.terminated.value, "the stream is live before cancel")
        follower.cancel()
        await waitUntil("stream terminated") { f.terminated.value }
        let result = f.continuation.yield(2)
        guard case .terminated = result else { return XCTFail("yield after cancel was \(result)") }
        // Give a wrongly surviving loop its turn, then read.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(owner.got, [1])
    }

    func testAValueBufferedBeforeCancelIsNotApplied() async {
        let f = feed()
        let owner = Owner()
        let follower = follow(f, owner)
        f.continuation.yield(1)
        follower.cancel()                // synchronously, before the loop's turn
        await waitUntil("stream terminated") { f.terminated.value }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(owner.got, [], "a buffered element must not be applied after cancel()")
    }

    func testAModelDroppedWithoutCancelIsReleasedAndEndsTheStream() async {
        let f = feed()
        weak var weakOwner: Owner?
        do {
            let owner = Owner()
            weakOwner = owner
            owner.follower = follow(f, owner)   // the model holds its follower, as the view models do
            f.continuation.yield(1)
            await waitUntil("first value applied") { owner.got == [1] }
            XCTAssertFalse(f.terminated.value)
        }
        await waitUntil("owner released") { weakOwner == nil }
        await waitUntil("stream terminated with the follower") { f.terminated.value }
    }
}
