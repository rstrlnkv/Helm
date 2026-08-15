import XCTest
@testable import Module_Layout_Engine

/// With all three triggers off no word is ever confirmed, so «Fix as I type»
/// is dead however green the badge is. The page needs the fact as one word to
/// draw the warning from; three separate toggles read one at a time cannot say
/// it, and a hand-assembled `&&` in the view is the spelling that drifts.
final class ThreeSwitchesOffIsADeadModuleTests: XCTestCase {

    func testAllThreeOffConfirmsNothing() {
        let triggers = ConversionTriggers(onSpace: false, onReturn: false,
                                          onPunctuation: false)
        XCTAssertTrue(triggers.fixesNothing)
        // The property is a promise about `converts`, not a parallel fact.
        XCTAssertFalse(triggers.converts(.space))
        XCTAssertFalse(triggers.converts(.newline))
        XCTAssertFalse(triggers.converts(.punctuation(".")))
    }

    func testAnySingleTriggerIsEnoughToLive() {
        XCTAssertFalse(ConversionTriggers.default.fixesNothing)
        XCTAssertFalse(ConversionTriggers(onSpace: true, onReturn: false,
                                          onPunctuation: false).fixesNothing)
        XCTAssertFalse(ConversionTriggers(onSpace: false, onReturn: true,
                                          onPunctuation: false).fixesNothing)
        XCTAssertFalse(ConversionTriggers(onSpace: false, onReturn: false,
                                          onPunctuation: true).fixesNothing)
    }
}
