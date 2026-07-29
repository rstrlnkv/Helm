import Foundation
import XCTest
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The dry run is the one screen that has to be exhaustive: it is the promise
/// the person reads before letting a rule loose on a folder unattended.
///
/// `PreviewRow` is `Identifiable` by `name` — the file's last path component,
/// with nothing in front of it. Two files called `report.pdf`, one in
/// `Invoices/` and one in `Receipts/`, are two rows with one identity, and the
/// editor draws them with `ForEach(rvm.preview)`. SwiftUI given a duplicate id
/// does not draw both.
///
/// Same names in different folders is the ordinary case for a folder watched
/// deeper than one level: `report.pdf`, `IMG_0001.JPG`, `invoice.pdf`,
/// `index.html`, `Icon`.
final class PreviewRowIdentityTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-home-\(UUID().uuidString)")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "rules.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func write(_ relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 2_000).write(to: url)
    }

    /// Two files, one rule, one folder watched two levels deep.
    func testEveryFileTheRunWillTouchIsItsOwnRowInThePreview() throws {
        try write("Invoices/report.pdf")
        try write("Receipts/report.pdf")

        let folder = WatchedFolder(
            id: "f", path: root.path, enabled: true,
            rules: [Rule(id: "r", name: "PDFs", enabled: true, match: .all,
                         conditions: [.fileExtension(["pdf"])],
                         action: .addTag("Filed"))],
            depth: 2)

        let plans = engine.preview(folder)
        XCTAssertEqual(plans.count, 2, "both files match the rule and both will be acted on")

        let rows = plans.map(PreviewRow.init)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count,
                       "two rows, one identity — the list the person approves shows "
                       + "\(Set(rows.map(\.id)).count) of the \(rows.count) files the "
                       + "run will touch")
    }

    /// The same statement without a disk, so the defect is pinned to the type
    /// rather than to the walk: identity comes from the name, and a name is not
    /// what tells two files apart.
    func testTwoFilesAtDifferentPathsAreNotOneRow() {
        func plan(_ path: String) -> RulePlan {
            RulePlan(facts: FileFacts(name: (path as NSString).lastPathComponent,
                                      path: path, kind: .document, bytes: 10,
                                      added: Date(), modified: Date()),
                     rule: Rule(id: "r", name: "PDFs", enabled: true,
                                conditions: [.fileExtension(["pdf"])], action: .trash))
        }
        let one = PreviewRow(plan("/Users/r/Downloads/Invoices/report.pdf"))
        let other = PreviewRow(plan("/Users/r/Downloads/Receipts/report.pdf"))

        XCTAssertNotEqual(one.id, other.id,
                          "one of these two files is about to be trashed without ever "
                          + "appearing in the dry run")
    }
}
