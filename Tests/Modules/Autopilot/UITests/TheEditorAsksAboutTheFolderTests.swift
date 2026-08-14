import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The editor's half of «the dry run is of one rule alone».
///
/// The engine's half is `ADryRunIsOfTheFolderNotOfOneRuleTests`: a folder read
/// top to bottom, first match wins, every row naming the rule that takes it.
/// This is what the page does with that — it sends the folder rather than one
/// rule out of it, and it draws the rows another rule takes apart from its own,
/// because a list where they are one is the same promise the old preview made.
@MainActor
final class TheEditorAsksAboutTheFolderTests: XCTestCase {

    private func model(on wire: AutopilotWire) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: wire))
    }

    private func rule(_ id: String, enabled: Bool = false) -> Rule {
        Rule(id: id, name: id, enabled: enabled, conditions: [.fileExtension(["pdf"])],
             action: .sortIntoSubfolder(.kind))
    }

    private func row(_ file: String, rule: Rule) -> PreviewRow {
        PreviewRow(RulePlan(facts: FileFacts(name: file, path: "/tmp/watched/\(file)",
                                             kind: .document, bytes: 1,
                                             added: Date(), modified: Date()),
                            rule: rule))
    }

    // MARK: - What is asked

    func testThePreviewIsAskedAboutTheWholeFolder() async {
        let broad = rule("all", enabled: true)
        let mine = rule("mine")
        let folder = WatchedFolder(id: "f", path: "/tmp/watched", rules: [broad, mine])
        let wire = AutopilotWire(folders: [folder])
        let model = model(on: wire)

        await model.runPreview(for: folder, rule: mine)

        XCTAssertEqual(wire.previewed?.rules.map(\.id), ["all", "mine"],
                       "the editor asked about one rule and was answered about one rule")
        XCTAssertEqual(wire.previewed?.rules.map(\.enabled), [true, true],
                       "the rule being written is the one the dry run is about")
    }

    // MARK: - What is drawn

    /// The two lists the editor draws, split by identity rather than by name:
    /// two rules a person wrote can be called the same thing.
    func testTheRowsAnotherRuleTakesAreKeptApart() async {
        let broad = rule("all", enabled: true)
        let mine = rule("mine")
        let folder = WatchedFolder(id: "f", path: "/tmp/watched", rules: [broad, mine])
        let wire = AutopilotWire(folders: [folder],
                                 preview: [row("notes.pdf", rule: broad),
                                           row("invoice.pdf", rule: mine)])
        let model = model(on: wire)

        await model.runPreview(for: folder, rule: mine)

        XCTAssertEqual(model.previewByThisRule.map(\.name), ["invoice.pdf"])
        XCTAssertEqual(model.previewByOtherRules.map(\.name), ["notes.pdf"])
    }

    /// The measured case: every file goes to the rule above, and the editor has
    /// nothing of its own to show. It used to show two rows and name where they
    /// would go.
    func testARuleThatGetsNothingShowsNothingOfItsOwn() async {
        let broad = rule("all", enabled: true)
        let mine = rule("mine")
        let folder = WatchedFolder(id: "f", path: "/tmp/watched", rules: [broad, mine])
        let wire = AutopilotWire(folders: [folder],
                                 preview: [row("invoice-march.pdf", rule: broad),
                                           row("invoice-april.pdf", rule: broad)])
        let model = model(on: wire)

        await model.runPreview(for: folder, rule: mine)

        XCTAssertEqual(model.previewByThisRule, [],
                       "the editor promised two files to a rule that gets neither")
        XCTAssertEqual(model.previewByOtherRules.count, 2,
                       "and said nothing about where they really go")
    }

    /// A reply for a rule nobody is looking at any more is dropped, and the
    /// split does not resurrect it: both lists are empty once the editor has
    /// moved on.
    func testAnAnswerForAClosedEditorIsNotDrawn() async {
        let mine = rule("mine")
        let folder = WatchedFolder(id: "f", path: "/tmp/watched", rules: [mine])
        let wire = AutopilotWire(folders: [folder], preview: [row("invoice.pdf", rule: mine)])
        let model = model(on: wire)
        await model.runPreview(for: folder, rule: mine)
        XCTAssertEqual(model.previewByThisRule.count, 1, "precondition: it was drawn")

        model.clearPreview()

        XCTAssertEqual(model.previewByThisRule, [])
        XCTAssertEqual(model.previewByOtherRules, [])
    }
}
