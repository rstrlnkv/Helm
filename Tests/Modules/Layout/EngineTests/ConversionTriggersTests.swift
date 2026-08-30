import XCTest
@testable import Module_Layout_Engine

/// Which endings of a word are taken as «I meant that word», and which merely
/// end it.
///
/// **This file used to prove branches production could not reach.**
/// `ConversionTriggers` was a struct of three `var`s, and `reloadSettings`
/// assigned `.default` over whatever the engine had been handed, on every
/// `activate()` — so the only code able to see `onReturn: true` was a test that
/// constructed it. The tests below were written against that freedom, and every
/// one of them passed over a combination no Mac could be in. A fake freer than
/// the port proves nothing about the port; the repair belongs to the type, and
/// the type is an enum now.
final class ConversionTriggersTests: XCTestCase {

    func testASpaceConfirmsTheWord() {
        XCTAssertTrue(ConversionTriggers.converts(.space))
    }

    /// Return does not, and the reason is chat clients: Return sends the
    /// message and empties the field, so the backspaces delete nothing, the
    /// correction is typed into an empty box, and the newline sends *that* —
    /// the other person receives the typo and then a second message correcting
    /// it.
    func testReturnDoesNotConfirm() {
        XCTAssertFalse(ConversionTriggers.converts(.newline))
    }

    /// Punctuation that ends a sentence confirms; a character that merely is
    /// not a letter does not. The tap ends a word at anything non-letter, so a
    /// digit or a slash arrives here too — and if those confirmed, the guards
    /// in `LayoutVerdict` against digits, paths and addresses could never fire,
    /// because the word would already have been cut before them.
    /// `ghbdtn2024` became `привет2024`; `~/ghbdtn/x` became `~/привет/x`.
    func testOnlyRealPunctuationConfirms() {
        for mark in ".,!?;:»)]}\"'…«(" {
            XCTAssertTrue(ConversionTriggers.converts(.punctuation(mark)),
                          "\(mark) ends a sentence and should confirm")
        }
        for other in "0123456789/@-_+=#$%^&*" {
            XCTAssertFalse(ConversionTriggers.converts(.punctuation(other)),
                           "\(other) ends the word without confirming it")
        }
    }

    /// The curly ones too: macOS substitutes them as you type, so a sentence
    /// ending in a typed quote arrives here as “ ” ‘ ’ and used to confirm
    /// nothing at all.
    func testTheQuotesMacOSSubstitutesConfirmToo() {
        for mark in "“”‘’" {
            XCTAssertTrue(ConversionTriggers.converts(.punctuation(mark)),
                          "\(mark) is what macOS types in place of a quote")
        }
    }

    /// Ending a word by going somewhere else is not confirming it — nor is a
    /// chord. ⌘Space, the gesture somebody makes on noticing the wrong layout,
    /// used to arrive as a plain space and budget a backspace for a character
    /// that never reached the field.
    func testLeavingIsNotConfirming() {
        for event in [TypingBuffer.Event.navigation, .chord(49), .click, .focusChange,
                      .backspace, .character("a")] {
            XCTAssertFalse(ConversionTriggers.converts(event), "\(event) confirms nothing")
        }
    }
}
