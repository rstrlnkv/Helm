import XCTest
import AppKit
@testable import HelmApp
@testable import HelmUI
import HelmTestSupport

/// The shipped arrangement fits under the settings window's own height in
/// every language, not only the one this Mac runs in.
///
/// `SidebarComposerHeightTests` checks the shipped arrangement against a
/// literal, in whichever language the process happens to be in. The chrome
/// half of the sum is the measured height of a translated note, so a language
/// whose note wraps one line more is a sheet that scrolls — or, with the cap
/// read from `SettingsWindow.defaultSize`, a cap that is wrong for it alone.
/// This reads the cap from the window rather than a literal, so a window height
/// put back below the shipped arrangement goes red here too.
@MainActor
final class TheShippedComposerFitsTheWindowInEveryLanguageTests: XCTestCase {

    func testTheShippedArrangementFitsUnderTheWindowInEveryLanguage() {
        let shipped = SidebarLayout.seeded(from: SidebarLayoutStore.registry())
        let list = SidebarComposerList.estimatedHeight(of: shipped, editing: true)
        XCTAssertGreaterThan(list, 0, "the shipped arrangement estimated nothing")
        var seen = 0
        AppLanguage.each { language in
            seen += 1
            let chrome = SidebarComposerSheet.chromeHeight
            XCTAssertGreaterThan(chrome, 129, "\(language): the note measured nothing")
            XCTAssertLessThanOrEqual(list + chrome, SettingsWindow.defaultSize.height,
                "\(language): the shipped composer wants \(list + chrome) pt, "
                + "the window gives \(SettingsWindow.defaultSize.height)")
        }
        XCTAssertEqual(seen, AppLanguage.allCases.count)
    }
}
