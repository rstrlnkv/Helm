import XCTest
@testable import Module_Layout_Engine

/// The difference between ending a word and meaning it.
final class ConversionTriggersTests: XCTestCase {
    func testTheThreeConfirmingEndingsAreOnByDefault() {
        let triggers = ConversionTriggers.default
        XCTAssertTrue(triggers.converts(.space))
        XCTAssertTrue(triggers.converts(.newline))
        XCTAssertTrue(triggers.converts(.punctuation(".")))
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
        XCTAssertTrue(ConversionTriggers(onSpace: false).converts(.newline))
        XCTAssertFalse(ConversionTriggers(onReturn: false).converts(.newline))
        XCTAssertFalse(ConversionTriggers(onPunctuation: false).converts(.punctuation("!")))
    }

    /// A character is not an ending at all.
    func testTypingIsNeverATrigger() {
        XCTAssertFalse(ConversionTriggers.default.converts(.character("a")))
        XCTAssertFalse(ConversionTriggers.default.converts(.backspace))
    }
}
