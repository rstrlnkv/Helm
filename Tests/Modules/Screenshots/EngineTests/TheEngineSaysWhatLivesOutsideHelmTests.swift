import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// What the settings page is told: the folder macOS names, validated, and which
/// system boxes are ticked. Through the transport, as the page hears it.
final class TheEngineSaysWhatLivesOutsideHelmTests: XCTestCase {

    private func engine(home: URL, preferences: FakePreferences) -> ScreenshotsEngine {
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        return ScreenshotsEngine(preferences: preferences,
                                 locations: ScreenshotsLocations(home: home, desktop: desktop),
                                 transport: LocalTransport())
    }

    /// The flag and not only the cancel: a read *started* after the module was
    /// switched off has no task to cancel by then, and is stopped by the flag.
    func testAReadStartedAfterDeactivationDoesNotPublish() async throws {
        let engine = engine(home: scratchDirectory("shots-engine-late"), preferences: FakePreferences())
        engine.activate()
        engine.deactivate()
        engine.refresh()
        try await Task.sleep(nanoseconds: 300_000_000)
        let published = await Self.state(of: engine, within: 0.5)
        XCTAssertNil(published, "a read started after deactivation was published")
    }

    /// The first state the engine's stream yields, or nil if none arrives in time.
    private static func state(of engine: ScreenshotsEngine, within seconds: Double = 5) async -> ScreenshotsState? {
        await withTaskGroup(of: ScreenshotsState?.self) { group in
            group.addTask {
                for await event in engine.transport.events where event.name == ScreenshotsEvent.screenshotsState.rawValue {
                    return try? JSONDecoder().decode(ScreenshotsState.self, from: event.payload)
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    func testActivationPublishesTheReadingAndALateSubscriberStillGetsIt() async throws {
        let preferences = FakePreferences()
        preferences.hotkeys = .read(["28": ["enabled": false]])
        let engine = engine(home: scratchDirectory("shots-engine"), preferences: preferences)
        engine.activate()
        // Give the read a moment to land; the transport replays it to whoever comes next.
        try await Task.sleep(nanoseconds: 300_000_000)

        let found = await Self.state(of: engine)
        let state = try XCTUnwrap(found, "the engine published nothing")
        XCTAssertEqual(state.boxes.first { $0.box == .saveScreen }?.state, .off)
        XCTAssertEqual(state.boxes.first { $0.box == .saveArea }?.state, .on)
        XCTAssertTrue(state.folder.hasSuffix("/Desktop"))
        XCTAssertNil(state.folderRefused)
        engine.deactivate()
    }

    func testTheRefreshCommandReadsAgainAndAnswersWithWhatItRead() async throws {
        let preferences = FakePreferences()
        let engine = engine(home: scratchDirectory("shots-engine-refresh"), preferences: preferences)
        preferences.savedLocation = 42
        let reply = try await engine.transport.send(EngineCommand(name: ScreenshotsCommand.refresh.rawValue))
        let state = try JSONDecoder().decode(ScreenshotsState.self, from: reply)
        XCTAssertEqual(state.folderRefused, .notAPath, "a garbage location was not refused in the page's state")
    }

    func testAnUnknownCommandIsRefusedAtTheDoor() async throws {
        let engine = engine(home: scratchDirectory("shots-engine-unknown"), preferences: FakePreferences())
        let reply = try await engine.transport.send(EngineCommand(name: "capture"))
        XCTAssertEqual(reply, Data())
    }

    func testASwitchedOffEngineDoesNotPublish() async throws {
        let engine = engine(home: scratchDirectory("shots-engine-off"), preferences: FakePreferences())
        engine.activate()
        engine.deactivate()
        try await Task.sleep(nanoseconds: 300_000_000)
        let published = await Self.state(of: engine, within: 0.5)
        XCTAssertNil(published, "an engine that was deactivated published after it")
    }
}
