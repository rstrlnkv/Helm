import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// The watcher's plan for a file behind a link into `~/Library` reads nothing
/// of the file.
///
/// `plan(for:)` asks `WatchScope` before `admits`, `fileExists` and
/// `facts(of:)`. The runner's gate behind it refuses the same path, so what the
/// first gate buys is not a different outcome but the absence of a read: a gate
/// moved below `facts(of:)` refuses exactly the same files and records exactly
/// the same nothing, while the metadata of a protected file has already been
/// taken. The only place that read is visible from outside is the reader's
/// `weigh` seam, which `facts(of:)` asks for every file it reads — so the seam
/// records every path it is handed and the protected one must not be among them.
///
/// The shape is the one `AFolderReachedThroughALinkIsNotReadTests` builds:
/// `~/Stuff` is a link to `~/Library`, the watched folder is `~/Stuff/Inbox`,
/// and an ordinary folder beside it is watched too, so the ordinary file in the
/// same batch is the proof the watcher reached its reads at all.
final class AWatcherEventBehindALinkIsNeverReadTests: XCTestCase {

    /// Every path the seam was handed, across the engine's queue.
    private final class Weighed: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String] = []
        func note(_ url: URL) { lock.withLock { paths.append(url.path) } }
        var all: [String] { lock.withLock { paths } }
    }

    private let secret = "medical-letter-2026.pdf"

    func testTheProtectedFileIsNotWeighedAndTheOrdinaryOneIs() throws {
        let home = scratchDirectory("home")
        let library = home.appendingPathComponent("Library")
        try write("Inbox/\(secret)", in: library)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Stuff"),
                                                   withDestinationURL: library)
        try write("Real/Inbox/notes.pdf", in: home)
        func watch(_ id: String, _ path: String) -> WatchedFolder {
            WatchedFolder(id: id, path: path, enabled: true, rules: [
                Rule(id: "r", name: "Sort", enabled: true, conditions: [.fileExtension(["pdf"])],
                     action: .move(to: home.appendingPathComponent("Sorted").path)),
            ], depth: 1)
        }
        let engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
        let weighed = Weighed()
        engine.reader = FolderReader(weigh: { url in weighed.note(url); return 4 }, home: home.path)
        engine.folders = [watch("hijacked", home.appendingPathComponent("Stuff/Inbox").path),
                          watch("honest", home.appendingPathComponent("Real/Inbox").path)]

        let behind = home.appendingPathComponent("Stuff/Inbox/\(secret)").path
        let ordinary = home.appendingPathComponent("Real/Inbox/notes.pdf").path
        engine.handle([behind, ordinary])
        _ = engine.historyRefused   // the queue has drained once this returns

        XCTAssertTrue(weighed.all.contains { $0.hasSuffix("/Real/Inbox/notes.pdf") },
                      "precondition: the watcher read the ordinary file — \(weighed.all)")
        XCTAssertFalse(weighed.all.contains { $0.contains(secret) }, """
            the watcher read the metadata of a file behind a link into ~/Library before \
            any gate refused it: \(weighed.all)
            """)
        XCTAssertEqual(engine.history.map(\.kind), [.moved],
                       "the protected file left a record, or the ordinary one none")
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            library.appendingPathComponent("Inbox/\(secret)").path))
    }
}
