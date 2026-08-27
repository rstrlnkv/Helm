import HelmUI
import XCTest
@testable import Module_Layout_UI

/// «Undo it by pressing the key again» was true for exactly one keystroke.
///
/// The right to a blind undo dies the moment anything else is typed —
/// `UndoRecord.invalidate()`, called from the engine's event handler — but the
/// row on the page carries no such condition and stays there for the rest of
/// the session. Following it one beat late is not a no-op: `fix()` finds no
/// live undo, falls through to `convertLastWord()`, and that path forces a
/// conversion past the dictionary. Type `hello`, press the key expecting an
/// undo, and a valid English word is replaced by `руддщ` — by the control the
/// page told you to press.
///
/// The repair is the sentence, not a new field on the state. A flag saying
/// «still undoable» would be a second fact about the same thing, published on
/// its own schedule — the state is emitted on change, not on every keystroke,
/// so it would go stale exactly the way the sentence did. A sentence that
/// carries its own condition cannot.
///
/// Parameterized by language rather than reading `AppLanguage.current`: this
/// Mac's `AppleLanguages` is `("ru-RU","en-US")`, so a bare assertion reads
/// Russian and an English mutation would pass.
@MainActor
final class TheUndoPromiseNamesItsConditionTests: XCTestCase {

    /// What «before you type anything else» is in each language. The condition
    /// is the whole point of the sentence, so it is checked in all eight rather
    /// than in whichever one this machine is set to.
    private let condition: [AppLanguage: String] = [
        .en: "before you type anything else",
        .ru: "до того, как наберёте что-то ещё",
        .es: "antes de escribir nada más",
        .fr: "avant de taper autre chose",
        .de: "bevor du etwas anderes tippst",
        .pt: "antes de digitar mais nada",
        .ja: "何か入力する前に",
        .zh: "在继续输入之前",
    ]

    func testTheLastChangeNoteSaysWhenTheUndoStillWorks() throws {
        for language in AppLanguage.allCases {
            let expected = try XCTUnwrap(condition[language], "no condition written for \(language)")
            let line = LyStr.undoHint(gesture: "Right ⌘", language: language)
            XCTAssertTrue(line.contains(expected),
                          "\(language) promises an undo without saying when it still works: \(line)")
        }
    }

    /// The introduction makes the same promise on the first run, and it was the
    /// same sentence with the same silence.
    func testTheIntroductionSaysItToo() throws {
        for language in AppLanguage.allCases {
            let expected = try XCTUnwrap(condition[language])
            let line = LyStr.introUndo(gesture: "Right ⌘", language: language)
            XCTAssertTrue(line.contains(expected),
                          "\(language) introduces an undo without its condition: \(line)")
        }
    }

    /// And VoiceOver hears it spoken, where there is no row to go back and read
    /// again. This one already knew whether an undo existed — it takes
    /// `undoable` — so what was missing is only how long it lasts.
    func testWhatVoiceOverHearsCarriesTheConditionToo() throws {
        for language in AppLanguage.allCases {
            let expected = try XCTUnwrap(condition[language])
            let line = LyStr.fixedAnnouncement(before: "ghbdtn", after: "привет",
                                               undoable: true, language: language)
            XCTAssertTrue(line.contains(expected),
                          "\(language) announces an undo without its condition: \(line)")
        }
    }

    /// The control: with no undo to offer, the announcement must not grow the
    /// condition either — a sentence about when to press a key nobody may press
    /// is worse than silence.
    func testNothingIsPromisedWhenThereIsNoUndo() throws {
        for language in AppLanguage.allCases {
            let expected = try XCTUnwrap(condition[language])
            let line = LyStr.fixedAnnouncement(before: "ghbdtn", after: "привет",
                                               undoable: false, language: language)
            XCTAssertFalse(line.contains(expected),
                           "\(language) told somebody when to undo a change that cannot be: \(line)")
        }
    }
}
