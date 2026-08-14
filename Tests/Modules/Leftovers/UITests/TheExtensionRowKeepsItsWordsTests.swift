import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **«Manage…» described nothing Helm does.** The button calls
/// `PermissionCheck.openExtensionSettings()`, and the Uninstaller's own button
/// drives the identical call under the name of the act — two labels for one
/// thing, and the vaguer of the two was on this page. Naming the act costs
/// width, in every language and most in the two that were already longest, so
/// the row is measured rather than assumed.
///
/// The bar below the list paid this bill once already
/// (`TheActionBarKeepsItsWordsTests`) and what it lost was the end of a word on
/// the destructive button. This row is the other shape: one button after a
/// `Spacer()`, on a row whose detail line is nil.
@MainActor
final class TheExtensionRowKeepsItsWordsTests: XCTestCase {

    /// The narrowest pane the window allows — `contentMinSize` is 860 × 540 and
    /// the sidebar takes the rest (ARCHITECTURE.md § Settings window).
    private static let narrowest: CGFloat = 606

    /// An extension whose host app is gone: the one row that draws this button,
    /// and `LeftoverActions.available` gives it `[.systemSettings]` and nothing
    /// else, so the button is the only control on it.
    private static func extensionItem() -> StaleItem {
        StaleItem(path: "com.vendor.app.networkExtension",
                  identifier: "com.vendor.app.networkExtension",
                  kind: .systemExtension, sizeBytes: 0)
    }

    /// The row's own control: the only one drawn above the foot of the page.
    private func rowControls(_ mount: MountedRender) -> [CGRect] {
        LeftoversPageRender.controls(in: mount).filter { $0.minY > 100 && $0.minY < 400 }
    }

    func testTheRowsButtonIsNeverDrawnNarrowerThanItsOwnWords() async throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for language in AppLanguage.allCases {
            try await checkTheRowIsNotSqueezed(language, appearance: .aqua)
        }
    }

    /// And on the other screen, in the language the label grew most in. A
    /// bordered control's metrics are its font's, so this is a reading that would
    /// move if that ever stopped being true rather than sixteen more page renders
    /// for a number that cannot — the argument `TheActionBarKeepsItsWordsTests`
    /// records for its own dark pass.
    func testTheDarkScreenMeasuresTheSame() async throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        try await checkTheRowIsNotSqueezed(.ru, appearance: .darkAqua)
        try await checkTheRowIsNotSqueezed(.de, appearance: .darkAqua)
    }

    private func checkTheRowIsNotSqueezed(_ language: AppLanguage,
                                          appearance: NSAppearance.Name) async throws {
        AppLanguage.override = language
        // `.small`, which is what the row gives it: measured against a regular
        // control every one of the eight reads as squeezed by the same ~19 pt,
        // which is the baseline being wrong rather than the button.
        let natural = LeftoversPageRender.naturalWidth(of: LfStr.openExtensions,
                                                       prominent: false, appearance: appearance,
                                                       controlSize: .small)
        XCTAssertGreaterThan(natural, 0, "precondition: the button was measured on its own")

        let (mount, _) = await LeftoversPageRender.page(
            [Self.extensionItem()], language: language,
            width: Self.narrowest, appearance: appearance)
        defer { mount.drop() }
        mount.settle(20)

        let drawn = rowControls(mount)
        XCTAssertEqual(drawn.count, 1, """
            \(language.rawValue): the extension row drew \(drawn.count) controls where it draws \
            one — the measurement below is about whichever of them came first.
            """)
        let button = try XCTUnwrap(drawn.first)
        XCTAssertGreaterThanOrEqual(button.width, natural, """
            \(language.rawValue), \(RenderedInk.label(of: appearance)): «\(LfStr.openExtensions)» \
            is drawn \(button.width) pt wide where its own words need \(natural) — \
            \(natural - button.width) pt squeezed out of it, and what a squeezed button loses is \
            the end of the word.
            """)
        XCTAssertLessThanOrEqual(button.maxX, Self.narrowest, """
            \(language.rawValue): the button reaches \(button.maxX) pt on a \(Self.narrowest) pt \
            pane — it is off the edge of the page rather than truncated on it.
            """)
    }
}
