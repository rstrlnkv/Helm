import XCTest
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **At the smallest window the segment switcher becomes a pop-up, and Refresh
/// stays in the bar.**
///
/// The window's toolbar does not shrink an item that does not fit: photographed
/// 2026-09-17 at the smallest window, a 646 pt pane, the whole bar — switcher and
/// Refresh — went into the «»» overflow menu, in Russian and in Japanese and in
/// both header shapes. The page now decides the switcher's shape from the pane
/// width (`switcherIsSegmented`), calibrated on the same photographs: ru's
/// switcher fitted a 753 pt pane, and after the change so did ja's, the widest.
///
/// What the toolbar then draws is judged by photograph — a pane in a hosting
/// view has no window toolbar — and so is the pop-up's title, which is why it is
/// an `NSPopUpButton`: four SwiftUI menus drew no words there at all.
@MainActor
final class TheSwitcherGivesWayBeforeRefreshTests: XCTestCase {

    /// The smallest pane the settings window allows and the one the owner's
    /// window sat at when this was photographed.
    private let smallest: CGFloat = 646
    private let photographed: CGFloat = 753

    func testAtTheSmallestWindowTheSwitcherIsAPopUpInTheWidestLanguages() {
        for language in [AppLanguage.ru, .ja] {
            AppLanguage.only(language) {
                XCTAssertFalse(HomebrewSettingsPage.switcherIsSegmented(paneWidth: smallest), """
                    \(language.rawValue): the segmented switcher is kept in a \(smallest) pt pane, \
                    where the toolbar puts it and Refresh into its overflow menu
                    """)
            }
        }
    }

    func testWhereTheSwitcherWasSeenToFitItStaysSegmented() {
        for language in [AppLanguage.ru, .ja] {
            AppLanguage.only(language) {
                XCTAssertTrue(HomebrewSettingsPage.switcherIsSegmented(paneWidth: photographed), """
                    \(language.rawValue): a \(photographed) pt pane, where the segmented switcher was \
                    photographed fitting beside the header and Refresh, gets the pop-up instead
                    """)
            }
        }
    }

    func testAnUnmeasuredPaneDrawsTheSegmentedSwitcher() {
        XCTAssertTrue(HomebrewSettingsPage.switcherIsSegmented(paneWidth: nil),
                      "the first frame, before the pane is measured, flashes the pop-up")
    }
}
