import XCTest
import HelmContract
@testable import Module_Layout_Engine

private final class FakeTyping: TypingPort, @unchecked Sendable {
    var performed: [SwitchPlan] = []
    func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return true }
}

private final class FakeSecure: SecureContextPort, @unchecked Sendable {
    var secure = false
    var bundle = "com.apple.Notes"
    func isSecure() -> Bool { secure }
    func frontmostBundleID() -> String { bundle }
}

private struct FakeTranslation: TranslationPort {
    let table: [String: String]
    func translate(_ word: String, from: String, to: String) -> String? { table[word] }
}

private struct FakeSpell: SpellPort {
    let valid: Set<String>
    func isWord(_ word: String, sourceID: String) -> Bool? { valid.contains(word) }
}

private final class FakeTap: KeyTapPort, @unchecked Sendable {
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void) -> Bool {
        handler = onEvent
        return true
    }
    func stop() { handler = nil }
    func type(_ text: String) { for character in text { handler?(.character(character)) } }
    func space() { handler?(.space) }
}

private final class FakeSources: LayoutSourcePort, @unchecked Sendable {
    var selected: [String] = []
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) { selected.append(sourceID) }
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
        XCTAssertEqual(typing.performed.first?.insert, "привет")
        XCTAssertEqual(typing.performed.first?.backspaces, 6)
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
        XCTAssertEqual(typing.performed.last?.insert, "ghbdtn")
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
