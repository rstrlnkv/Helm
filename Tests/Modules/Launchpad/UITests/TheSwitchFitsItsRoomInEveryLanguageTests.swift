import AppKit
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Launchpad_UI

/// The window's switch ("Apps", "Categories", the kit's tabs as the window draws them: text only) is no wider than
/// `LaunchpadMetrics.switchRoom` less the 20 pt gap that keeps it from the search field, in any of the eight languages.
@MainActor final class TheSwitchFitsItsRoomInEveryLanguageTests: XCTestCase {
    func testTheStripAndItsGapFitTheRoomInEveryLanguage() {
        AppLanguage.each { language in
            let tabs = [HelmToolbarTab(id: "apps", title: HelmWord.apps, symbol: "square.grid.2x2"),
                        HelmToolbarTab(id: "categories", title: LpStr.categories, symbol: "rectangle.3.group")]
            let strip = HelmHeaderTabs(tabs: tabs, selection: .constant("apps"), enabled: true)
            let width = NSHostingView(rootView: strip).fittingSize.width
            XCTAssertGreaterThan(width, 60, "\(language): the strip was measured")
            XCTAssertLessThanOrEqual(width + 20, LaunchpadMetrics.switchRoom, "\(language): the strip is \(width) pt")
        }
    }
}
