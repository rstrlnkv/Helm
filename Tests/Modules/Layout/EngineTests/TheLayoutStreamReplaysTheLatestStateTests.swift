import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_Layout_Engine

/// `LayoutEngine.stream()` hands a subscriber that arrives late the state it
/// missed, then every later one in order, and gives the subscription back when
/// the reader stops.
///
/// Defect class kept: a level-triggered state read through a stream the model
/// takes after `activate()`. The model is built when the module starts and the
/// engine has already published; a stream that replays nothing leaves the page
/// drawing the initial «not watching» until the next change, and a subscriber
/// that is never given back outlives the model that made it (the news
/// keeps writing into a stream nobody reads). The engine runs its own
/// `EngineNews<LayoutState>`, passed in, so the count of subscribers is the engine's.
@MainActor
final class TheLayoutStreamReplaysTheLatestStateTests: XCTestCase {

    private func engine(_ tap: FakeTap, news: EngineNews<LayoutState>) -> LayoutEngine {
        LayoutEngine(tap: tap, typing: FakeTyping(), sources: FakeSources(),
                     translation: FakeTranslation(table: [:]), spell: FakeSpell(valid: []),
                     secure: FakeSecure(), activation: FakeActivation(),
                     settings: NamespacedStore(namespace: LayoutEngine.moduleID,
                                               backing: InMemoryKeyValueStore()),
                     news: news)
    }

    /// Everything one reader was handed, in order.
    private final class Reader: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [LayoutState] = []
        private(set) var task: Task<Void, Never>?
        var states: [LayoutState] { lock.withLock { seen } }
        init(_ stream: AsyncStream<LayoutState>) {
            task = Task { [self] in
                for await state in stream { lock.withLock { seen.append(state) } }
            }
        }
    }

    func testASubscriberAfterActivationIsHandedTheStateItMissed() async {
        let tap = FakeTap()
        let engine = engine(tap, news: EngineNews())
        engine.activate()
        XCTAssertEqual(tap.starts, 1, "the tap never started, so nothing below is about a replay")

        let reader = Reader(engine.stream())
        await waitUntil("the missed state is replayed") { !reader.states.isEmpty }
        XCTAssertEqual(reader.states.first?.enabled, true,
                       "the late subscriber was not told the module is watching")
        reader.task?.cancel()
        engine.deactivate()
    }

    func testLaterStatesArriveInOrder() async {
        let tap = FakeTap()
        let engine = engine(tap, news: EngineNews())
        engine.activate()
        let reader = Reader(engine.stream())
        await waitUntil("the replay") { !reader.states.isEmpty }

        tap.macOSTakesItAway()
        await waitUntil("the state after macOS took the tap") { reader.states.last?.enabled == false }

        let enabled = reader.states.map(\.enabled)
        XCTAssertEqual(enabled.first, true, "the replay did not come first")
        XCTAssertEqual(enabled.last, false, "the later state did not come after it")
        // Order, not values: once the module is not watching, no older «watching»
        // state is delivered behind it.
        if let firstOff = enabled.firstIndex(of: false) {
            XCTAssertFalse(enabled[firstOff...].contains(true),
                           "an older state arrived after a newer one: \(enabled)")
        }
        reader.task?.cancel()
        engine.deactivate()
    }

    func testEndingTheIterationGivesTheSubscriberBack() async {
        let news = EngineNews<LayoutState>()
        let engine = engine(FakeTap(), news: news)
        engine.activate()
        XCTAssertEqual(news.subscriberCount, 0, "precondition: nobody has subscribed")

        let reader = Reader(engine.stream())
        await waitUntil("the stream registers") { news.subscriberCount == 1 }
        reader.task?.cancel()
        await waitUntil("the stream is given back") { news.subscriberCount == 0 }
        engine.deactivate()
    }
}
