import XCTest
import HelmRuntime
@testable import Module_Layout_Engine

/// **The capital fix asks the dictionary now, because the shape of the letters
/// cannot tell a slip from an abbreviation.**
///
/// `TypingHabits.corrected` sees two capitals and a lowercase third. That is a
/// Shift held a beat too long — and it is also `IPhone`, `IPad`, `IPods`,
/// `OSes`, `ТВшник`, `MPhil`. Measured by compiling the rule and running it: it
/// rewrote every one of them, in somebody else's application, mid-sentence.
/// Raising the threshold from three letters to four bought only the `CDs`
/// family; everything four letters and longer went on being corrupted, and the
/// note under the switch listed three refusals from which the only available
/// conclusion was that abbreviations were safe.
///
/// This was also the one path in the module that changed text without asking
/// anything: `convert` runs the whole `LayoutVerdict` gauntlet, and
/// `replaceWord` asked only about app scope and secure input.
///
/// A slip has a **word** behind it. `TypingHabits` stays a pure shape test —
/// that is all it can honestly be — and the engine asks whether what the shape
/// proposes is a word in the layout being typed in.
final class ASlipHasAWordBehindItTests: XCTestCase {

    private var typing = FakeTyping()
    private var tap = FakeTap()

    /// `valid` is the dictionary. Everything else is the same rig the module's
    /// other engine tests build.
    private func engine(dictionary valid: Set<String>) -> LayoutEngine {
        typing = FakeTyping(); tap = FakeTap()
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: FakeSources(),
            translation: FakeTranslation(table: [:]),
            spell: FakeSpell(valid: valid),
            secure: FakeSecure(), automatic: true,
            settings: Self.boundStore())
        engine.activate()
        return engine
    }

    /// **The switch is set in the store, not handed to `init`.**
    /// `reloadSettings` runs on `activate()` and assigns `fixCapitals` from the
    /// store over whatever the initialiser was given — the same shape
    /// `ConversionTriggers` had before it became a stateless enum. A test that
    /// passed `fixCapitals: true` would be testing a value the engine discards
    /// one line later.
    private static func boundStore() -> NamespacedStore {
        let store = NamespacedStore(namespace: LayoutEngine.moduleID,
                                    backing: InMemoryKeyValueStore())
        store.set(true, for: LayoutKey.fixCapitals)
        return store
    }

    /// The case the feature exists for.
    func testASlippedShiftIsStillCorrected() {
        let engine = engine(dictionary: ["Hello"])
        tap.type("HEllo"); tap.space()
        XCTAssertEqual(typing.performed.count, 1,
                       "a slipped Shift over a real word is what this rule is for")
        withExtendedLifetime(engine) {}
    }

    /// The case it was getting wrong, and the reason this file exists.
    func testAnAbbreviationIsLeftAloneBecauseTheCorrectionIsNotAWord() {
        for word in ["IPhone", "IPads", "OSes", "MPhil"] {
            let engine = engine(dictionary: ["Hello"])   // «Iphone» &c. are not in it
            tap.type(word); tap.space()
            XCTAssertTrue(typing.performed.isEmpty,
                          "\(word) was rewritten: the shape matched and nothing asked whether "
                          + "the result is a word")
            withExtendedLifetime(engine) {}
        }
    }

    /// **Nil is a refusal, not a yes.** `SpellPort`'s own contract says no
    /// dictionary must never be read as «not a word»; it must not be read as
    /// «go ahead» either, or the rule is back to shape alone on exactly the
    /// Macs where nothing can check it.
    func testNoDictionaryMeansNoCorrection() {
        let engine = engine(dictionary: [])
        tap.type("HEllo"); tap.space()
        XCTAssertTrue(typing.performed.isEmpty,
                      "with no dictionary the rule fell back to the shape test alone")
        withExtendedLifetime(engine) {}
    }

    /// And the shape test still refuses what it always refused, so the
    /// dictionary is an addition rather than a replacement.
    func testTheShapeTestStillRefusesShoutingAndDigits() {
        for word in ["HELLO", "MP3file"] {
            let engine = engine(dictionary: ["Hello", "Mp3file", "Hello"])
            tap.type(word); tap.space()
            XCTAssertTrue(typing.performed.isEmpty, "\(word) is not a slipped Shift")
            withExtendedLifetime(engine) {}
        }
    }
}
