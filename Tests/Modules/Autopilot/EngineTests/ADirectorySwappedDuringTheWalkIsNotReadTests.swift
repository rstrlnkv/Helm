import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// A subfolder of a watched folder replaced by a link into `~/Library` while the
/// walk is under way, and put back as soon as the walk has read it.
///
/// The root is asked about before it is read and every file is asked about by
/// the runner, and between the two a walk that descends *by path* opens whatever
/// the path leads to at that moment. What it read then was a protected folder's
/// names; swapped back, the runner found the file `.missing` and the history and
/// the log wrote its name and path down.
///
/// The swap is made by the walk's own seam — the weigh of a file, which is asked
/// as each file is read — so it lands in the window without a race: the first
/// file read swaps every subfolder not yet entered, and the file the walk finds
/// in the protected folder swaps them back. Sibling order is the filesystem's, so
/// files are named to sort on both sides of the folders.
final class ADirectorySwappedDuringTheWalkIsNotReadTests: XCTestCase {

    private var home: URL!
    private var watched: URL!
    private let secret = "tax-return-2026.pdf"
    private let dirs = ["m1", "m2", "m3", "m4", "m5"]

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        watched = home.appendingPathComponent("Watched")
        try write("Library/Inbox/\(secret)", in: home)
        for name in ["a1.pdf", "a2.pdf", "z1.pdf", "z2.pdf"] { try write("Watched/\(name)", in: home) }
        for dir in dirs { try write("Watched/\(dir)/ok.pdf", in: home) }
    }

    private func engine(swapping: Bool) -> AutopilotEngine {
        let engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
        guard swapping else { return engine }
        let library = home.appendingPathComponent("Library/Inbox")
        let watched = self.watched!, dirs = self.dirs, secret = self.secret
        engine.reader = FolderReader(weigh: { url in
            let fm = FileManager.default
            if url.lastPathComponent == secret {
                // Read: put the real folders back.
                for dir in dirs {
                    let place = watched.appendingPathComponent(dir)
                    guard (try? fm.destinationOfSymbolicLink(atPath: place.path)) != nil else { continue }
                    try? fm.removeItem(at: place)
                    try? fm.createDirectory(at: place, withIntermediateDirectories: true)
                    fm.createFile(atPath: place.appendingPathComponent("ok.pdf").path, contents: Data("x".utf8))
                }
                return 1
            }
            for dir in dirs {
                let place = watched.appendingPathComponent(dir)
                guard (try? fm.destinationOfSymbolicLink(atPath: place.path)) == nil else { continue }
                try? fm.removeItem(at: place)
                try? fm.createSymbolicLink(at: place, withDestinationURL: library)
            }
            return 1
        }, home: home.path)
        return engine
    }

    private func folder() -> WatchedFolder {
        WatchedFolder(id: "w", path: watched.path, enabled: true, rules: [
            Rule(id: "r", name: "Sort", enabled: true, conditions: [.fileExtension(["pdf"])],
                 action: .move(to: home.appendingPathComponent("Sorted").path)),
        ], depth: 3)
    }

    private func everythingWritten(_ engine: AutopilotEngine) -> String {
        let history = engine.history.compactMap { try? JSONEncoder().encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }.joined()
        let log = HelmLog.shared.recentEntries().map(\.message).joined(separator: "\n")
        return history + "\n" + log
    }

    /// The control: no swap, the walk goes down and reads every ok.pdf.
    func testWithoutASwapTheWalkDescends() {
        let engine = engine(swapping: false)
        let folder = folder()
        engine.folders = [folder]
        XCTAssertEqual(engine.preview(folder).filter { $0.facts.name == "ok.pdf" }.count, dirs.count)
    }

    func testASubfolderSwappedToALinkIsNeverEntered() {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()
        let engine = engine(swapping: true)
        let folder = folder()
        engine.folders = [folder]

        let report = engine.sweep(folder)

        XCTAssertEqual(report.folder, .read, "precondition: the sweep ran")
        XCTAssertGreaterThan(report.examined, 0, "precondition: the walk read something")
        let written = everythingWritten(engine)
        XCTAssertFalse(written.contains(secret), written)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: home.appendingPathComponent("Library/Inbox/\(secret)").path))
    }
}
