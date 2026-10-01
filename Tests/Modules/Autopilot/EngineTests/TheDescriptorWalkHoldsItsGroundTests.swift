import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// The folder walk reads through descriptors: the root opened once, every level
/// opened relative to its parent with `O_NOFOLLOW`, the gate asked of the path
/// each descriptor reports, and a ceiling on how deep it goes.
///
/// Each of those is a belt the engine's own filter stands behind, so none of them
/// can be seen through a sweep — the filter drops what a broken walk would have
/// read, and the module's tests stayed green with the walk's gates, its
/// `O_NOFOLLOW`, its ceiling and every `close` taken out. These ask the reader
/// itself, which is where each of them lives.
///
/// **One case here is a documented gap, skipped and not deleted:**
/// `testPastTheCeilingTheWatcherAndTheSweepAgree` (F-Y2) is skipped unless
/// `HELM_KNOWN_GAPS=1`, with a reason starting «Known gap F-Y2», and keeps its
/// reproduction, so removing the skip is what turns it into the guard once `admits`
/// knows the ceiling; `HELM_KNOWN_GAPS=1` runs it red. Every known gap in the tree
/// is skipped this one way.
final class TheDescriptorWalkHoldsItsGroundTests: XCTestCase {

    private var home: URL!
    private let secret = "passport-scan-2026.pdf"

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        try write("Library/Inbox/\(secret)", in: home)
    }

    private func openDescriptors() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
    }

    // MARK: - Descriptors

    /// Every way out of a read — a full walk, a level that will not open, a link
    /// that is not followed, a root the gate refuses, a root that is gone, a depth
    /// that reads nothing — leaves the process holding what it held before.
    /// A walk that leaks one per level runs out of descriptors in a process that
    /// holds Full Disk Access, hourly, unattended.
    func testEveryDescriptorTheWalkOpensIsClosed() throws {
        try write("Downloads/a.pdf", in: home)
        try write("Downloads/sub/b.pdf", in: home)
        try write("Downloads/sub/deep/c.pdf", in: home)
        try write("Downloads/locked/x.pdf", in: home)
        let locked = home.appendingPathComponent("Downloads/locked").path
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked)
        }
        let fm = FileManager.default
        try fm.createSymbolicLink(at: home.appendingPathComponent("Downloads/lib"),
                                  withDestinationURL: home.appendingPathComponent("Library"))
        try fm.createSymbolicLink(at: home.appendingPathComponent("Stuff"),
                                  withDestinationURL: home.appendingPathComponent("Library"))
        let reader = FolderReader(home: home.path)
        let downloads = home.appendingPathComponent("Downloads").path

        // The subject happened: the walk went three levels down, and the refused
        // root was refused by the reader, not merely by an absence.
        let names = Set(reader.reading(in: downloads, depth: 5).files.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["a.pdf", "b.pdf", "c.pdf", "locked", "lib"]), "\(names)")
        XCTAssertEqual(reader.reading(in: home.appendingPathComponent("Stuff/Inbox").path,
                                      depth: 5).state, .refused)

        let before = openDescriptors()
        for _ in 0..<300 {
            _ = reader.reading(in: downloads, depth: 5)
            _ = reader.reading(in: downloads, depth: 1)
            _ = reader.reading(in: downloads, depth: 0)
            _ = reader.reading(in: home.appendingPathComponent("Stuff/Inbox").path, depth: 5)
            _ = reader.reading(in: home.appendingPathComponent("gone").path, depth: 5)
        }
        XCTAssertEqual(openDescriptors(), before, "the walk left descriptors open")
    }

    // MARK: - The root

    /// A watched folder whose path leads into `~/Library` — a link standing in
    /// for an ancestor — is refused by the reader on the path its descriptor
    /// reports, without the engine's check in front of it. The engine asks first,
    /// and a link turned between that question and the open is this one's.
    func testARootThatLeadsIntoLibraryIsRefusedByTheReaderItself() throws {
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("Stuff"),
            withDestinationURL: home.appendingPathComponent("Library"))
        let path = home.appendingPathComponent("Stuff/Inbox").path

        // Control: with no gate the same path reads the protected folder, so the
        // refusal below is the gate's and not the filesystem's.
        XCTAssertEqual(FolderReader().reading(in: path, depth: 1).files.map(\.name), [secret])

        let reading = FolderReader(home: home.path).reading(in: path, depth: 1)
        XCTAssertEqual(reading.state, .refused)
        XCTAssertTrue(reading.files.isEmpty, "\(reading.files.map(\.path))")
    }

    // MARK: - A level swapped while the walk is under way

    /// A subfolder swapped with a link into `~/Library` over and over while the
    /// reader walks. The listing and the descent are two moments, and nothing
    /// may stand in between to make them one — so the descent has to refuse the
    /// link itself, by `O_NOFOLLOW` and by the gate on the descriptor's path.
    ///
    /// No seam reaches the window between a level's facts and its open, so this
    /// is a race and is run long enough to land in it: every read in which the
    /// folder was a folder and every read in which it was a link is counted, and
    /// both must have happened.
    func testASubfolderSwappedForALinkWhileTheWalkRunsIsNeverReadThrough() throws {
        let watched = home.appendingPathComponent("Watched")
        try write("Watched/a.pdf", in: home)
        try write("Watched/m/ok.pdf", in: home)
        // The link waits under a hidden name, which the walk never lists.
        try FileManager.default.createSymbolicLink(
            at: watched.appendingPathComponent(".alt"),
            withDestinationURL: home.appendingPathComponent("Library/Inbox"))

        let flipper = Flipper(watched.appendingPathComponent("m").path,
                              watched.appendingPathComponent(".alt").path)
        let reader = FolderReader(home: home.path)
        var throughAFolder = 0, overALink = 0
        var leaked: [String] = []
        flipper.start()
        let deadline = Date().addingTimeInterval(4)
        var reads = 0
        while Date() < deadline, reads < 20_000 {
            reads += 1
            let files = reader.reading(in: watched.path, depth: 3).files
            if files.contains(where: { $0.name == "ok.pdf" }) { throughAFolder += 1 }
            if files.contains(where: { $0.name == "m" && !$0.isDirectory }) { overALink += 1 }
            leaked += files.map(\.path).filter { $0.contains("/Library/") }
        }
        let swaps = flipper.stop()

        XCTAssertGreaterThan(swaps, 100, "precondition: the folder was swapped")
        XCTAssertGreaterThan(throughAFolder, 0, "precondition: some reads descended the real folder")
        XCTAssertGreaterThan(overALink, 0, "precondition: some reads met the link")
        XCTAssertEqual(leaked, [], "the walk read through a link into ~/Library in \(leaked.count) of \(reads) reads")
    }

    // MARK: - The ceiling

    /// A depth is an `Int` from a property list; the ceiling is what keeps a huge
    /// one from holding a descriptor per level for as deep as a tree goes.
    func testTheWalkStopsAtItsCeilingWhateverTheDepthAsks() throws {
        let root = home.appendingPathComponent("Deep")
        let chain = (1...(FolderReader.deepest + 6)).map { "d\($0)" }
        try write("Deep/" + chain.joined(separator: "/") + "/leaf.pdf", in: home)
        let reader = FolderReader(home: home.path)

        let deep = Set(reader.facts(in: root.path, depth: Int.max).map(\.name))
        XCTAssertTrue(deep.contains("d\(FolderReader.deepest)"), "the ceiling's own level is offered")
        XCTAssertFalse(deep.contains("d\(FolderReader.deepest + 1)"), "the walk went past its ceiling")
        XCTAssertFalse(deep.contains("leaf.pdf"))
        // A depth under the ceiling is the depth asked for.
        XCTAssertEqual(reader.facts(in: root.path, depth: 8).count, 8)
    }

    /// The watcher's question and the sweep's are pinned to one another
    /// (`TheWatcherAndTheSweepAskOneQuestionTests`) — at depths under the
    /// ceiling. Past it the sweep stops and `admits` does not, so a file at
    /// level 70 of a folder set to depth 100 is acted on when it arrives and
    /// never by any sweep.
    func testPastTheCeilingTheWatcherAndTheSweepAgree() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_KNOWN_GAPS"] == "1", "Known gap F-Y2: past FolderReader.deepest the watcher admits files the sweep never reads.")
        let root = home.appendingPathComponent("Deep")
        let chain = (1...(FolderReader.deepest + 6)).map { "d\($0)" }
        try write("Deep/" + chain.joined(separator: "/") + "/leaf.pdf", in: home)
        let reader = FolderReader(home: home.path)
        let folder = WatchedFolder(id: "w", path: root.path, enabled: true, rules: [], depth: 100)

        let swept = Set(reader.facts(in: root.path, depth: folder.depth).map(\.path))
        var path = root.path
        var disagree: [String] = []
        for name in chain + ["leaf.pdf"] {
            path += "/" + name
            let admitted = reader.admits(URL(fileURLWithPath: path), under: folder)
            let read = swept.contains { WatchScope.sameFolder($0, path) }
            if admitted != read { disagree.append(name) }
        }
        XCTAssertEqual(disagree, [], "the watcher admits what the sweep never reads")
    }

    // MARK: - A folder saved as a link meets its own bucket

    /// The walk reports where a folder saved as a link leads — `~/Downloads/…`
    /// for a folder saved as `~/DL` — while the rule's destination keeps the
    /// spelling it was saved with, `~/DL/Invoices`. The bucket matches its own
    /// rule on the next sweep, and the guard that keeps a folder out of itself
    /// has to see one folder in two spellings, or `moveItem` answers EINVAL on
    /// every sweep for ever.
    func testABucketSpelledThroughTheFoldersLinkIsNotMovedIntoItself() throws {
        try write("Downloads/Invoice-1.pdf", in: home)
        try write("Downloads/Invoices/Invoice-0.pdf", in: home)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("DL"),
            withDestinationURL: home.appendingPathComponent("Downloads"))
        let engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
        let folder = WatchedFolder(id: "w", path: home.appendingPathComponent("DL").path, enabled: true, rules: [
            Rule(id: "r", name: "Invoices", enabled: true, conditions: [.name(.beginsWith, "Invoice")],
                 action: .move(to: home.appendingPathComponent("DL/Invoices").path)),
        ], depth: 1)
        engine.folders = [folder]

        let report = engine.sweep(folder)

        XCTAssertEqual(report.examined, 2, "precondition: the walk offered the file and the bucket")
        XCTAssertEqual(report.acted, 1, "precondition: the file went into the bucket")
        XCTAssertEqual(report.failed, 0, "the bucket was handed to moveItem to go inside itself")
        XCTAssertEqual(report.refused, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: home.appendingPathComponent("Downloads/Invoices/Invoice-1.pdf").path))
    }

    // MARK: - A history written before the split

    /// A build before `targetOutOfScope` wrote every scope refusal with the
    /// file's name and `outOfScope`. That history still decodes, still names its
    /// file, still reads as the scope sentence — and the new destination refusal
    /// is stored as the very same reason, so the page cannot tell them apart.
    func testAnOldRecordOfAScopeRefusalStillReadsAsOne() throws {
        let old = """
        [{"at":780000000,"rule":"Sort","file":"invoice.pdf","path":"/Users/x/Downloads/invoice.pdf",\
        "kind":"refused","detail":"outOfScope","destination":"","run":"p","ruleID":"r"}]
        """
        let records = ActionHistory.decode(Data(old.utf8))
        XCTAssertEqual(records.map(\.file), ["invoice.pdf"])
        XCTAssertEqual(records.first.flatMap { RuleOutcome.Refusal(rawValue: $0.detail) }, .outOfScope)

        let plan = RulePlan(facts: FileFacts(name: "invoice.pdf", path: "/Users/x/Downloads/invoice.pdf",
                                             kind: .document, bytes: 1, added: Date(), modified: Date()),
                            rule: Rule(id: "r", name: "Sort", enabled: true,
                                       conditions: [.fileExtension(["pdf"])], action: .trash))
        let new = ActionRecord.of(plan, .targetOutOfScope, run: "p")
        XCTAssertEqual(new?.detail, records.first?.detail)
        XCTAssertEqual(new?.file, "invoice.pdf")
    }
}

/// Swaps two directory entries atomically, as fast as it can, on a thread of
/// its own, until told to stop.
private final class Flipper: @unchecked Sendable {
    private let a: String, b: String
    private let lock = NSLock()
    private var running = true
    private var count = 0
    private let done = DispatchSemaphore(value: 0)

    init(_ a: String, _ b: String) { self.a = a; self.b = b }

    func start() {
        Thread.detachNewThread { [self] in
            var swaps = 0
            while lock.withLock({ running }) {
                if renamex_np(a, b, UInt32(RENAME_SWAP)) == 0 { swaps += 1 }
            }
            // Leave the real folder under its own name.
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: a)) != nil {
                _ = renamex_np(a, b, UInt32(RENAME_SWAP))
            }
            lock.withLock { count = swaps }
            done.signal()
        }
    }

    func stop() -> Int {
        lock.withLock { running = false }
        done.wait()
        return lock.withLock { count }
    }
}
