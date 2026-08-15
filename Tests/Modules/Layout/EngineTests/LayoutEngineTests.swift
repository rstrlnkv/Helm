import XCTest
import HelmContract
@testable import Module_Layout_Engine

final class FakeTyping: TypingPort, @unchecked Sendable {
    var performed: [SwitchPlan] = []
    var succeeds = true
    func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return succeeds }
}

final class FakeSecure: SecureContextPort, @unchecked Sendable {
    var secure = false
    var bundle = "com.apple.Notes"
    func isSecureInput() -> Bool { secure }
    func isSecure() -> Bool { secure }
    func frontmostBundleID() -> String { bundle }
}

struct FakeTranslation: TranslationPort {
    let table: [String: String]
    func translate(_ word: String, from: String, to: String) -> String? { table[word] }
}

struct FakeSpell: SpellPort {
    let valid: Set<String>
    func isWord(_ word: String, sourceID: String) -> Bool? { valid.contains(word) }
}

/// A tap that can be in the three states the real one can: watching, refused
/// for want of the grant, and stopped by macOS behind the app's back.
///
/// `start` used to return `true` unconditionally, so «macOS would not give us a
/// tap» and «macOS took the tap away» were states no test could write down —
/// which is why the second one shipped as a page that said «Active» with nobody
/// listening (CLAUDE.md § A fake simpler than the thing it stands for).
final class FakeTap: KeyTapPort, @unchecked Sendable {
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    var modifiers: (@Sendable (ModifierTap.Input) -> Void)?
    private var died: (@Sendable () -> Void)?
    /// Whether Accessibility is granted. False is a refusal, exactly as
    /// `AXIsProcessTrusted()` failing is.
    var grant = true
    /// How many taps have been asked for — the difference between «it was
    /// rebuilt» and «the engine still believes in the first one».
    var starts = 0
    /// Fired after each `start`, so a test can wait for the rebuild that the
    /// `didBecomeActive` observer performs on the main queue.
    var onStart: (@Sendable () -> Void)?

    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
               died: @escaping @Sendable () -> Void) -> Bool {
        starts += 1
        guard grant else { onStart?(); return false }
        handler = onEvent
        modifiers = onModifier
        self.died = died
        onStart?()
        return true
    }

    /// The grant is withdrawn mid-session: macOS disables the tap and the port
    /// stands down, which is a teardown the engine did not ask for.
    func macOSTakesItAway() {
        grant = false
        let announce = died
        stop()
        died = nil
        announce?()
    }
    /// One clean press and release of the bound key.
    func tapKey(_ code: Int64, at: TimeInterval = 0) {
        modifiers?(.down(code, at: at, othersHeld: false))
        modifiers?(.up(code, at: at + 0.05))
    }
    func stop() { handler = nil }
    func type(_ text: String) { for character in text { handler?(.character(character)) } }
    func space() { handler?(.space) }
}

/// A keyboard that is actually on the layout it was switched to.
///
/// `current()` used to answer `"en"` for ever, whatever `select()` had been
/// told — so "convert, then convert the next word back" was unrepresentable:
/// the engine reads `current()` at the top of every conversion, and in a test
/// the second one always started from where the first one had. No test could
/// have covered the sequence, whatever anybody wrote.
///
/// Shared rather than private because it was written out twice, in this file
/// and in `TheLogDoesNotCarryWhatYouTypeTests` — the arrangement where one copy
/// gets fixed. KeepAwake and VPN keep theirs in a `Fakes.swift` for the same
/// reason.
final class FakeSources: LayoutSourcePort, @unchecked Sendable {
    var selected: [String] = []
    private var live: String
    init(current: String = "en") { self.live = current }
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { live }
    func select(_ sourceID: String) { selected.append(sourceID); live = sourceID }
}

/// The newest state the engine published — `LocalTransport` replays the last
/// event per name to every new subscriber, so this is not racing the emit.
/// Beside the shared fakes for the reason they are here: three suites read the
/// state back and each had spelled this loop for itself.
func latestLayoutState(_ engine: LayoutEngine) async -> LayoutState? {
    for await event in engine.transport.events
    where event.name == LayoutEvent.layoutState.rawValue {
        return try? JSONDecoder().decode(LayoutState.self, from: event.payload)
    }
    return nil
}

/// The engine's own job is refusing: everything it does that is not a
/// conversion is a guard, and each of these is one of them.
final class LayoutEngineTests: XCTestCase {
    private var typing = FakeTyping()
    private var secure = FakeSecure()
    private var tap = FakeTap()
    private var sources = FakeSources()

    private func engine(automatic: Bool = true) -> LayoutEngine {
        typing = FakeTyping(); secure = FakeSecure(); tap = FakeTap(); sources = FakeSources()
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: sources,
            translation: FakeTranslation(table: ["ghbdtn": "привет", "ras": "кфы",
                                                 "qqqq": "ййыы"]),
            spell: FakeSpell(valid: ["привет", "ras"]),
            secure: secure, automatic: automatic)
        engine.activate()
        return engine
    }

    func testAMislayoutWordIsConvertedAndTheSourceFollows() {
        let engine = engine()
        tap.type("ghbdtn"); tap.space()
        // The space is deleted and put back with the replacement: it was
        // already in the field, and leaving it out of the count left the first
        // letter behind — `ghbdtn ` came back as `gпривет`.
        XCTAssertEqual(typing.performed.first?.insert, "привет ")
        XCTAssertEqual(typing.performed.first?.backspaces, 7)
        XCTAssertEqual(sources.selected, ["ru"], "the input source follows the text")
        withExtendedLifetime(engine) {}
    }

    /// A real word is left alone even though the fake can translate it.
    func testAValidWordIsUntouched() {
        let engine = engine()
        tap.type("ras"); tap.space()
        XCTAssertTrue(typing.performed.isEmpty)
        withExtendedLifetime(engine) {}
    }

    func testNonsenseInBothLayoutsIsUntouched() {
        let engine = engine()
        tap.type("qqqq"); tap.space()
        XCTAssertTrue(typing.performed.isEmpty)
        withExtendedLifetime(engine) {}
    }

    /// Secure input stops conversions and takes the buffer with it.
    func testSecureInputSuspends() {
        let engine = engine()
        secure.secure = true
        tap.type("ghbdtn"); tap.space()
        XCTAssertTrue(typing.performed.isEmpty)
        withExtendedLifetime(engine) {}
    }

    /// A blocked app never reaches the dictionary, let alone the keyboard.
    func testABlockedAppIsNotTouched() {
        let engine = engine()
        secure.bundle = "com.apple.Terminal"
        tap.type("ghbdtn"); tap.space()
        XCTAssertTrue(typing.performed.isEmpty)
        withExtendedLifetime(engine) {}
    }

    /// With automatic conversion off, typing does nothing — but the hotkey
    /// still works, because that is an explicit request.
    func testManualModeOnlyActsOnTheHotkey() {
        let engine = engine(automatic: false)
        tap.type("ghbdtn")
        XCTAssertTrue(typing.performed.isEmpty)
        engine.convertLastWord()
        XCTAssertEqual(typing.performed.first?.insert, "привет")
    }

    /// The hotkey converts a word the dictionary would have declined: the user
    /// has already decided.
    func testTheHotkeyIgnoresTheDictionary() {
        let engine = engine(automatic: false)
        tap.type("qqqq")
        engine.convertLastWord()
        XCTAssertEqual(typing.performed.first?.insert, "ййыы")
    }

    func testUndoRestoresTheOriginalOnlyOnce() {
        let engine = engine()
        tap.type("ghbdtn"); tap.space()
        engine.undoLast()
        XCTAssertEqual(typing.performed.last?.insert, "ghbdtn ",
                       "undo puts back exactly what was replaced, ending and all")
        let count = typing.performed.count
        engine.undoLast()
        XCTAssertEqual(typing.performed.count, count, "a second undo has nothing to undo")
    }

    /// The caret is elsewhere by then, and a blind edit would eat somebody's
    /// text in the other app.
    func testUndoRefusesInAnotherApp() {
        let engine = engine()
        tap.type("ghbdtn"); tap.space()
        let count = typing.performed.count
        secure.bundle = "com.apple.Mail"
        engine.undoLast()
        XCTAssertEqual(typing.performed.count, count)
    }

    /// The keystrokes a conversion sends must not be read back as typing, or
    /// the replacement is converted again, forever.
    func testTheEngineDoesNotReadItsOwnTyping() {
        let engine = engine()
        tap.type("ghbdtn"); tap.space()
        XCTAssertEqual(typing.performed.count, 1)
        tap.space()
        XCTAssertEqual(typing.performed.count, 1, "the buffer was cleared, not re-converted")
        withExtendedLifetime(engine) {}
    }
}

/// The cases the review pass named, each one a way to corrupt somebody's text.
extension LayoutEngineTests {
    /// Typing after a conversion moves the caret past it. Undoing then deletes
    /// a fixed number of characters from a different place: `привет vjq` became
    /// `приghbdtn `.
    func testTypingAfterAConversionCancelsTheUndo() {
        let engine = engine()
        tap.type("ghbdtn"); tap.space()
        let afterConversion = typing.performed.count
        tap.type("vjq")
        engine.undoLast()
        XCTAssertEqual(typing.performed.count, afterConversion,
                       "the caret has moved on; undo must refuse")
    }

    /// A command chord is not text and not a confirmation. ⌘Space — the gesture
    /// someone makes on noticing the wrong layout — used to arrive as a plain
    /// space and budget a backspace for a character that never reached the
    /// field, eating the one to its left.
    func testACommandChordEndsTheWordWithoutConverting() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.handler?(.chord)           // what a chord delivers
        XCTAssertTrue(typing.performed.isEmpty)

        // …and the word it ended is still available to the shortcut, which is
        // itself a chord and would otherwise destroy its own input.
        engine.convertLastWord()
        XCTAssertEqual(typing.performed.first?.insert, "привет")
    }

    /// The port says it failed; claiming a conversion on top of that would be
    /// the app reporting work it did not do.
    func testARefusedReplacementIsNotCountedAsOne() {
        typing = FakeTyping(); secure = FakeSecure(); tap = FakeTap(); sources = FakeSources()
        typing.succeeds = false
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: sources,
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]), secure: secure)
        engine.activate()
        tap.type("ghbdtn"); tap.space()
        XCTAssertTrue(sources.selected.isEmpty, "the input source must not follow a failure")
        engine.undoLast()
        XCTAssertEqual(typing.performed.count, 1, "nothing was recorded to undo")
    }
}
