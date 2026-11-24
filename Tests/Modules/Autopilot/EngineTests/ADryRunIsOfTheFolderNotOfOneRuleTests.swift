import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The dry run is of the folder as it will be, not of one rule on its own.
///
/// A folder's list is read top to bottom, first match wins, so a rule asked
/// about alone offers files a rule above it takes first. The preview is of the
/// whole folder with the draft in its place, and every row says which rule
/// takes it.
final class ADryRunIsOfTheFolderNotOfOneRuleTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        engine = AutopilotEngine.scratch(home: home.path)
    }

    private func rule(_ id: String, enabled: Bool = true,
                      _ conditions: [RuleCondition]) -> Rule {
        Rule(id: id, name: id, enabled: enabled, match: .all,
             conditions: conditions, action: .sortIntoSubfolder(.kind))
    }

    private func folder(_ rules: [Rule]) -> WatchedFolder {
        WatchedFolder(id: "f", path: root.path, enabled: true, rules: rules, depth: 1)
    }

    // MARK: - The folder the preview is asked about

    func testTheRuleBeingWrittenKeepsItsPlaceInTheOrder() {
        let list = folder([rule("first", [.fileExtension(["pdf"])]),
                           rule("second", [.name(.contains, "invoice")]),
                           rule("third", [.fileExtension(["png"])])])

        let probe = list.previewing(rule("second", [.name(.contains, "receipt")]))

        XCTAssertEqual(probe.rules.map(\.id), ["first", "second", "third"],
                       "the dry run reordered the rules it is a dry run of")
    }

    /// The whole point of a dry run: it answers a rule that is not switched on
    /// yet, because that is the decision it exists to inform.
    func testTheRuleBeingWrittenIsOnEvenWhenItsSwitchIsOff() {
        let list = folder([rule("only", enabled: false, [.fileExtension(["pdf"])])])

        let probe = list.previewing(rule("only", enabled: false, [.fileExtension(["pdf"])]))

        XCTAssertEqual(probe.rules.map(\.enabled), [true])
    }

    /// And every other rule is left exactly as the person has it: a rule they
    /// switched off does not take files in a preview of a folder where it will
    /// not take them.
    func testTheOtherRulesAreLeftAsTheyAre() {
        let list = folder([rule("off", enabled: false, [.fileExtension(["pdf"])]),
                           rule("mine", [.name(.contains, "invoice")])])

        let probe = list.previewing(rule("mine", [.name(.contains, "invoice")]))

        XCTAssertEqual(probe.rules.map(\.enabled), [false, true])
    }

    /// A rule being written for the first time is not in the folder's list yet —
    /// the editor is opened on a rule the page has only just made.
    func testARuleTheFolderHasNeverSeenGoesLast() {
        let list = folder([rule("first", [.fileExtension(["pdf"])])])

        let probe = list.previewing(rule("fresh", [.fileExtension(["png"])]))

        XCTAssertEqual(probe.rules.map(\.id), ["first", "fresh"])
    }

    /// The draft wins over what is stored: the preview answers the rule on
    /// screen, not the one before the last keystroke.
    func testTheDraftReplacesTheStoredRuleRatherThanJoiningIt() {
        let list = folder([rule("mine", [.fileExtension(["pdf"])])])

        let probe = list.previewing(rule("mine", [.name(.contains, "invoice")]))

        XCTAssertEqual(probe.rules.count, 1)
        XCTAssertEqual(probe.rules.first?.conditions, [.name(.contains, "invoice")])
    }

    // MARK: - What the folder's rules really do to the files in it

    /// End to end: «All PDFs» takes every PDF, so the narrower rule below it
    /// gets nothing, and the dry run names the rule that takes each file.
    func testAFileAnEarlierRuleTakesIsAttributedToThatRule() throws {
        try write("invoice-march.pdf", in: root, bytes: 10)
        try write("invoice-april.pdf", in: root, bytes: 10)
        try write("notes.pdf", in: root, bytes: 10)
        let all = Rule(id: "all", name: "All PDFs", enabled: true, match: .all,
                       conditions: [.fileExtension(["pdf"])],
                       action: .sortIntoSubfolder(.kind))
        let invoices = Rule(id: "inv", name: "Invoices", enabled: false, match: .all,
                            conditions: [.name(.contains, "invoice")],
                            action: .sortIntoSubfolder(.month))
        let list = folder([all, invoices])

        let rows = engine.preview(list.previewing(invoices)).map { PreviewRow($0, counters: CounterBook()) }

        XCTAssertEqual(rows.map(\.name).sorted(),
                       ["invoice-april.pdf", "invoice-march.pdf", "notes.pdf"])
        XCTAssertEqual(Set(rows.map(\.ruleID)), ["all"],
                       "the editor offered files a rule above it takes first")
        XCTAssertEqual(rows.filter { $0.ruleID == invoices.id }.count, 0,
                       "«Invoices» was shown as doing work it will never do")
    }

    /// What the earlier rule leaves alone reaches the one being written: both are
    /// on, the PDF is the first rule's and the text file is the second's, and the
    /// dry run of the folder shows each file with the rule that takes it.
    func testAFileTheEarlierRuleLeavesAloneReachesTheRuleBeingWritten() throws {
        try write("invoice-march.pdf", in: root, bytes: 10)
        try write("notes.txt", in: root, bytes: 10)
        let pdfs = Rule(id: "pdf", name: "All PDFs", enabled: true, match: .all,
                        conditions: [.fileExtension(["pdf"])],
                        action: .sortIntoSubfolder(.kind))
        let notes = Rule(id: "txt", name: "Notes", enabled: true, match: .all,
                         conditions: [.fileExtension(["txt"])],
                         action: .sortIntoSubfolder(.kind))

        let rows = engine.preview(folder([pdfs, notes]).previewing(notes)).map { PreviewRow($0, counters: CounterBook()) }

        XCTAssertEqual(Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.ruleID) }),
                       ["invoice-march.pdf": "pdf", "notes.txt": "txt"])
    }

    /// And with the earlier rule switched off, the same files come to the rule
    /// being written — so the reading above is about the order, not about the
    /// preview having stopped working.
    func testWithTheEarlierRuleOffTheFilesReachTheRuleBeingWritten() throws {
        try write("invoice-march.pdf", in: root, bytes: 10)
        let all = Rule(id: "all", name: "All PDFs", enabled: false, match: .all,
                       conditions: [.fileExtension(["pdf"])],
                       action: .sortIntoSubfolder(.kind))
        let invoices = Rule(id: "inv", name: "Invoices", enabled: false, match: .all,
                            conditions: [.name(.contains, "invoice")],
                            action: .sortIntoSubfolder(.month))

        let rows = engine.preview(folder([all, invoices]).previewing(invoices))
            .map { PreviewRow($0, counters: CounterBook()) }

        XCTAssertEqual(rows.map(\.ruleID), ["inv"])
    }
}
