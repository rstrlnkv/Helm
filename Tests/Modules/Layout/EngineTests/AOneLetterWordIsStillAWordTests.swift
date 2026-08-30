import XCTest
@testable import Module_Layout_Engine

/// Russian's commonest words are one letter long, and the module refused every
/// one of them.
///
/// `LayoutVerdict.minimumLength` was 2, under a comment saying «one character is
/// a keystroke, not a word». That is an English sentence about a Russian
/// problem: English has `a` and `I`, Russian has `в`, `и`, `с`, `к`, `о`, `у`,
/// `а` and `я` — prepositions, conjunctions and a pronoun in almost every
/// sentence anybody types. Type `d ` on a latin layout and it stayed `d`.
///
/// **By list, and more strictly than at two letters.** A spell checker asked
/// about a single character answers noise, and the latin side of these keys —
/// `d`, `b`, `c`, `r`, `j`, `e`, `f`, `z` — is also what variable names, flags
/// and initials look like. The rule is the one the two- and three-letter words
/// already use: convert only *towards* a word on the list, and only when what
/// was typed is not on it.
final class AOneLetterWordIsStillAWordTests: XCTestCase {

    private func decide(_ word: String, _ translated: String,
                        typedIsWord: Bool = false, translatedIsWord: Bool = false)
    -> LayoutVerdict.Decision {
        LayoutVerdict.decide(word: word, translated: translated,
                             validAsTyped: typedIsWord, validTranslated: translatedIsWord,
                             exceptions: [])
    }

    func testEveryRussianOneLetterWordIsReachable() {
        let pairs = [("f", "а"), ("d", "в"), ("b", "и"), ("r", "к"),
                     ("j", "о"), ("c", "с"), ("e", "у"), ("z", "я")]
        for (typed, translated) in pairs {
            guard case .convert(let out) = decide(typed, translated) else {
                XCTFail("«\(typed)» was left alone; it is «\(translated)», which is a word "
                        + "people type constantly")
                continue
            }
            XCTAssertEqual(out, translated)
        }
    }

    /// `I` typed on a Russian layout is `Ш` — the case this started from.
    func testACapitalIComesBackFromTheRussianLayout() {
        guard case .convert(let out) = decide("Ш", "I") else {
            return XCTFail("«Ш» was left alone: it is «I», and the rule lowercases before it asks")
        }
        XCTAssertEqual(out, "I")
    }

    /// The control that stops «convert every single letter» from passing: a
    /// letter whose other side is not on the list is not a word, it is a
    /// keystroke.
    func testALetterThatIsNotAWordOnEitherSideIsLeftAlone() {
        for (typed, translated) in [("g", "п"), ("h", "р"), ("y", "н"), ("q", "й")] {
            guard case .leave = decide(typed, translated) else {
                return XCTFail("«\(typed)» was rewritten to «\(translated)», which is not a word "
                               + "in either language — one letter is a keystroke unless the list "
                               + "says otherwise")
            }
        }
    }

    /// And the rule that outranks everything still does: `a` is an English
    /// word, so it is what they meant, whatever the other side says.
    func testAWordOnTheListInBothDirectionsIsLeftAlone() {
        guard case .leave = decide("a", "ф") else {
            return XCTFail("«a» was rewritten; it is an English word and the typed form wins")
        }
    }

    /// A single letter must not borrow confidence from a longer word that
    /// starts with it — `и` is on the one-letter list, `и` inside «их» is a
    /// different question.
    func testOneLetterIsAnsweredFromTheOneLetterListOnly() {
        XCTAssertFalse(ShortWords.isCommon("н"), "«н» is not a word; «на» is")
        XCTAssertTrue(ShortWords.isCommon("и"))
        XCTAssertFalse(ShortWords.isCommon("t"), "«t» is not a word; «to» is")
    }
}
