import AppKit
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Launchpad_UI

/// The removal card's two buttons, as the card draws them under `helmRoot()`: in no language are they wider than `LaunchpadMetrics.removalRoom`, and the pair
/// that is too wide side by side (German and Russian "Quit and Move to Trash") stands one above the other instead of running out of the card.
@MainActor final class TheRemovalButtonsFitTheCardInEveryLanguageTests: XCTestCase {
    private func row(_ confirm: String) -> CGSize {
        NSHostingView(rootView: LaunchpadRemovalButtons(confirm: confirm).frame(width: LaunchpadMetrics.removalRoom).helmRoot()).fittingSize
    }

    private func alone(_ title: String) -> CGSize { NSHostingView(rootView: Button(title) {}.helmRoot()).fittingSize }

    func testNoLanguageRunsTheButtonsOutOfTheCard() {
        var stacked = 0
        AppLanguage.each { language in
            for confirm in [LpStr.quitAndMoveToTrash, HelmWord.moveToTrash] {
                XCTAssertGreaterThan(alone(confirm).width, 30, "\(language): measured")
                XCTAssertLessThanOrEqual(alone(confirm).width, LaunchpadMetrics.removalRoom, "\(language): \(confirm) alone is wider than the card")
                if row(confirm).height > alone(confirm).height * 1.5 { stacked += 1 }
            }
        }
        // The control: the row does stack somewhere, or this proved nothing about the fix.
        XCTAssertGreaterThan(stacked, 0, "some language is too wide for one row")
    }
}
