import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import Module_Homebrew_UI
import Module_KeepAwake_UI
import Module_Layout_UI
import Module_Screenshots_UI
import Module_VPN_UI

/// Switching a module off must give its transport subscriber back.
///
/// The host holds each module's model and the descriptor's `stop(_:)` ends its
/// one event task. Whether that is enough is not a question `stop(_:)` answers:
/// the model's event loop is a `Task` over `LocalTransport.events`, the stream
/// nothing ever calls `finish()` on, and the *only* thing that prunes
/// `subscribers` is `continuation.onTermination` — which fires when that task is
/// cancelled. So this asks the real descriptor of every module whose model holds such a task for its real
/// parts, stops the model the way `ModuleHost` does, and reads the count that a
/// leak makes climb.
///
/// **The count is asserted at 1 before it is asserted at 0.** A subscriber that
/// never registered would pass an assertion about its absence, which is the
/// vacuous shape CLAUDE.md names: assert first that the thing happened. That
/// alone was not enough — the subscriber registers before the loop that consumes
/// it runs at all, so the gate stood open on a module that had not started;
/// `letTheLoopStart()` below has the measurement.
@MainActor
final class ASwitchedOffModuleLetsItsSubscriberGoTests: XCTestCase {

    /// Keep Awake: the host holds the model and the descriptor's `stop(_:)` ends
    /// its one event task.
    ///
    /// The count is asserted at 1 first, for the reason given above, and the
    /// task is given its turn to park on the stream before it is cancelled.
    func testKeepAwakeGivesItsSubscriberBackWhenTheHostStopsItsModel() async throws {
        let descriptor = KeepAwakeDescriptor()
        let parts = descriptor.makeModule(store: NamespacedStore(
            namespace: "test.keepawake.subscriber", backing: InMemoryKeyValueStore()))
        let transport = try XCTUnwrap(parts.engine.transport as? LocalTransport)
        await settle(transport, until: 1)
        XCTAssertEqual(transport.subscriberCount, 1,
                       "the model never subscribed, so the count below would pass on nothing")
        await letTheLoopStart()

        descriptor.stop(parts.model)
        await settle(transport, until: 0)

        XCTAssertEqual(transport.subscriberCount, 0,
                       "`stop(_:)` left the engine's subscriber behind: the model's task was not cancelled")
    }

    /// Layout is built like Keep Awake: the host holds the model, `stop(_:)` ends
    /// its one event task. The engine is built, never activated, so nothing here
    /// reaches the keyboard.
    func testLayoutGivesItsSubscriberBackWhenTheHostStopsItsModel() async throws {
        let descriptor = LayoutDescriptor()
        let parts = descriptor.makeModule(store: NamespacedStore(
            namespace: "test.layout.subscriber", backing: InMemoryKeyValueStore()))
        let transport = try XCTUnwrap(parts.engine.transport as? LocalTransport)
        await settle(transport, until: 1)
        XCTAssertEqual(transport.subscriberCount, 1,
                       "the model never subscribed, so the count below would pass on nothing")
        await letTheLoopStart()

        descriptor.stop(parts.model)
        await settle(transport, until: 0)

        XCTAssertEqual(transport.subscriberCount, 0,
                       "`stop(_:)` left the engine's subscriber behind: the model's task was not cancelled")
    }

    /// Screenshots is built like Layout: the host holds the model, `stop(_:)` ends its one event task. The engine is
    /// built, never activated, so nothing here reads a preference or the disk and no capture is made.
    func testScreenshotsGivesItsSubscriberBackWhenTheHostStopsItsModel() async throws {
        let descriptor = ScreenshotsDescriptor()
        let parts = descriptor.makeModule(store: NamespacedStore(
            namespace: "test.screenshots.subscriber", backing: InMemoryKeyValueStore()))
        let transport = try XCTUnwrap(parts.engine.transport as? LocalTransport)
        await settle(transport, until: 1)
        XCTAssertEqual(transport.subscriberCount, 1,
                       "the model never subscribed, so the count below would pass on nothing")
        await letTheLoopStart()

        descriptor.stop(parts.model)
        await settle(transport, until: 0)

        XCTAssertEqual(transport.subscriberCount, 0,
                       "`stop(_:)` left the engine's subscriber behind: the model's task was not cancelled")
    }

    /// Homebrew is built like Keep Awake: the host holds the model, `stop(_:)`
    /// ends its one event task. The engine is built, never activated, so nothing
    /// here reaches `brew` or the network.
    func testHomebrewGivesItsSubscriberBackWhenTheHostStopsItsModel() async throws {
        let descriptor = HomebrewDescriptor()
        let parts = descriptor.makeModule(store: NamespacedStore(
            namespace: "test.homebrew.subscriber", backing: InMemoryKeyValueStore()))
        let transport = try XCTUnwrap(parts.engine.transport as? LocalTransport)
        await settle(transport, until: 1)
        XCTAssertEqual(transport.subscriberCount, 1,
                       "the model never subscribed, so the count below would pass on nothing")
        await letTheLoopStart()

        descriptor.stop(parts.model)
        await settle(transport, until: 0)

        XCTAssertEqual(transport.subscriberCount, 0,
                       "`stop(_:)` left the engine's subscriber behind: the model's task was not cancelled")
    }

    /// VPN is built like Keep Awake: the host holds the model, `stop(_:)` ends
    /// its one event task. The engine is built, never activated, so nothing here
    /// reaches the network.
    func testVPNGivesItsSubscriberBackWhenTheHostStopsItsModel() async throws {
        let descriptor = VPNDescriptor()
        let parts = descriptor.makeModule(store: NamespacedStore(
            namespace: "test.vpn.subscriber", backing: InMemoryKeyValueStore()))
        let transport = try XCTUnwrap(parts.engine.transport as? LocalTransport)
        await settle(transport, until: 1)
        XCTAssertEqual(transport.subscriberCount, 1,
                       "the model never subscribed, so the count below would pass on nothing")
        await letTheLoopStart()

        descriptor.stop(parts.model)
        await settle(transport, until: 0)

        XCTAssertEqual(transport.subscriberCount, 0,
                       "`stop(_:)` left the engine's subscriber behind: the model's task was not cancelled")
    }

    // MARK: - Waiting

    /// Lets the event loop actually start and park on its stream.
    ///
    /// **Not a courtesy wait — without it this check cannot see half the defect
    /// it exists for.** `LocalTransport.events` registers its continuation
    /// inside `AsyncStream`'s builder, which runs the moment `init` touches the
    /// property — so the subscriber is there *before* the task that consumes it
    /// has run a single line. A gate that waits for the count to reach 1 is
    /// therefore already open at `init`, and a view model written as
    /// `Task { [weak self] in await self?.observeEvents(events) }` would be
    /// dropped before its task first ran: `self?` resolves to nil, no strong
    /// reference is ever taken, and the module looks clean. Measured — that
    /// mutation passed three runs in a row until this wait was added. The
    /// retain only exists once the loop is inside the call, which is the state a
    /// page open for a moment is always in.
    ///
    /// Sleeping rather than yielding: the loop starts on the concurrency pool,
    /// and yielding from the main actor hands the turn to main-actor work.
    private func letTheLoopStart() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Waits for the count, rather than yielding a fixed number of times.
    ///
    /// `Task.sleep` and not `Task.yield`: the drop closure is registered on
    /// `OperationQueue.main`, so the notification is delivered by the main queue
    /// rather than by the concurrency pool, and a loop that only yields to other
    /// tasks can spin without the main queue ever getting a turn. Returning
    /// early is safe — the assertion is at the call site, so a wait that gives
    /// up reports the count it actually saw.
    private func settle(_ transport: LocalTransport, until count: Int) async {
        for _ in 0..<400 {
            if transport.subscriberCount == count { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
