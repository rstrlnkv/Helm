import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// **An empty folder, a folder Helm may not read and a folder that is no longer
/// there were one report.**
///
/// Measured before this existed: `examined 0 acted 0 refused 0 failed 0` for all
/// three, an identical dry run, and a page drawing the path with a live switch
/// beside it and nothing else. That is the commonest way this module dies — a
/// watched folder is renamed, or the Downloads prompt is declined once, and
/// Autopilot stops tidying behind a screen that looks exactly like a screen where
/// nothing needed tidying. The module's own `needsAccess` string describes the
/// defect instead of fixing it.
///
/// The reader answers which of the three it was, so everything above it can.
final class AnEmptyFolderIsNotAnUnreadableOneTests: XCTestCase {

    private var home: URL!
    private let reader = FolderReader()

    override func setUpWithError() throws {
        home = scratchDirectory("home")
    }

    /// **Handed back inside the test, not in `tearDown`.** `scratchDirectory`
    /// registers a teardown *block*, and XCTest runs those before the teardown
    /// method — so a directory left at 0 was still unreadable when the scratch
    /// cleanup tried to walk it, and the run ended with the harness reporting
    /// that it had left a home directory behind.
    private func lock(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: url.path)
        }
    }

    private func directory(_ name: String) throws -> URL {
        let url = home.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - The three answers

    func testAFolderWithFilesReadsThem() throws {
        let full = try directory("full")
        try write("a.pdf", in: full, bytes: 10)

        let reading = reader.reading(in: full.path, depth: 1)

        XCTAssertEqual(reading.state, .read)
        XCTAssertEqual(reading.files.map(\.name), ["a.pdf"])
    }

    func testAnEmptyFolderIsRead() throws {
        let empty = try directory("empty")

        let reading = reader.reading(in: empty.path, depth: 1)

        XCTAssertEqual(reading.state, .read)
        XCTAssertEqual(reading.files, [])
    }

    func testAFolderThatIsNoLongerThereSaysSo() {
        let gone = home.appendingPathComponent("gone")

        let reading = reader.reading(in: gone.path, depth: 1)

        XCTAssertEqual(reading.state, .missing)
        XCTAssertEqual(reading.files, [])
    }

    func testAFolderHelmMayNotReadSaysSo() throws {
        let closed = try directory("closed")
        try write("a.pdf", in: closed, bytes: 10)
        try lock(closed)
        // The fixture is what it claims: this really is unreadable to this
        // process, and a test running where it is not would be asserting the
        // empty case under another name.
        XCTAssertNil(try? FileManager.default.contentsOfDirectory(atPath: closed.path),
                     "precondition: the directory is readable after chmod 000")

        let reading = reader.reading(in: closed.path, depth: 1)

        XCTAssertEqual(reading.state, .refused)
        XCTAssertEqual(reading.files, [])
    }

    // MARK: - What the sweep reports

    /// The report carries it, so the page can draw the difference the survey
    /// measured as one identical banner three times over.
    func testTheSweepReportCarriesWhichOfTheThreeItWas() throws {
        let empty = try directory("empty")
        let gone = home.appendingPathComponent("gone")

        XCTAssertEqual(engine().sweep(folder(at: empty.path)).folder, .read)
        XCTAssertEqual(engine().sweep(folder(at: gone.path)).folder, .missing)
    }

    // MARK: - What the page can ask without running anything

    /// A person opening the page has not pressed Run now, and the folder that
    /// vanished has to say so on sight — the switch beside it says «on».
    func testTheStatusNamesEveryFolderItCouldNotRead() throws {
        let empty = try directory("empty")
        let closed = try directory("closed")
        try lock(closed)
        let gone = home.appendingPathComponent("gone")
        let engine = engine()
        engine.folders = [folder(at: empty.path), folder(at: closed.path), folder(at: gone.path)]

        let status = engine.status

        XCTAssertEqual(status.folders[empty.path], .read)
        XCTAssertEqual(status.folders[closed.path], .refused)
        XCTAssertEqual(status.folders[gone.path], .missing)
    }

    /// **The channel `FolderWatcher.watch` grew two commits before this module
    /// was audited, and this engine threw it away.** A stream that never started
    /// left the switch saying «on» over a folder nothing was looking at.
    func testWhetherAnythingIsWatchingIsAskedOfTheWatcher() throws {
        let watched = try directory("watched")
        let engine = engine()
        engine.folders = [folder(at: watched.path)]
        XCTAssertNil(engine.status.watching,
                     "an engine that has not been activated claims to know")

        engine.activate()
        addTeardownBlock { engine.deactivate() }

        let deadline = Date().addingTimeInterval(5)
        while engine.status.watching == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(engine.status.watching, true,
                       "nothing is watching a folder the page says is being watched")
    }

    private func engine() -> AutopilotEngine {
        AutopilotEngine(store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                               backing: InMemoryKeyValueStore()),
                        home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func folder(at path: String) -> WatchedFolder {
        WatchedFolder(id: path, path: path, enabled: true, rules: [
            Rule(id: "pdfs", name: "PDFs", enabled: true, match: .all,
                 conditions: [.fileExtension(["pdf"])], action: .sortIntoSubfolder(.kind)),
        ], depth: 1)
    }
}
