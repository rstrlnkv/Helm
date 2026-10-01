import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// A refusal for scope writes no name and no path, so a protected file's name
/// never reaches the history. `.outOfScope` is also the answer for a file that
/// is the person's own and in plain sight — in their watched `~/Downloads`,
/// passed by the root check and by `WatchScope` — whose *destination* is the
/// part the gate refused: a bucket folder somebody later replaced with a link
/// into iCloud Drive's `~/Library/Mobile Documents`, or anywhere else outside
/// the allowed folders. Nothing about such a file is a secret — its name is
/// what the history holds for every file the same rule moved yesterday.
///
/// What the history makes of that sweep is what these hold: one row per file
/// the sweep refused, each naming the file, and the pass still named after the
/// folder it swept. On disk, with the real engine.
final class AScopeRefusalOfThePersonsOwnFileIsStillLegibleTests: XCTestCase {

    private var home: URL!
    private var engine: AutopilotEngine!
    private var downloads: String { home.appendingPathComponent("Downloads").path }

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        // The bucket the images rule files into is now a link into `~/Library`.
        let fm = FileManager.default
        try fm.createDirectory(at: home.appendingPathComponent("Library/Mobile Documents/Pictures"),
                               withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: home.appendingPathComponent("Pictures Sorted"),
                                  withDestinationURL: home.appendingPathComponent(
                                      "Library/Mobile Documents/Pictures"))
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func folder() -> WatchedFolder {
        WatchedFolder(id: "dl", path: downloads, enabled: true, rules: [
            Rule(id: "pdf", name: "Papers", enabled: true, conditions: [.fileExtension(["pdf"])],
                 action: .move(to: home.appendingPathComponent("Papers").path)),
            Rule(id: "img", name: "Photos", enabled: true, conditions: [.fileExtension(["jpg"])],
                 action: .move(to: home.appendingPathComponent("Pictures Sorted").path)),
        ], depth: 1)
    }

    /// Three photos refused for their destination: the sweep says three, and
    /// the history — the only place a person can find out *which* — says one
    /// row with no name at all.
    func testEachRefusedFileOfThePersonsOwnFolderIsARowWithItsName() throws {
        for name in ["beach.jpg", "dog.jpg", "cake.jpg"] {
            try write("Downloads/\(name)", in: home)
        }
        let watched = folder()
        engine.folders = [watched]

        let report = engine.sweep(watched)
        XCTAssertEqual(report.folder, .read, "precondition: the root check let Downloads through")
        XCTAssertEqual(report.refused, 3, "precondition: all three were refused for the bucket")
        XCTAssertTrue(engine.history.allSatisfy {
            $0.kind == .refused && $0.detail == RuleOutcome.Refusal.outOfScope.rawValue
        }, "precondition: every record is a scope refusal")

        let summary = ActionHistory.summary(of: engine.history)
        XCTAssertEqual(summary.refused, report.refused,
                       "the page's «not completed» disagrees with the sweep that just ran")
        XCTAssertEqual(Set(engine.history.map(\.file)), ["beach.jpg", "dog.jpg", "cake.jpg"],
                       "which of the person's own files did not go is written nowhere")
    }

    /// The runner's other `.outOfScope`: «a folder cannot be moved inside
    /// itself», which its own comment calls reachable without malice. A rule
    /// filing names that begin with «Invoice» into `~/Downloads/Invoices` meets
    /// its own bucket on the next sweep — nothing planted, nothing outside the
    /// home, every path the person's. The history must still say which item it
    /// left alone.
    func testTheBucketARuleMetInItsOwnFolderIsNamed() throws {
        try write("Downloads/Invoice-march.pdf", in: home)
        // The bucket spelled the way the walk spells what it finds, so the
        // runner's own «inside itself» guard is the one that answers — spelled
        // through `/var` it misses and the move fails instead
        // (`ARuleNeverMovesItsOwnBucketIntoItselfTests`).
        // (`resolvingSymlinksInPath` would put `/var` back: it drops a
        // `/private` the path also exists without.)
        try XCTSkipUnless(downloads.hasPrefix("/var/"), "the scratch home is not under /var")
        let bucket = "/private" + downloads + "/Invoices"
        let rule = Rule(id: "inv", name: "Invoices", enabled: true,
                        conditions: [.name(.beginsWith, "Invoice")],
                        action: .move(to: bucket))
        let watched = WatchedFolder(id: "dl", path: downloads, enabled: true, rules: [rule], depth: 1)
        engine.folders = [watched]
        XCTAssertEqual(engine.sweep(watched).acted, 1, "precondition: the first sweep filed the PDF")

        let second = engine.sweep(watched)
        XCTAssertEqual(second.refused, 1, "precondition: the bucket itself was refused")
        let refused = engine.history.filter { $0.kind == .refused }
        XCTAssertEqual(refused.map(\.detail), [RuleOutcome.Refusal.outOfScope.rawValue],
                       "precondition: the refusal is the scope one")
        XCTAssertEqual(refused.map(\.file), ["Invoices"],
                       "the person's own bucket folder is a row with no name")
    }

    /// One pass that moved a PDF and was refused on a photo, both in Downloads:
    /// its header names Downloads. A record with an empty path is a second
    /// «folder» to the pass, and a pass from two folders is drawn with none.
    func testAPassThatMovedOneFileAndWasRefusedAnotherStillNamesItsFolder() throws {
        try write("Downloads/invoice.pdf", in: home)
        try write("Downloads/beach.jpg", in: home)
        let watched = folder()
        engine.folders = [watched]

        let report = engine.sweep(watched)
        XCTAssertEqual(report.acted, 1, "precondition: the PDF moved")
        XCTAssertEqual(report.refused, 1, "precondition: the photo was refused")

        let runs = ActionHistory.runs(of: engine.history)
        XCTAssertEqual(runs.count, 1, "precondition: one pass")
        XCTAssertEqual(runs.first?.records.count, 2)
        // The records carry the walk's spelling (`/private/var/…` for a scratch
        // home), so the folder is compared as the gate reads a folder.
        let named = try XCTUnwrap(runs.first?.folder,
                                  "the pass lost its folder name to a record with no path")
        XCTAssertTrue(WatchScope.sameFolder(named, downloads), "\(named) is not \(downloads)")
    }
}
