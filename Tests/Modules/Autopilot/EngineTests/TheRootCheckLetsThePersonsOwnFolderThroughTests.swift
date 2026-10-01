import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// The engine asks `WatchScope` about a watched folder's root before it reads it.
///
/// A root check refuses in the safe direction, and the cost of refusing too much
/// is not visible anywhere: the sweep reports the folder as unreadable, the
/// hourly pass writes one warning into a log nobody reads, and the person's
/// real rules simply stop. So these hold the other side of the check — every
/// spelling under which an ordinary watched folder is still the person's own
/// folder is read, and a gate that compared strings, or one that forgot the
/// engine's home, fails here — and then the one planted shape the ancestor
/// test does not cover: the watched folder *itself* replaced by a link after
/// the rules were saved.
///
/// Everything is on disk: a scratch home, real folders, real links. The scratch
/// home lives under `/var/folders`, so its `/private` spelling is a real second
/// spelling of the same directory.
final class TheRootCheckLetsThePersonsOwnFolderThroughTests: XCTestCase {

    private var home: URL!
    private var engine: AutopilotEngine!
    private let secret = "passport-scan-2026.pdf"

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        try write("Downloads/invoice.pdf", in: home)
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func watch(_ path: String, id: String = "f") -> WatchedFolder {
        WatchedFolder(id: id, path: path, enabled: true, rules: [
            Rule(id: "r", name: "Sort", enabled: true, conditions: [.fileExtension(["pdf"])],
                 action: .move(to: home.appendingPathComponent("Sorted").path)),
        ], depth: 1)
    }

    private func storedText() -> String {
        engine.history.compactMap { try? JSONEncoder().encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }.joined()
    }

    /// Read, and acted on: the move happened, so the rules really ran.
    private func assertRead(_ path: String, _ what: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let folder = watch(path)
        engine.folders = [folder]
        XCTAssertEqual(engine.preview(folder).count, 1, "\(what): the dry run showed nothing",
                       file: file, line: line)
        let report = engine.sweep(folder)
        XCTAssertEqual(report.folder, .read, "\(what): the person's own folder was refused",
                       file: file, line: line)
        XCTAssertEqual(report.examined, 1, "\(what)", file: file, line: line)
        XCTAssertEqual(report.acted, 1, "\(what): the rule did not run", file: file, line: line)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: home.appendingPathComponent("Sorted/invoice.pdf").path),
            "\(what): the file was not moved", file: file, line: line)
    }

    // MARK: - The person's own folder under another spelling

    func testDownloadsItselfIsRead() {
        assertRead(home.appendingPathComponent("Downloads").path, "control")
    }

    func testDownloadsSpelledThroughPrivateIsRead() throws {
        let plain = home.appendingPathComponent("Downloads").path
        try XCTSkipUnless(plain.hasPrefix("/var/"), "the scratch home is not under /var: \(plain)")
        assertRead("/private" + plain, "/private spelling")
    }

    /// The engine's own home spelled through `/private`, the folder not.
    func testAHomeSpelledThroughPrivateStillHoldsDownloads() throws {
        try XCTSkipUnless(home.path.hasPrefix("/var/"), "the scratch home is not under /var")
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: "/private" + home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
        assertRead(home.appendingPathComponent("Downloads").path, "home through /private")
    }

    /// Not refused by the root check. Whether the reader then reads through the
    /// link is `AFolderWatchedThroughALinkIsReadTests`' question, not this one.
    func testALinkToDownloadsIsNotRefusedByTheRootCheck() throws {
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("DL"),
            withDestinationURL: home.appendingPathComponent("Downloads"))
        let report = engine.sweep(watch(home.appendingPathComponent("DL").path))
        XCTAssertEqual(report.folder, .read, "a link to Downloads was refused as outside the scope")
    }

    func testAnotherCaseOfDownloadsIsRead() {
        assertRead(home.appendingPathComponent("downloads").path, "lower case")
    }

    func testATrailingSlashIsRead() {
        assertRead(home.appendingPathComponent("Downloads").path + "/", "trailing slash")
    }

    // MARK: - Absent folders keep saying absent

    /// A renamed folder is `.missing`, which the page words as «this folder is
    /// gone» — a root check that ran first and refused it would say «Helm cannot
    /// read this folder» about a rename.
    func testAFolderThatIsGoneStillReadsAsMissing() {
        let report = engine.sweep(watch(home.appendingPathComponent("Gone").path))
        XCTAssertEqual(report.folder, .missing)
    }

    /// An unplugged disk is the same: the gate allows a folder inside a volume,
    /// and the answer is that it is not there.
    func testAFolderOnADiskThatIsNotMountedReadsAsMissing() {
        let report = engine.sweep(watch("/Volumes/HelmNoSuchDisk-\(UUID().uuidString)/Photos"))
        XCTAssertEqual(report.folder, .missing)
    }

    // MARK: - The watched folder itself became a link

    /// Saved as `~/Inbox`, a real folder; afterwards `~/Inbox` is removed and a
    /// link of that name to `~/Library/Inbox` put in its place. The ancestor test
    /// has the link one level up; this is the leaf.
    func testTheWatchedFolderReplacedByALinkIntoLibraryIsNotRead() throws {
        let fm = FileManager.default
        try write("Inbox/mine.pdf", in: home)
        let folder = watch(home.appendingPathComponent("Inbox").path)
        engine.folders = [folder]
        XCTAssertEqual(engine.sweep(folder).examined, 1, "precondition: the real folder was read")

        try write("Library/Inbox/\(secret)", in: home)
        try fm.removeItem(at: home.appendingPathComponent("Inbox"))
        try fm.createSymbolicLink(at: home.appendingPathComponent("Inbox"),
                                  withDestinationURL: home.appendingPathComponent("Library/Inbox"))

        XCTAssertEqual(engine.preview(folder), [])
        let report = engine.sweepAll().first { $0.folderID == folder.id }
        XCTAssertEqual(report?.examined, 0)
        XCTAssertEqual(report?.folder, .refused)
        XCTAssertFalse(storedText().contains(secret), storedText())
        XCTAssertTrue(fm.fileExists(atPath: home.appendingPathComponent("Library/Inbox/\(secret)").path))
    }

    /// The same, one link further: `~/Inbox -> ~/Hop -> ~/Library/Inbox`.
    func testAChainOfLinksIntoLibraryIsNotRead() throws {
        let fm = FileManager.default
        try write("Library/Inbox/\(secret)", in: home)
        try fm.createSymbolicLink(at: home.appendingPathComponent("Hop"),
                                  withDestinationURL: home.appendingPathComponent("Library/Inbox"))
        try fm.createSymbolicLink(at: home.appendingPathComponent("Inbox"),
                                  withDestinationURL: home.appendingPathComponent("Hop"))
        let folder = watch(home.appendingPathComponent("Inbox").path)

        XCTAssertEqual(engine.preview(folder), [])
        XCTAssertEqual(engine.sweep(folder).examined, 0)
    }

    // MARK: - The page and the sweep

    /// **What the page draws for a root the sweep refuses.** `status` answers
    /// each folder with `FolderReader.state(of:)`, which opens the folder without
    /// asking the gate — with Full Disk Access that open succeeds, so the page
    /// is told `.read` and draws no notice, while every sweep of the same folder
    /// is `.refused` and does nothing. After a Run now the row says «Helm cannot
    /// read this folder» until the next status read takes it away again.
    func testThePageIsToldWhatTheSweepWasToldAboutARefusedRoot() throws {
        let fm = FileManager.default
        try write("Library/Inbox/\(secret)", in: home)
        try fm.createSymbolicLink(at: home.appendingPathComponent("Inbox"),
                                  withDestinationURL: home.appendingPathComponent("Library/Inbox"))
        let folder = watch(home.appendingPathComponent("Inbox").path)
        engine.folders = [folder]

        let swept = engine.sweep(folder).folder
        XCTAssertEqual(swept, .refused, "precondition: the sweep refused the root")

        XCTAssertEqual(engine.status.folders[folder.id], swept,
                       "the page is told this folder reads fine while no sweep will ever read it")
    }
}
