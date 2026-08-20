import XCTest
@testable import HelmApp

/// **Nobody who hid their panel footer gets it back, and nobody who kept one
/// loses it.**
///
/// The panel's footer was three switches — Settings, Quit, and the pencil — and
/// one taste: `HelmPanel`'s own `showsFooter` was
/// `showSettingsButton || showQuitButton || showEditButton`, so the only thing
/// the three of them together decided was whether there was a footer at all.
/// They are one switch now, and the fold below **is** that expression, which is
/// what makes the migration a rename rather than a change of mind.
///
/// Each of the three defaulted to true, so an absent key is a switch that was
/// on: a panel loses its footer only if all three were turned off by hand.
final class OneSwitchAnswersForThreeTests: XCTestCase {

    func testAFreshInstallHasAFooter() {
        XCTAssertEqual(PanelFooterSetting.folded(stored: nil, settings: nil,
                                                 quit: nil, edit: nil), true)
    }

    func testTheOnlyWayToNoFooterIsAllThreeTurnedOff() {
        XCTAssertEqual(PanelFooterSetting.folded(stored: nil, settings: false,
                                                 quit: false, edit: false), false)
    }

    /// Any one of them left on is a footer, because it was one before.
    func testOneSurvivorKeepsTheFooter() {
        for kept in 0..<3 {
            let flags = (0..<3).map { $0 == kept }
            XCTAssertEqual(PanelFooterSetting.folded(stored: nil, settings: flags[0],
                                                     quit: flags[1], edit: flags[2]), true,
                           "the footer was drawn with only switch \(kept) on, and is not now")
        }
    }

    /// An absent old key is that switch's own default, which was on — so two
    /// switched off and one never touched is still a footer.
    func testAnAbsentOldKeyCountsAsOn() {
        XCTAssertEqual(PanelFooterSetting.folded(stored: nil, settings: false,
                                                 quit: false, edit: nil), true)
    }

    /// Once the new key is written it is the whole answer: somebody who hides
    /// the footer today must not have it folded back on by three keys that are
    /// about to be purged.
    func testTheNewKeyWinsOverAllThree() {
        XCTAssertEqual(PanelFooterSetting.folded(stored: false, settings: true,
                                                 quit: true, edit: true), false)
        XCTAssertEqual(PanelFooterSetting.folded(stored: true, settings: false,
                                                 quit: false, edit: false), true)
    }
}
