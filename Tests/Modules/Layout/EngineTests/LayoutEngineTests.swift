import HelmTestSupport
import HelmRuntime
import XCTest
import HelmContract
@testable import Module_Layout_Engine

/// The newest state the engine published — `stream()` hands every new
/// subscriber the latest one first, so this is not racing the emit.
/// Beside the shared fakes for the reason they are here: three suites read the
/// state back and each had spelled this loop for itself.
func latestLayoutState(_ engine: LayoutEngine) async -> LayoutState? {
    for await state in engine.stream() { return state }
    return nil
}

/// Asks the engine to re-read the store and returns once the re-read is in force.
func rereadSettings(_ engine: LayoutEngine) async {
    await withCheckedContinuation { continuation in
        engine.settingsChanged(then: { continuation.resume() })
    }
}

/// The fixture both classes below build on, so the split into two classes
/// does not copy it. Holds no test.
class LayoutEngineRig: XCTestCase {
    fileprivate var typing = FakeTyping()
    fileprivate var secure = FakeSecure()
    fileprivate var tap = FakeTap()
    fileprivate var sources = FakeSources()

    fileprivate func engine(automatic: Bool = true) -> LayoutEngine {
        typing = FakeTyping(); secure = FakeSecure(); tap = FakeTap(); sources = FakeSources()
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: sources,
            translation: FakeTranslation(table: ["ghbdtn": "привет", "ras": "кфы",
                                                 "qqqq": "ййыы"]),
            spell: FakeSpell(valid: ["привет", "ras"]),
            secure: secure, activation: FakeActivation(), automatic: automatic,
            settings: layoutStore(bound: true))
        engine.activate()
        return engine
    }
}

/// The engine's own job is refusing: everything it does that is not a
/// conversion is a guard, and each of these is one of them.
final class LayoutEngineTests: LayoutEngineRig {
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
        tap.handler?(.chord(layoutShortcut))           // what a chord delivers
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
            spell: FakeSpell(valid: ["привет"]), secure: secure, activation: FakeActivation())
        engine.activate()
        tap.type("ghbdtn"); tap.space()
        XCTAssertTrue(sources.selected.isEmpty, "the input source must not follow a failure")
        engine.undoLast()
        XCTAssertEqual(typing.performed.count, 1, "nothing was recorded to undo")
    }
}
