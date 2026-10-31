import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The engine's `stream()` carries the state the page draws: the last one first, every later one in order, nothing
/// after the module is off, and the subscriber goes when the consumer does.**
///
/// A state is told from the one before it by the save folder: the preferences answer nothing (the Desktop) and then
/// a number (a refused folder), so an order that came out reversed or a replay that skipped a state is a different list.
final class TheScreenshotsStreamCarriesTheStateTests: XCTestCase {

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var states: [ScreenshotsState] = []
        var all: [ScreenshotsState] { lock.withLock { states } }
        func add(_ state: ScreenshotsState) { lock.withLock { states.append(state) } }
    }

    private func engine(_ name: String, _ preferences: FakePreferences) -> (ScreenshotsEngine, EngineNews<ScreenshotsState>) {
        let home = scratchDirectory(name)
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let news = EngineNews<ScreenshotsState>()
        return (ScreenshotsEngine(preferences: preferences, locations: ScreenshotsLocations(home: home, desktop: desktop),
                                  news: news), news)
    }

    private func collect(_ engine: ScreenshotsEngine, into sink: Collected) -> Task<Void, Never> {
        let stream = engine.stream()
        return Task { for await state in stream { sink.add(state) } }
    }

    @MainActor
    func testTheLastStateComesFirstAndLaterOnesInOrder() async throws {
        let preferences = FakePreferences()
        let (engine, _) = engine("shots-stream-order", preferences)
        let early = Collected(), late = Collected()
        let earlyTask = collect(engine, into: early)
        await grace(0.2)
        XCTAssertTrue(early.all.isEmpty, "the control: nothing is said before the engine reads")

        engine.activate()
        await waitUntil("the first reading reached an early subscriber") { early.all.count == 1 }
        let first = try XCTUnwrap(early.all.first, "the early subscriber heard nothing")
        XCTAssertNil(first.folderRefused)
        XCTAssertTrue(first.folder.hasSuffix("/Desktop"))

        let lateTask = collect(engine, into: late)
        await waitUntil("a subscriber that came late got the last state") { late.all.count == 1 }
        XCTAssertEqual(late.all.first, first, "the replay is not the last state")

        preferences.savedLocation = 42
        engine.refresh()
        await waitUntil("the second reading reached both") { early.all.count == 2 && late.all.count == 2 }
        XCTAssertEqual(early.all.map(\.folderRefused), [nil, .notAPath], "the early subscriber's order")
        XCTAssertEqual(late.all.map(\.folderRefused), [nil, .notAPath], "the late subscriber's order")
        earlyTask.cancel(); lateTask.cancel()
        engine.deactivate()
    }

    @MainActor
    func testAfterDeactivateNothingIsSaid() async throws {
        let preferences = FakePreferences()
        let (engine, _) = engine("shots-stream-off", preferences)
        let sink = Collected()
        let task = collect(engine, into: sink)
        engine.activate()
        await waitUntil("the first reading") { sink.all.count == 1 }
        preferences.savedLocation = 42
        engine.refresh()
        await waitUntil("the control: a refresh while active is said") { sink.all.count == 2 }

        engine.deactivate()
        preferences.savedLocation = nil
        engine.refresh()
        await grace(0.5)
        XCTAssertEqual(sink.all.count, 2, "a read started after deactivation was said")
        task.cancel()
    }

    @MainActor
    func testTheConsumersCancelLeavesNoSubscriber() async throws {
        let (engine, news) = engine("shots-stream-cancel", FakePreferences())
        XCTAssertEqual(news.subscriberCount, 0, "the control: nobody subscribed yet")
        let task = collect(engine, into: Collected())
        XCTAssertEqual(news.subscriberCount, 1, "the subscriber is registered before stream() returns")
        await grace(0.1)
        task.cancel()
        for _ in 0..<400 where news.subscriberCount != 0 { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(news.subscriberCount, 0, "the consumer went and its subscriber stayed")
    }
}
