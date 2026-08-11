import XCTest
@testable import Module_KeepAwake_Engine

/// The automation card indents every row by the mark column as soon as **one**
/// row could carry a mark, and the question «could one» was asked of the
/// settings rather than of the rows on screen.
///
/// «Keep awake with an external display» is not drawn on a Mac with no display of
/// its own — the rule means «docked», and a mini has no notion of docked. The
/// switch is still in the file, though, and a machine that was a laptop when the
/// plist was written has it set. So on a Studio with a migrated `true`, the card
/// counted a rule whose row does not exist: all five visible rows stepped 26 pt
/// right for a mark column that nothing could ever put a mark in — the indent
/// against nobody `HelmRowMark.spacer` exists to prevent, arrived at by another
/// route. It cannot be photographed here, because this Mac has a built-in
/// display, so the hardware is a parameter and the rule is a function.
///
/// The lid is the other half, and it is why this type exists rather than a
/// condition tucked into the page: the lid row now carries a mark of its own
/// when sleep is off, so «can a mark appear in this card» has two sources and
/// they must be one value — a second reader is a second clock, and the column
/// then disagrees with the marks it makes room for.
final class TheMarkColumnCountsDrawableRowsTests: XCTestCase {

    /// A Mac mini whose plist still says the display rule is on.
    func testADesktopDoesNotCountADisplayRuleItDoesNotDraw() {
        let rules = MarkableRules.of(autoExternalDisplay: true, autoPower: false,
                                     lidHolding: false,
                                     hasBuiltInDisplay: false, hasLid: false)
        XCTAssertFalse(rules.contains(.externalDisplay),
                       "the display rule is counted on a Mac that does not draw its row")
        XCTAssertTrue(rules.isEmpty,
                      "every row of the card is indented by a mark column no row can fill")
    }

    /// And the row it *does* draw still counts, or the fix above is «no marks on
    /// a desktop, ever».
    func testADesktopStillCountsThePowerRule() {
        let rules = MarkableRules.of(autoExternalDisplay: true, autoPower: true,
                                     lidHolding: false,
                                     hasBuiltInDisplay: false, hasLid: false)
        XCTAssertTrue(rules.contains(.power))
        XCTAssertFalse(rules.isEmpty)
    }

    /// A laptop draws both rows, so both count.
    func testALaptopCountsTheDisplayRule() {
        let rules = MarkableRules.of(autoExternalDisplay: true, autoPower: false,
                                     lidHolding: false,
                                     hasBuiltInDisplay: true, hasLid: true)
        XCTAssertTrue(rules.contains(.externalDisplay))
        XCTAssertFalse(rules.contains(.power))
    }

    /// Nothing switched on is the state a fresh install opens in, and it is the
    /// one the column must not appear for.
    func testNothingSwitchedOnMeansNoColumn() {
        let rules = MarkableRules.of(autoExternalDisplay: false, autoPower: false,
                                     lidHolding: false,
                                     hasBuiltInDisplay: true, hasLid: true)
        XCTAssertTrue(rules.isEmpty)
    }

    /// Sleep being off with the lid shut is the one thing this module does that
    /// outlives the process, and it is a mark on the lid's own row — so the
    /// column has to make room for it even with no rule switched on at all.
    func testTheLidHoldingMakesTheColumnPossibleOnItsOwn() {
        let rules = MarkableRules.of(autoExternalDisplay: false, autoPower: false,
                                     lidHolding: true,
                                     hasBuiltInDisplay: true, hasLid: true)
        XCTAssertTrue(rules.lidHolding)
        XCTAssertFalse(rules.isEmpty,
                       "the lid row carries a tick in a column that was never made room for")
    }

    /// …and it is not a rule. The lid is a switch that changes the whole Mac, and
    /// reading it as a condition would put its mark on the two rule rows.
    func testTheLidIsNotOneOfTheRules() {
        let rules = MarkableRules.of(autoExternalDisplay: false, autoPower: false,
                                     lidHolding: true,
                                     hasBuiltInDisplay: true, hasLid: true)
        for condition in ActiveCondition.allCases {
            XCTAssertFalse(rules.contains(condition),
                           "the lid was counted as \(condition.rawValue)")
        }
    }

    /// **An iMac, which is the third shape and was in none of the readings above.**
    ///
    /// `MacHardware` answers three questions from two facts — `hasLid` *is*
    /// `hasBattery`, and `hasBuiltInDisplay` is «a battery, or the window server
    /// says a panel is built in» — so the machines this function can be asked
    /// about are a laptop (both true), a mini/Studio/Pro (both false) and an iMac:
    /// a panel of its own and no lid. The two cases written above are the first
    /// two, and a desktop that draws the display row was left to be assumed.
    ///
    /// It has to count the display rule, because the row is on its page, and it
    /// has to ignore the lid, because that row is not — the pair a fix that tied
    /// the two hardware questions together would break, in the one direction this
    /// Mac cannot photograph.
    func testAniMacCountsTheDisplayRuleAndNeverTheLid() {
        let rules = MarkableRules.of(autoExternalDisplay: true, autoPower: false,
                                     lidHolding: true,
                                     hasBuiltInDisplay: true, hasLid: false)
        XCTAssertTrue(rules.contains(.externalDisplay),
                      "the row is drawn on an iMac and its mark is not counted")
        XCTAssertFalse(rules.lidHolding,
                       "an iMac has no lid, and the row that would carry this mark is not drawn")
        XCTAssertFalse(rules.isEmpty)
    }

    /// A Mac with no lid cannot be holding sleep off with it, whatever arrives
    /// over the wire — the same rule as the display row, one row down.
    func testAMacWithNoLidNeverReportsTheLidHolding() {
        let rules = MarkableRules.of(autoExternalDisplay: false, autoPower: false,
                                     lidHolding: true,
                                     hasBuiltInDisplay: false, hasLid: false)
        XCTAssertFalse(rules.lidHolding)
        XCTAssertTrue(rules.isEmpty)
    }
}
