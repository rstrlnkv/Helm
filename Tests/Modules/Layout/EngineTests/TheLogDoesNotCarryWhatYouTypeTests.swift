import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_Layout_Engine

/// This module reads every keystroke in every app, and nothing checked that
/// none of them reach the log.
///
/// The engine says so twice in its own comments — "Counts and shapes, never the
/// word itself", "the log carries no content" — and CLAUDE.md states the rule
/// for the whole app. Twenty-nine test files in this module, and not one of
/// them touches `HelmLog`. The promise was kept by discipline at each of the
/// eleven call sites and by nothing else.
///
/// The stake here is the highest in the app. A VPN name says where somebody
/// works; this sees what they write — in a chat window, a search field, a form
/// that is not secure-entry. `helm.log` has a "Copy log" button whose whole
/// purpose is pasting it into a bug report, and the file already had to be
/// deleted once, wholesale, when redaction arrived after it.
///
/// **Each test proves its own subject exists.** A test that only looks for the
/// absence of a word passes when nothing was logged at all — which is what a
/// test process does by default, since `LogPolicy` keeps the log off for a
/// build that is not `-dev`.
final class TheLogDoesNotCarryWhatYouTypeTests: XCTestCase {

    private final class FakeTyping: TypingPort, @unchecked Sendable {
        var performed: [SwitchPlan] = []
        var succeeds = true
        func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return succeeds }
    }

    private final class FakeSecure: SecureContextPort, @unchecked Sendable {
        var secure = false
        func isSecureInput() -> Bool { secure }
        func isSecure() -> Bool { secure }
        func frontmostBundleID() -> String { "com.acme.private-notes" }
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
        var modifiers: (@Sendable (ModifierTap.Input) -> Void)?
        func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
                   onModifier: @escaping @Sendable (ModifierTap.Input) -> Void) -> Bool {
            handler = onEvent
            modifiers = onModifier
            return true
        }
        func stop() { handler = nil }
        func type(_ text: String) { for character in text { handler?(.character(character)) } }
        func space() { handler?(.space) }
    }

    /// A word nobody would type by accident, so finding it in a message cannot
    /// be a coincidence — and its replacement, which is just as much the
    /// person's text.
    private let typed = "ghbdtn"
    private let replacement = "привет"

    private var typing = FakeTyping()
    private var tap = FakeTap()

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

    private func engine(typingSucceeds: Bool = true) -> LayoutEngine {
        typing = FakeTyping()
        typing.succeeds = typingSucceeds
        tap = FakeTap()
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: FakeSources(),
            translation: FakeTranslation(table: [typed: replacement]),
            spell: FakeSpell(valid: [replacement]),
            secure: FakeSecure(), automatic: true)
        engine.activate()
        return engine
    }

    private var layoutLines: [String] {
        HelmLog.shared.recentEntries().filter { $0.category == "layout" }.map(\.message)
    }

    func testAConversionDoesNotWriteTheWordOrItsReplacement() {
        let engine = engine()

        tap.type(typed); tap.space()

        XCTAssertFalse(typing.performed.isEmpty, "precondition: a conversion happened")
        XCTAssertTrue(layoutLines.contains { $0.contains("converted") },
                      "no conversion line was written, so this proves nothing: \(layoutLines)")
        XCTAssertFalse(layoutLines.contains { $0.contains(typed) },
                       "the log carries what was typed: \(layoutLines)")
        XCTAssertFalse(layoutLines.contains { $0.contains(replacement) },
                       "the log carries what it was replaced with: \(layoutLines)")
        withExtendedLifetime(engine) {}
    }

    /// The refusal path names a count of characters, and it is the line most
    /// likely to grow a "what we tried to write" while somebody is debugging a
    /// refusal.
    func testARefusedReplacementDoesNotWriteTheWordEither() {
        let engine = engine(typingSucceeds: false)

        tap.type(typed); tap.space()

        XCTAssertTrue(layoutLines.contains { $0.contains("refused a replacement") },
                      "no refusal line was written: \(layoutLines)")
        XCTAssertFalse(layoutLines.contains { $0.contains(typed) },
                       "the refusal names what was typed: \(layoutLines)")
        XCTAssertFalse(layoutLines.contains { $0.contains(replacement) },
                       "the refusal names the replacement: \(layoutLines)")
        withExtendedLifetime(engine) {}
    }

    /// And the app is a tag, not a bundle id — the same rule, one field over.
    func testTheAppIsRedacted() {
        let engine = engine()

        tap.type(typed); tap.space()

        XCTAssertFalse(layoutLines.isEmpty, "nothing was logged, so this proves nothing")
        XCTAssertFalse(layoutLines.contains { $0.contains("com.acme.private-notes") },
                       "the log names the app being typed into: \(layoutLines)")
        withExtendedLifetime(engine) {}
    }
}
