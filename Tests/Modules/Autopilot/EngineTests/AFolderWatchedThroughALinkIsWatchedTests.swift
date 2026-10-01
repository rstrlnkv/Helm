import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// The other leg of `AFolderWatchedThroughALinkIsReadTests`: a folder saved as a
/// link — `~/DL` for `~/Downloads` — and a file arriving in it.
///
/// An FSEvents stream reports real paths, so the event for `photo.jpg` names
/// `~/Downloads/photo.jpg`, and a leg that matched it to the watched folder by
/// the folder's *spelling* found no folder at all: the sweep read the folder and
/// the watcher never acted on anything arriving in it.
final class AFolderWatchedThroughALinkIsWatchedTests: XCTestCase {

    private var home: URL!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        try write("Downloads/photo.jpg", in: home)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("DL"),
            withDestinationURL: home.appendingPathComponent("Downloads"))
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func watch(_ path: String) -> WatchedFolder {
        WatchedFolder(id: "w", path: path, enabled: true, rules: [
            Rule(id: "r", name: "Photos", enabled: true, conditions: [.fileExtension(["jpg"])],
                 action: .move(to: home.appendingPathComponent("Sorted").path)),
        ], depth: 1)
    }

    private var arrived: Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent("Sorted/photo.jpg").path)
    }

    /// The control: the folder under its own name, the event under the real path.
    func testAnEventInAFolderWatchedUnderItsOwnNameIsActedOn() {
        engine.folders = [watch(home.appendingPathComponent("Downloads").path)]
        engine.handle([home.appendingPathComponent("Downloads/photo.jpg").path])
        _ = engine.historyRefused
        XCTAssertTrue(arrived)
    }

    func testAnEventInAFolderWatchedThroughALinkIsActedOn() {
        engine.folders = [watch(home.appendingPathComponent("DL").path)]
        engine.handle([home.appendingPathComponent("Downloads/photo.jpg").path])
        _ = engine.historyRefused   // the queue has drained once this returns
        XCTAssertTrue(arrived, "a file arrived in a folder watched through a link and no rule ran")
    }
}
