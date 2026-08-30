import HelmContract
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// **One gesture, two doors, one set of refusals — and only one door has them.**
///
/// `fix()` looks at what is selected and, finding nothing, converts the last
/// word. Both outcomes are the same key press to the person making it. The word
/// door ends in `LayoutVerdict.decideForced`, which skips the dictionary — the
/// person asked for this word by name — and still refuses two things outright:
///
/// - a word on «Never change these words», in either form, because the list is
///   the person's own instruction and a later one than the gesture; and
/// - a translation that turns a letter into a mark, because somebody typing
///   letters meant letters.
///
/// The selection door never reaches `LayoutVerdict` at all. `transform` builds a
/// `SelectionTransform` straight out of `TranslationPort` and writes whatever
/// comes back. So the same key press, on the same word, honours the list when
/// nothing is selected and ignores it when the word is selected — which is the
/// harder half to notice, because selecting the word first is what somebody
/// does when the automatic path has *already* refused it.
///
/// The page's own promise has no footnote: «Never change these words» over
/// «These are left exactly as you typed them, whatever the dictionary thinks.»
final class TheSelectionAnswersTheSameRefusalsTests: XCTestCase {

    // MARK: - Ports

    private final class Typing: TypingPort, @unchecked Sendable {
        var performed: [SwitchPlan] = []
        var succeeds = true
        func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return succeeds }
    }

    /// Both halves of the secure check, kept apart the way the port keeps them:
    /// `isSecureInput` is the system-wide syscall, `isSecure` also recognises an
    /// app's own password field. Neither is on in this suite — they are here so
    /// the fake cannot answer one question for the other.
    private final class Context: SecureContextPort, @unchecked Sendable {
        var bundle = "com.apple.Notes"
        var systemWideSecure = false
        var passwordField = false
        func isSecureInput() -> Bool { systemWideSecure }
        func isSecure() -> Bool { systemWideSecure || passwordField }
        func frontmostBundleID() -> String { bundle }
    }

    /// Keyed by direction, because the selection path asks both ways round
    /// (`TwoWayConversion`) and a table that ignores the pair cannot tell the
    /// two apart — the real `UCTranslation` reads two different layouts and can
    /// answer nil for one of them.
    private struct Translation: TranslationPort {
        let table: [String: [String: String]]
        func translate(_ word: String, from: String, to: String) -> String? {
            table["\(from)>\(to)"]?[word]
        }
    }

    /// Nil is «no dictionary for this language», which the port's contract says
    /// must never be read as «not a word» — so the fake can answer it.
    private struct Spell: SpellPort {
        let valid: Set<String>
        let noDictionary: Set<String>
        func isWord(_ word: String, sourceID: String) -> Bool? {
            noDictionary.contains(sourceID) ? nil : valid.contains(word)
        }
    }

    private final class Tap: KeyTapPort, @unchecked Sendable {
        var handler: (@Sendable (TypingBuffer.Event) -> Void)?
        var modifiers: (@Sendable (ModifierTap.Input) -> Void)?
        var grant = true
        func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
                   onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
                   died: @escaping @Sendable () -> Void) -> Bool {
            guard grant else { return false }
            handler = onEvent
            modifiers = onModifier
            return true
        }
        func stop() { handler = nil; modifiers = nil }
    }

    private final class Sources: LayoutSourcePort, @unchecked Sendable {
        var selected: [String] = []
        private var live: String
        private let all: [String]
        init(current: String, installed: [String]) { live = current; all = installed }
        func installed() -> [String] { all }
        func current() -> String? { live }
        func select(_ sourceID: String) { selected.append(sourceID); live = sourceID }
    }

    /// The tree and the clipboard are two readings, as they are in the port:
    /// `selectedTextWithoutClipboard` is the accessibility tree alone, and
    /// `selectedText` falls through to ⌘C when the tree says nothing. And the
    /// replace can be refused, which is the state an app that will not take
    /// synthesised edits is permanently in.
    private final class Selection: SelectionPort, @unchecked Sendable {
        var treeText: String?
        var clipboardText: String?
        var accepts = true
        var replaced: [String] = []
        func selectedText() -> String? { treeText ?? clipboardText }
        func selectedTextWithoutClipboard() -> String? { treeText }
        func replaceSelection(with text: String) -> Bool {
            guard accepts else { return false }
            replaced.append(text)
            return true
        }
    }

    // MARK: - The world

    /// `ras` is nonsense in English and `кфы` is nonsense in Russian, so nothing
    /// here leans on a dictionary being generous. `las[` is the measured real
    /// case from `LayoutVerdict.turnsALetterIntoAMark`: `дфых` read through the
    /// other layout puts a bracket where a letter was, and `NSSpellChecker`
    /// accepts it as an English word — a trailing mark does not trouble it.
    private let table: [String: [String: String]] = [
        "en>ru": ["ghbdtn": "привет"],
        "ru>en": ["привет": "ghbdtn", "дфых": "las["],
    ]

    private func engine(current: String,
                        exceptions: [String],
                        typing: Typing,
                        selection: Selection,
                        sources: Sources) -> LayoutEngine {
        let engine = LayoutEngine(
            tap: Tap(), typing: typing, sources: sources,
            translation: Translation(table: table),
            spell: Spell(valid: ["привет", "las["], noDictionary: []),
            secure: Context(),
            selection: selection,
            ledger: LedgerStore(),
            exceptions: exceptions,
            automatic: false)
        engine.activate()
        return engine
    }

    private func convertSelection(_ engine: LayoutEngine) async throws {
        _ = try await engine.transport.send(
            EngineCommand(name: LayoutCommand.convertSelection.rawValue))
    }

    // MARK: - The control, first

    /// Nothing is asserted below unless this passes: an absence proves nothing
    /// when the subject never happened, and «the selection was not replaced» is
    /// green in a world where no selection is ever replaced.
    func testASelectedWordIsConvertedWhenItIsOnNoList() async throws {
        let typing = Typing()
        let selection = Selection()
        selection.treeText = "ghbdtn"
        let engine = engine(current: "en", exceptions: [], typing: typing,
                            selection: selection,
                            sources: Sources(current: "en", installed: ["en", "ru"]))
        try await convertSelection(engine)
        XCTAssertEqual(selection.replaced, ["привет"],
                       "precondition: the selection path converts an ordinary word")
        engine.deactivate()
    }

    // MARK: - The never-list

    /// The person put `ghbdtn` on «Never change these words» because Helm kept
    /// rewriting it. The automatic path stopped; the gesture stopped. Then they
    /// select the word — which is what somebody does when the module has been
    /// refusing to touch it — and press the same key. It is rewritten.
    func testANeverListedWordIsNotConvertedBecauseItWasSelected() async throws {
        let typing = Typing()
        let selection = Selection()
        selection.treeText = "ghbdtn"
        let engine = engine(current: "en", exceptions: ["ghbdtn"], typing: typing,
                            selection: selection,
                            sources: Sources(current: "en", installed: ["en", "ru"]))
        try await convertSelection(engine)
        XCTAssertEqual(selection.replaced, [], """
            the word is on «Never change these words» and selecting it was \
            enough to get it converted: the identical gesture with nothing \
            selected goes through `LayoutVerdict.decideForced`, which refuses \
            the list outright, and the selection door consults no verdict at all.
            """)
        engine.deactivate()
    }

    /// Both forms, as `decide` and `decideForced` each check them: somebody
    /// tired of seeing `привет` appear writes down the word they keep *seeing*,
    /// not the one they typed.
    func testTheConvertedFormOnTheListCountsForASelectionToo() async throws {
        let typing = Typing()
        let selection = Selection()
        selection.treeText = "ghbdtn"
        let engine = engine(current: "en", exceptions: ["привет"], typing: typing,
                            selection: selection,
                            sources: Sources(current: "en", installed: ["en", "ru"]))
        try await convertSelection(engine)
        XCTAssertEqual(selection.replaced, [], """
            the list entry names the converted form and the selection was \
            converted into it anyway — the two word paths check both forms for \
            exactly this reason, and this one answers to neither.
            """)
        engine.deactivate()
    }

    // MARK: - A letter is not a mark

    /// The other absolute refusal, and the same door is missing it.
    ///
    /// `дфых` read through the other layout is `las[` — measured, and the
    /// reason `turnsALetterIntoAMark` exists: opening the key table so `,` can
    /// be `б` gave every letter a key in the other direction too, and some of
    /// those type punctuation. A spell checker accepts `las[`, so nothing else
    /// stops it. The word path refuses it even when the person asked by name,
    /// because a bracket where a letter was is not the word they asked for.
    func testASelectionIsNotConvertedIntoAWordWithAMarkWhereALetterWas() async throws {
        let typing = Typing()
        let selection = Selection()
        selection.treeText = "дфых"
        let engine = engine(current: "ru", exceptions: [], typing: typing,
                            selection: selection,
                            sources: Sources(current: "ru", installed: ["ru", "en"]))
        try await convertSelection(engine)
        XCTAssertEqual(selection.replaced, [], """
            four letters were replaced by three letters and a bracket. Both \
            word verdicts refuse this — `decide` and `decideForced` alike — and \
            the selection path, which edits text Helm has never seen and is \
            supposed to be the stricter of the two mechanisms, applies neither.
            """)
        engine.deactivate()
    }
}
