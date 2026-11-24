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
/// The model's event loop is a `Task` over `EngineNews.stream()`, a stream
/// nothing calls `finish()` on, and the only thing that prunes `subscribers` is
/// `continuation.onTermination`, which fires when that task is cancelled. So
/// this asks the real descriptor of every module whose model holds such a task
/// for its real parts, stops the model the way `ModuleHost` does, and reads the
/// count that a leak makes climb.
///
/// **The count is asserted at 1 before it is asserted at 0**, or an absence
/// proves nothing (Architecture/TestsAndMeasurement.md § What makes a check).
/// The subscriber registers before its loop runs, so the loop is also given
/// its turn (`letTheLoopStart()`).
@MainActor
final class ASwitchedOffModuleLetsItsSubscriberGoTests: XCTestCase {

    /// Keep Awake: the host holds the model and the descriptor's `stop(_:)` ends
    /// its one event task.
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
        await waitUntil("1 subscriber(s)", within: .seconds(2)) { live.subscriberCount == 1 }
        XCTAssertEqual(live.subscriberCount, 1,
                       "the model never subscribed, so the count below would pass on nothing", file: file, line: line)
        await letTheLoopStart()

        descriptor.stop(parts.model)
        await waitUntil("0 subscriber(s)", within: .seconds(2)) { live.subscriberCount == 0 }

        XCTAssertEqual(live.subscriberCount, 0,
                       "`stop(_:)` left the engine's subscriber behind: the model's task was not cancelled",
                       file: file, line: line)
    }

    // MARK: - Waiting

    /// Lets the event loop actually start and park on its stream.
    ///
    /// **Not a courtesy wait.** `EngineNews.stream()` registers its
    /// continuation inside `AsyncStream`'s builder, so the subscriber is there
    /// before the task that consumes it has run a line, and the gate at 1 is
    /// already open at `init`. A model written as
    /// `Task { [weak self] in await self?.observeEvents(events) }` would then be
    /// dropped before its task ran (`self?` is nil, no strong reference is
    /// taken) and look clean. The retain exists only once the loop is inside
    /// the call, the state a page open for a moment is always in.
    ///
    /// A sleep rather than a yield: the loop starts on the concurrency pool,
    /// and yielding from the main actor hands the turn to main-actor work.
    private func letTheLoopStart() async {
        await grace()
    }
}
