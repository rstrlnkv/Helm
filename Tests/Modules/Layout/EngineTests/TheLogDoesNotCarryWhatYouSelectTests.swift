import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// The selection path edits text Helm never watched being typed — a paragraph,
/// a password somebody selected to check, a message someone else wrote — and it
/// has two log lines of its own that `TheLogDoesNotCarryWhatYouTypeTests` never
/// reaches: the decline («no conversion for N characters») and the refusal
/// («refused by <app>»). Both are the lines most likely to grow a «what we
/// tried to write» while somebody is debugging, and the stake is higher than
/// the word path's: a selection can be anything at all.
///
/// Each test proves its own subject exists first — an absence alone is green
/// when nothing was logged at all, which is the default in a test process.
final class TheLogDoesNotCarryWhatYouSelectTests: XCTestCase {

    private final class Selection: SelectionPort, @unchecked Sendable {
        var text: String?
        var accepts = true
        func selectedText() -> String? { text }
        func selectedTextWithoutClipboard() -> String? { text }
        func replaceSelection(with text: String) -> Bool { accepts }
    }

    /// Text nobody would select by accident, so finding it in the log cannot
    /// be a coincidence.
    private let selected = "ghbdtn xbcnj"
    private let replacement = "привет чисто"

    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var layoutLines: [String] {
        HelmLog.shared.recentEntries().filter { $0.category == "layout" }.map(\.message)
    }

    private func engine(selection: Selection,
                        table: [String: String]) -> LayoutEngine {
        let engine = LayoutEngine(
            tap: FakeTap(), typing: FakeTyping(), sources: FakeSources(current: "en"),
            translation: FakeTranslation(table: table),
            spell: FakeSpell(valid: Set(table.values)),
            secure: FakeSecure(), selection: selection)
        engine.activate()
        return engine
    }

    /// The translation declines, and the engine says so with a count — the one
    /// shape of that line that is safe to paste into a bug report.
    func testADeclinedSelectionLogsACountAndNotTheText() async throws {
        let selection = Selection()
        selection.text = selected
        let engine = engine(selection: selection, table: [:])

        _ = try await engine.transport.send(
            EngineCommand(name: LayoutCommand.convertSelection.rawValue))

        XCTAssertTrue(layoutLines.contains { $0.contains("selection left alone") },
                      "no decline line was written, so this proves nothing: \(layoutLines)")
        XCTAssertFalse(layoutLines.contains { $0.contains(selected) }, """
            the decline names the selected text, which can be anything at all — \
            a password somebody selected to check included: \(layoutLines)
            """)
        engine.deactivate()
    }

    /// The app refuses the replacement; the warning names the app as a tag and
    /// neither side of the conversion.
    func testARefusedSelectionReplacementNamesNoTextAndNoApp() async throws {
        let selection = Selection()
        selection.text = selected
        selection.accepts = false
        let engine = engine(selection: selection,
                            table: ["ghbdtn": "привет", "xbcnj": "чисто",
                                    selected: replacement])

        _ = try await engine.transport.send(
            EngineCommand(name: LayoutCommand.convertSelection.rawValue))

        XCTAssertTrue(layoutLines.contains { $0.contains("refused") },
                      "no refusal line was written, so this proves nothing: \(layoutLines)")
        XCTAssertFalse(layoutLines.contains { $0.contains(selected) },
                       "the refusal names what was selected: \(layoutLines)")
        XCTAssertFalse(layoutLines.contains { $0.contains(replacement) },
                       "the refusal names the replacement: \(layoutLines)")
        XCTAssertFalse(layoutLines.contains { $0.contains("com.apple.Notes") },
                       "the refusal names the app being typed into: \(layoutLines)")
        engine.deactivate()
    }
}
