import AppKit
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Launchpad_UI

/// The edit mode's "Done" button, as the window draws it (a plain button under `helmRoot()`), with the 20 pt gap that keeps it from the search field, is no wider than
/// `LaunchpadMetrics.doneRoom` in any of the eight languages.
@MainActor final class TheDoneButtonFitsItsRoomInEveryLanguageTests: XCTestCase {
    func testTheButtonAndItsGapFitTheRoomInEveryLanguage() {
        AppLanguage.each { language in
            let width = NSHostingView(rootView: Button(HelmWord.done) {}.helmRoot()).fittingSize.width
            XCTAssertGreaterThan(width, 30, "\(language): the button was measured")
            XCTAssertLessThanOrEqual(width + 20, LaunchpadMetrics.doneRoom, "\(language): the button is \(width) pt")
        }
    }
}
