import XCTest
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Where the switcher does not fit, it becomes a pop-up, and Refresh stays in
/// the bar.**
///
/// The window's toolbar does not shrink an item that does not fit: photographed
/// 2026-09-17 at the smallest window, a 646 pt pane, the whole bar — switcher and
/// Refresh — went into the «»» overflow menu, in Russian and in Japanese and in
/// both header shapes. The page decides from the pane width and the chosen
/// `ToolbarSwitcherStyle` (`switcherFits`), with a reserve calibrated on those
/// photographs: ru's 488 pt system control fitted a 753 pt pane.
///
/// What the toolbar then draws is judged by photograph — a pane in a hosting
/// view has no window toolbar — and so is the pop-up's title.
@MainActor
final class TheSwitcherGivesWayBeforeRefreshTests: XCTestCase {

    private let smallest: CGFloat = 646
    private let photographed: CGFloat = 753

    /// Glyphs are the narrowest style and do not grow with the language, so
    /// they are the one that must keep the switcher at the smallest window.
    func testGlyphsFitTheSmallestWindowInTheWidestLanguages() {
        for language in [AppLanguage.ru, .ja] {
            AppLanguage.only(language) {
                XCTAssertTrue(HomebrewSettingsPage.switcherFits(paneWidth: smallest, style: .icons), """
                    \(language.rawValue): the glyph switcher is replaced by the pop-up in a \
                    \(smallest) pt pane, where it is narrower than anything else in the bar
                    """)
            }
        }
    }

    /// A glyph beside every word is the widest style: at the smallest window it
    /// gives way, or the toolbar takes Refresh with it.
    func testGlyphsAndWordsGiveWayAtTheSmallestWindow() {
        for language in [AppLanguage.ru, .ja] {
            AppLanguage.only(language) {
                XCTAssertFalse(HomebrewSettingsPage.switcherFits(paneWidth: smallest, style: .iconsAndText), """
                    \(language.rawValue): glyphs and words are kept in a \(smallest) pt pane, where \
                    the toolbar puts the switcher and Refresh into its overflow menu
                    """)
            }
        }
    }

    func testEveryStyleFitsWhereTheWiderSystemControlWasSeenToFit() {
        for language in [AppLanguage.ru, .ja] {
            AppLanguage.only(language) {
                for style in ToolbarSwitcherStyle.allCases {
                    XCTAssertTrue(HomebrewSettingsPage.switcherFits(paneWidth: photographed, style: style), """
                        \(language.rawValue): \(style) gets the pop-up in a \(photographed) pt pane, \
                        where the wider system control was photographed fitting
                        """)
                }
            }
        }
    }

    func testAnUnmeasuredPaneDrawsTheSwitcher() {
        for style in ToolbarSwitcherStyle.allCases {
            XCTAssertTrue(HomebrewSettingsPage.switcherFits(paneWidth: nil, style: style),
                          "\(style): the first frame, before the pane is measured, flashes the pop-up")
        }
    }
}
