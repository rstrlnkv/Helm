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

/// Switching a module off must give its news subscriber back.
///
/// The host holds each module's model and the descriptor's `stop(_:)` ends its
/// one event task. Whether that is enough is not a question `stop(_:)` answers:
/// the model's event loop is a `Task` over `EngineNews.stream()`, the stream
/// nothing ever calls `finish()` on, and the *only* thing that prunes
/// `subscribers` is `continuation.onTermination` — which fires when that task is
/// cancelled. So this asks the real descriptor of every module whose model holds such a task for its real
/// parts, stops the model the way `ModuleHost` does, and reads the count that a
/// leak makes climb.
///
/// **The count is asserted at 1 before it is asserted at 0.** A subscriber that
/// never registered would pass an assertion about its absence, which is the
/// vacuous shape (ARCHITECTURE.md § What makes a check) names: assert first that the thing happened. That
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
        await assertStopGivesItsSubscriberBack(KeepAwakeDescriptor())
    }

    /// Layout is built like Keep Awake: the host holds the model, `stop(_:)` ends
    /// its one event task. The engine is built, never activated, so nothing here
    /// reaches the keyboard.
    func testLayoutGivesItsSubscriberBackWhenTheHostStopsItsModel() async throws {
        await assertStopGivesItsSubscriberBack(LayoutDescriptor())
    }

    /// Screenshots is built like Layout: the host holds the model, `stop(_:)` ends its one event task. The engine is
    /// built, never activated, so nothing here reads a preference or the disk and no capture is made.
    func testScreenshotsGivesItsSubscriberBackWhenTheHostStopsItsModel() async throws {
        await assertStopGivesItsSubscriberBack(ScreenshotsDescriptor())
    }

    /// Homebrew is built like Keep Awake: the host holds the model, `stop(_:)`
    /// ends its one event task. The engine is built, never activated, so nothing
    /// here reaches `brew` or the network.
    func testHomebrewGivesItsSubscriberBackWhenTheHostStopsItsModel() async throws {
        await assertStopGivesItsSubscriberBack(HomebrewDescriptor())
    }

    /// VPN is built like Keep Awake: the host holds the model, `stop(_:)` ends
    /// its one event task. The engine is built, never activated, so nothing here
    /// reaches the network.
    func testVPNGivesItsSubscriberBackWhenTheHostStopsItsModel() async throws {
        await assertStopGivesItsSubscriberBack(VPNDescriptor())
    }

    /// The body of every module's test: the count is asserted at 1 first, for the reason in the class comment,
    /// and the task is given its turn to park on the stream before it is cancelled.
    private func assertStopGivesItsSubscriberBack<D: ModuleDescriptor>(
        _ descriptor: D, file: StaticString = #filePath, line: UInt = #line) async {
        let parts = descriptor.makeModule(store: NamespacedStore(
            namespace: "test.\(D.id.rawValue).subscriber", backing: InMemoryKeyValueStore()))
        let live = parts.engine
        await settle(live, until: 1)
        XCTAssertEqual(live.subscriberCount, 1,
                       "the model never subscribed, so the count below would pass on nothing", file: file, line: line)
        await letTheLoopStart()

        descriptor.stop(parts.model)
        await settle(live, until: 0)

        XCTAssertEqual(live.subscriberCount, 0,
                       "`stop(_:)` left the engine's subscriber behind: the model's task was not cancelled",
                       file: file, line: line)
    }

    // MARK: - Waiting

    /// Lets the event loop actually start and park on its stream.
    ///
    /// **Not a courtesy wait — without it this check cannot see half the defect
    /// it exists for.** `EngineNews.stream()` registers its continuation
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
    /// A sleep rather than a yield: the loop starts on the concurrency pool,
    /// and yielding from the main actor hands the turn to main-actor work.
    private func letTheLoopStart() async {
        await grace()
    }

    /// Waits for the count, on the clock; the drop closure is registered on
    /// `OperationQueue.main`, so the notification is delivered by the main queue
    /// rather than by the concurrency pool, and a sleep between reads is what
    /// gives that queue its turn.
    private func settle(_ engine: any ModuleEngine, until count: Int) async {
        await waitUntil("\(count) subscriber(s)", within: .seconds(2)) { engine.subscriberCount == count }
    }
}
