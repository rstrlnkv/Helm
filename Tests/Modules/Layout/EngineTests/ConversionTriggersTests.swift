import XCTest
@testable import Module_Layout_Engine

/// The difference between ending a word and meaning it.
final class ConversionTriggersTests: XCTestCase {
    func testSpaceAndPunctuationConfirmByDefault() {
        let triggers = ConversionTriggers.default
        XCTAssertTrue(triggers.converts(.space))
        XCTAssertTrue(triggers.converts(.punctuation(".")))
    }

    /// Off by default: in a chat, Return sends the message and empties the
    /// field, so the correction is typed into an empty box and sent as a second
    /// message to somebody else.
    func testReturnDoesNotConfirmByDefault() {
        XCTAssertFalse(ConversionTriggers.default.converts(.newline))
        XCTAssertTrue(ConversionTriggers(onReturn: true).converts(.newline))
    }

    /// The tap cuts a word at anything that is not a letter, so digits and
    /// slashes arrive here too — and if they confirmed, the guards against
    /// digits and paths could never fire: `ghbdtn2024` became `привет2024`.
    func testOnlyRealPunctuationConfirms() {
        for character in Array(".,!?;:)]}\"'") {
            XCTAssertTrue(ConversionTriggers.default.converts(.punctuation(character)),
                          String(character))
        }
        for character in Array("0123456789/\\@~_-=+*&^%$#") {
            XCTAssertFalse(ConversionTriggers.default.converts(.punctuation(character)),
                           String(character))
        }
    }

    /// Going somewhere else is not confirming; converting then edits text the
    /// person has already left. Not offered as a choice, so it cannot be turned
    /// back on by accident.
    func testLeavingNeverConverts() {
        for triggers in [ConversionTriggers.default,
                         ConversionTriggers(onSpace: true, onReturn: true, onPunctuation: true)] {
            XCTAssertFalse(triggers.converts(.navigation))
            XCTAssertFalse(triggers.converts(.click))
            XCTAssertFalse(triggers.converts(.focusChange))
        }
    }

    func testEachEndingCanBeTurnedOffOnItsOwn() {
        XCTAssertFalse(ConversionTriggers(onSpace: false).converts(.space))
        XCTAssertTrue(ConversionTriggers(onSpace: false, onReturn: true).converts(.newline))
        XCTAssertFalse(ConversionTriggers(onReturn: false).converts(.newline))
        XCTAssertFalse(ConversionTriggers(onPunctuation: false).converts(.punctuation("!")))
    }

    /// A character is not an ending at all.
    func testTypingIsNeverATrigger() {
        XCTAssertFalse(ConversionTriggers.default.converts(.character("a")))
        XCTAssertFalse(ConversionTriggers.default.converts(.backspace))
    }
}
