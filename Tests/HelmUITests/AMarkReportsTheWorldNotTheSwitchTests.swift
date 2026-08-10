import XCTest
@testable import HelmUI

/// The left of a settings row.
///
/// v3's whole idea is that one row answers two questions: the mark says what is
/// happening now, which is a fact from the engine, and the control says what is
/// configured, which is a value from the store. Two questions and one row only
/// works while the two halves stay out of each other's business — and the way
/// that breaks is a mark that starts reporting the switch.
final class AMarkReportsTheWorldNotTheSwitchTests: XCTestCase {

    func testARuleThatAppliesRightNowIsMarkedAsHolding() {
        XCTAssertEqual(HelmRowMark.of(enabled: true, satisfied: true), .holding)
    }

    /// The state that had no picture at all before v3, and the reason the mark
    /// exists: on, and doing nothing. Without it «my rule does not work» and
    /// «my rule is off» are the same row.
    func testARuleThatIsOnAndNotMetIsMarkedAsWaiting() {
        XCTAssertEqual(HelmRowMark.of(enabled: true, satisfied: false), .waiting)
    }

    /// The half that is easy to get wrong. A switched-off rule gets the mark's
    /// *width* and no mark: the switch beside it already says «off», and a grey
    /// dot would be the row saying one thing twice in two alphabets.
    func testARuleThatIsOffGetsNoMarkAtAll() {
        XCTAssertEqual(HelmRowMark.of(enabled: false, satisfied: false), .space)
    }

    /// And it stays `.space` even when the condition itself is true. The engine
    /// can perfectly well report «an external display is attached» while the
    /// rule that watches for one is switched off — that is not a reason the Mac
    /// is awake, and a tick there would claim it was.
    func testAnOffRuleIsNotMarkedByAConditionItIsNotWatching() {
        XCTAssertEqual(HelmRowMark.of(enabled: false, satisfied: true), .space,
                       "a rule nobody switched on took credit for the world")
    }

    /// `.none` is never chosen by this function — it is for cards whose rows
    /// carry no marks at all, where holding the width would indent every label
    /// for nothing.
    func testTheFactoryNeverAnswersNone() {
        for enabled in [true, false] {
            for satisfied in [true, false] {
                XCTAssertNotEqual(HelmRowMark.of(enabled: enabled, satisfied: satisfied), .none)
            }
        }
    }
}
