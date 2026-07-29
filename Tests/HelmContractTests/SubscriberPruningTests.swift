import XCTest
@testable import HelmContract

/// A subscriber that nobody can reach must not stay registered.
///
/// `LocalTransport` prunes `subscribers` only from `continuation.onTermination`,
/// which fires when the consuming task is cancelled or the stream finishes —
/// and the stream never finishes, because nothing calls `finish()`. So the
/// question "does a torn-down page leave a subscriber behind" is answered by
/// whether the consuming task ends, and by nothing else.
///
/// The regression guard the memory hunt asked for is a **count that must not
/// grow**, not a memory figure: a footprint is too noisy to assert on, and the
/// last leak was found by watching a number climb rather than by reading code.
final class SubscriberPruningTests: XCTestCase {
    /// The shape every view model uses: hold the stream, re-acquire `self`
    /// per event, and leave the loop when the owner is gone.
    func testACancelledConsumerIsUnregistered() async {
        let transport = LocalTransport()
        XCTAssertEqual(transport.subscriberCount, 0)

        let events = transport.events
        let task = Task { for await _ in events {} }
        // Give the stream a moment to register its continuation.
        for _ in 0..<50 where transport.subscriberCount == 0 { await Task.yield() }
        XCTAssertEqual(transport.subscriberCount, 1, "the consumer did not register")

        task.cancel()
        _ = await task.value
        for _ in 0..<50 where transport.subscriberCount == 1 { await Task.yield() }

        XCTAssertEqual(transport.subscriberCount, 0,
                       "a cancelled consumer left its continuation registered — every rebuilt "
                       + "module page would then add one more subscriber for the life of the app")
    }

    /// Settings tears a module's page down and rebuilds it on every sidebar
    /// visit. Twenty visits must not leave twenty subscribers.
    func testRepeatedPageBuildsDoNotAccumulateSubscribers() async {
        let transport = LocalTransport()

        for _ in 0..<20 {
            let events = transport.events
            let task = Task { for await _ in events {} }
            for _ in 0..<50 where transport.subscriberCount == 0 { await Task.yield() }
            task.cancel()
            _ = await task.value
            for _ in 0..<50 where transport.subscriberCount > 0 { await Task.yield() }
        }

        XCTAssertEqual(transport.subscriberCount, 0,
                       "subscribers accumulated across page rebuilds — this is the shape that "
                       + "grows with page switches and with event volume")
    }
}
