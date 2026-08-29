import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

private final class FakeAnnouncer: AnnouncePort, @unchecked Sendable {
    var announced: [LayoutAnnouncement] = []
    func announce(_ what: LayoutAnnouncement) { announced.append(what) }
}

/// The module changes text in somebody else's app and switches the keyboard
/// under their hands, and to a VoiceOver reader all of it was silent: no other
/// module acts without a word, and this one acts on what is being typed. The
/// engine names what happened; what is said and how it reaches the reader is
/// the announcer's side of the port.
final class TheModuleSpeaksWhenItActsTests: XCTestCase {

    private func engine(tap: FakeTap, announcer: FakeAnnouncer,
                        automatic: Bool = true) -> LayoutEngine {
        let engine = LayoutEngine(
            tap: tap, typing: FakeTyping(), sources: FakeSources(current: "en"),
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]),
            secure: FakeSecure(), announcer: announcer, automatic: automatic, vocabulary: VocabularyStore(keys: SilentSealKey()))
        engine.activate()
        return engine
    }

    func testAConversionIsAnnouncedWithItsWords() {
        let tap = FakeTap()
        let announcer = FakeAnnouncer()
        let engine = engine(tap: tap, announcer: announcer)
        tap.type("ghbdtn"); tap.space()
        guard case .converted(let event)? = announcer.announced.last else {
            XCTFail("""
                a word was rewritten in another app and nothing was said: a \
                VoiceOver reader gets a changed sentence with no account of \
                who changed it or how to take it back.
                """)
            return
        }
        XCTAssertEqual(event.before, "ghbdtn")
        XCTAssertEqual(event.after, "привет")
        engine.deactivate()
    }

    func testASecureEpisodeIsAnnouncedOnceAtItsEntry() {
        let tap = FakeTap()
        let announcer = FakeAnnouncer()
        let secure = FakeSecure()
        let engine = LayoutEngine(
            tap: tap, typing: FakeTyping(), sources: FakeSources(),
            translation: FakeTranslation(table: [:]), spell: FakeSpell(valid: []),
            secure: secure, announcer: announcer, automatic: true, vocabulary: VocabularyStore(keys: SilentSealKey()))
        engine.activate()

        secure.secure = true
        tap.type("hunter2")
        XCTAssertEqual(announcer.announced, [.securePause], """
            the pause is announced at the edge of the episode and exactly once: \
            silence would leave a VoiceOver reader typing into a module that \
            stopped listening, and one announcement per keystroke would talk \
            over the password being typed.
            """)
        engine.deactivate()
    }

    func testTheGrantBeingTakenAwayIsAnnounced() {
        let tap = FakeTap()
        let announcer = FakeAnnouncer()
        let engine = engine(tap: tap, announcer: announcer)
        tap.macOSTakesItAway()
        XCTAssertEqual(announcer.announced.last, .grantLost, """
            macOS revoked the tap and the module said nothing: the page goes \
            «Not running» silently, which for a VoiceOver reader is a module \
            that simply stops fixing words with no account of why.
            """)
        engine.deactivate()
    }
}
