import HelmContract
import XCTest
@testable import Module_Layout_Engine

private final class CountingSelection: SelectionPort, @unchecked Sendable {
    var text: String?
    var replaced: [String] = []
    func selectedText() -> String? { text }
    func selectedTextWithoutClipboard() -> String? { text }
    func replaceSelection(with text: String) -> Bool { replaced.append(text); return true }
}

/// The page's one figure is «words fixed today», and the selection path fixes
/// words without ever telling it.
///
/// `convert` ends a success with `conversions.add` and `emitState`, so the
/// counter the descriptor calls the module's reason to be glanced at moves.
/// `transform` — the same fix, reached through the gesture on a selection or
/// through `convertSelection` — replaces the text, plays the sound, and ends
/// there: no count, no emit. Somebody who fixes their words by selecting them
/// reads «0 words fixed today» on a page describing a day of fixes.
final class ASelectionPutRightIsAWordFixedTodayTests: XCTestCase {

    /// A state the engine published that answers the question being asked.
    ///
    /// **Not «the first one».** `activate()` emits too, so the stream can hold
    /// the state from before the fix — and taking the first event read that
    /// one, which is a count taken over a moving subject. It passed alone and
    /// failed in a full run, which is exactly the shape that habit produces.
    ///
    /// Bounded rather than open-ended: a `for await` with no end hangs the
    /// suite when the fix never lands, and a hung test says far less than a
    /// failed one.
    private func published(by engine: LayoutEngine,
                           matching: @Sendable @escaping (LayoutState) -> Bool)
    async -> LayoutState? {
        var seen = 0
        for await event in engine.transport.events
        where event.name == LayoutEvent.layoutState.rawValue {
            seen += 1
            if let state = try? JSONDecoder().decode(LayoutState.self, from: event.payload),
               matching(state) { return state }
            if seen >= 8 { return nil }
        }
        return nil
    }

    func testAConvertedSelectionMovesTheDaysCount() async throws {
        let selection = CountingSelection()
        let engine = LayoutEngine(
            tap: FakeTap(), typing: FakeTyping(), sources: FakeSources(current: "en"),
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]),
            secure: FakeSecure(), selection: selection)
        engine.activate()

        selection.text = "ghbdtn"
        _ = try await engine.transport.send(
            EngineCommand(name: LayoutCommand.convertSelection.rawValue))
        XCTAssertEqual(selection.replaced, ["привет"],
                       "precondition: the selection was put right — without a fix the "
                       + "count below is rightly zero")

        let state = await published(by: engine) { $0.totals.today.words >= 1 }
        XCTAssertEqual(state?.totals.today.words, 1, """
            a selection was fixed and the day's count never heard: the page reads \
            «0 words fixed today» after a fix, because `transform` neither counts \
            a success nor emits the state the page draws.
            """)
        engine.deactivate()
    }
}
