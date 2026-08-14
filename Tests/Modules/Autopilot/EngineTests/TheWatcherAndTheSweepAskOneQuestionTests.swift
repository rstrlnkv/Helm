import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// **The two triggers disagreed about what a rule means.**
///
/// The sweep and the dry run read a folder through `FolderReader.facts(in:)`,
/// whose enumerator is built with `.skipsHiddenFiles` and
/// `.skipsPackageDescendants` — so an `.app` is one thing and a dotfile is not
/// there at all. The FSEvents leg took the path it was handed and asked for its
/// facts with no filter, and an FSEvents stream is recursive whether or not
/// anybody asked. With «Include subfolders» on — depth 8, which is what the ⋯
/// menu writes — a resource inside an application bundle in Downloads was a live
/// target, and the dry run could not warn anybody, because the dry run runs
/// through the reader that skips packages.
///
/// **The FSEvents delivery itself is not what these tests drive**, and that is
/// deliberate: `FolderWatcher` carries `kFSEventStreamCreateFlagIgnoreSelf`, so
/// files a test writes in its own process raise no event at all — a test built on
/// the stream would be a test of a child process. `handle` is the leg's entry
/// point and these call it directly, which is the decision the finding is about.
final class TheWatcherAndTheSweepAskOneQuestionTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var engine: AutopilotEngine!
    private let reader = FolderReader()

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Downloads")
        try write("plain.pdf", in: root, bytes: 10)
        try write(".quiet.pdf", in: root, bytes: 10)
        try write("Reader.app/Contents/Resources/manual.pdf", in: root, bytes: 10)
        // An ordinary file one level down, which is the only thing in this tree
        // that depth alone decides: the bundle's contents and the dotfile are
        // refused for reasons of their own at every depth, so without this the
        // depth question could be deleted and nothing would notice.
        try write("project/report.pdf", in: root, bytes: 10)
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func path(_ relative: String) -> String {
        root.appendingPathComponent(relative).path
    }

    private func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: path(relative))
    }

    /// Everything under the watched folder, relative and sorted — the shape a
    /// race cannot satisfy by accident.
    private func tree() -> [String] {
        let all = FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String]
        return (all ?? []).sorted()
    }

    private func everyPathInTheTree() -> [String] {
        tree().map { root.appendingPathComponent($0).path }
    }

    private func folder(depth: Int = 8) -> WatchedFolder {
        WatchedFolder(id: "downloads", path: root.path, enabled: true, rules: [
            Rule(id: "pdfs", name: "PDFs", enabled: true, match: .all,
                 conditions: [.fileExtension(["pdf"])], action: .sortIntoSubfolder(.kind)),
        ], depth: depth)
    }

    // MARK: - The fixture is what it claims to be

    /// A `.app` made with `mkdir` really is a package to `URLResourceValues`, and
    /// a leading dot really is hidden. Asserted rather than assumed: every
    /// finding below is about a file being *left alone*, and a fixture macOS did
    /// not agree with would leave the same files alone for the wrong reason.
    func testTheFixtureIsAPackageAndAHiddenFile() throws {
        let bundle = try XCTUnwrap(URL(fileURLWithPath: path("Reader.app")) as URL?)
        XCTAssertEqual(try bundle.resourceValues(forKeys: [.isPackageKey]).isPackage, true)
        let quiet = URL(fileURLWithPath: path(".quiet.pdf"))
        XCTAssertEqual(try quiet.resourceValues(forKeys: [.isHiddenKey]).isHidden, true)
    }

    // MARK: - What the sweep can see

    func testTheSweepNeverOffersABundleResourceOrAHiddenFile() {
        let found = reader.facts(in: root.path, depth: 8).map(\.name).sorted()

        XCTAssertEqual(found, ["Reader.app", "plain.pdf", "project", "report.pdf"],
                       "the sweep's own reader changed what it can see")
    }

    /// And the depth is the folder's, on both sides: a file one level down is
    /// out of reach at depth 1 and in reach at depth 2.
    func testAFileBelowTheDepthIsNotAdmitted() {
        let deep = URL(fileURLWithPath: path("project/report.pdf"))

        XCTAssertFalse(reader.admits(deep, under: folder(depth: 1)))
        XCTAssertTrue(reader.admits(deep, under: folder(depth: 2)))
    }

    // MARK: - The one question

    /// The tie between the two triggers: for every file in the tree, what the
    /// sweep reads and what the watcher admits are the same set. Written as an
    /// agreement rather than as two lists, so a change to either side that does
    /// not change the other fails here.
    func testWhatTheSweepReadsIsExactlyWhatTheWatcherAdmits() {
        for depth in [1, 2, 8] {
            let watched = folder(depth: depth)
            // Resolved on both sides: the enumerator hands back `/private/var/…`
            // for a scratch directory under `/var`, which is one path spelled two
            // ways and not a disagreement about any file.
            let swept = Set(reader.facts(in: root.path, depth: depth).map { resolved($0.path) })
            let admitted = Set(everyPathInTheTree()
                .filter { reader.admits(URL(fileURLWithPath: $0), under: watched) }
                .map(resolved))

            XCTAssertEqual(swept, admitted,
                           "at depth \(depth) the sweep and the watcher disagree about "
                           + "\(swept.symmetricDifference(admitted).sorted())")
        }
    }

    private func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    // MARK: - What the watcher does

    /// The control: an ordinary file in the watched folder is acted on, so the
    /// two assertions below are about a leg that ran rather than one that never
    /// started.
    func testAnOrdinaryFileIsActedOn() throws {
        engine.folders = [folder()]

        engine.handle([path("plain.pdf")])

        try waitForTheWatcherToFinish()
        XCTAssertFalse(exists("plain.pdf"), "the watcher did nothing at all")
        XCTAssertTrue(exists("Documents/plain.pdf"), tree().description)
    }

    func testAResourceInsideAnApplicationBundleIsLeftAlone() throws {
        engine.folders = [folder()]

        engine.handle([path("Reader.app/Contents/Resources/manual.pdf"), path("plain.pdf")])

        try waitForTheWatcherToFinish()
        XCTAssertTrue(exists("Reader.app/Contents/Resources/manual.pdf"),
                      "a rule took a resource out of an application bundle: \(tree())")
        XCTAssertFalse(exists("Reader.app/Contents/Resources/Documents/manual.pdf"))
    }

    func testAHiddenFileIsLeftAlone() throws {
        engine.folders = [folder(depth: 1)]

        engine.handle([path(".quiet.pdf"), path("plain.pdf")])

        try waitForTheWatcherToFinish()
        XCTAssertTrue(exists(".quiet.pdf"),
                      "a rule acted on a file the sweep can never see: \(tree())")
    }

    /// `handle` hands its work to the engine's own queue and answers nothing.
    /// The history is written after the whole batch, so a record for the control
    /// file is the batch having finished — not a sleep, which would be a guess
    /// about a machine.
    private func waitForTheWatcherToFinish() throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if engine.history.contains(where: { $0.file == "plain.pdf" }) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("the watcher never finished its batch")
    }
}
