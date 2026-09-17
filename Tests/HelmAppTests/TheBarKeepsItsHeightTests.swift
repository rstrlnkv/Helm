import HelmTestSupport
import XCTest

/// **The settings window's toolbar never changes its own display mode.**
///
/// A right-click on a toolbar raises AppKit's «Icon and Text / Icon Only» menu,
/// and choosing from it lays every item out with a label under it: photographed
/// 2026-09-17, the 52 pt bar became 68, and the labels themselves never
/// appeared, because every item in this bar is a custom view. Turning the
/// customization off is also what leaves the right-click to the switcher's own
/// menu.
///
/// Read off the construction: the toolbar is made by SwiftUI's bridge when a
/// page publishes items, so there is none to ask in a test process.
final class TheBarKeepsItsHeightTests: XCTestCase {

    func testTheWindowRefusesDisplayModeCustomization() throws {
        let code = SwiftSource.code(try RepoSource.text(of: "Sources/HelmApp/SettingsWindow.swift"))
        XCTAssertTrue(code.contains("toolbar.allowsDisplayModeCustomization = false"), """
            the settings window lets macOS change the toolbar's display mode, which grows the bar \
            and draws labels no custom item has
            """)
        XCTAssertTrue(code.contains("toolbar.displayMode = .iconOnly"),
                      "the bar is left on whatever display mode was stored for it")
    }
}
