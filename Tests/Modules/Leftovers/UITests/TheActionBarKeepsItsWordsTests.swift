import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// The bar under the list held three buttons and a caption in one `HStack`, and an
/// `HStack` does not wrap: at the narrowest pane the row overflowed and the
/// **destructive** button was what paid for it.
///
/// Measured at 606 pt, drawn against natural: de «Move to Trash» 167.0 → 127.0, fr
/// 164.5 → 128.5 (and «Clear selection» 144.5 → 121.0), es 161.0 → 127.5, ru 175.5
/// → 157.0. The German render read «In den Papierkorb…» and the Russian «Переместить
/// в Корзи…» — an ellipsis invented by truncation on the one page in this app that
/// had just spent a commit making an ellipsis mean *a question follows*.
///
/// The caption is a statement, not a control, so it moved to a full-width line of
/// its own above the buttons — the row `outcomeRow` already establishes for the same
/// reason. The buttons then need 438 pt of the 566 the pane leaves in the worst of
/// the eight.
@MainActor
final class TheActionBarKeepsItsWordsTests: XCTestCase {

    /// The narrowest pane the window allows: `contentMinSize` is 860 × 540 and the
    /// sidebar takes the rest (ARCHITECTURE.md § Settings window).
    private static let narrowest: CGFloat = 606

    private static func agent(_ name: String) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: 4_096)
    }

    /// The three words in the bar, in the order they are drawn. The English is the
    /// key, so this is also what the eight `.strings` files are read through.
    private func titles() -> [(String, Bool)] {
        [(LfStr.selectAll, false), (LfStr.deselectAll, false), (LfStr.removeSelected, true)]
    }

    /// The bar's own controls: the three at the bottom of the page.
    private func barControls(_ mount: MountedRender) -> [CGRect] {
        LeftoversPageRender.controls(in: mount).filter { $0.minY > 400 }
    }

    /// **The measurement this file exists for**, in every one of the eight.
    func testNoButtonInTheBarIsDrawnNarrowerThanItsOwnWords() async throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for language in AppLanguage.allCases {
            try await checkTheBarIsNotSqueezed(language, appearance: .aqua)
        }
    }

    /// And the same on the other screen, in the language that was worst — 40.0 pt
    /// out of the destructive button. **A control rather than a sweep**: a bordered
    /// control's metrics are its font's, and the eight readings above came back to
    /// the half-point identical in dark. Sixteen more page renders for a number
    /// that cannot move is thirty-five seconds of suite for nothing; a reading that
    /// *would* move if that ever stopped being true is what this is.
    func testTheDarkScreenMeasuresTheSame() async throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        try await checkTheBarIsNotSqueezed(.de, appearance: .darkAqua)
    }

    private func checkTheBarIsNotSqueezed(_ language: AppLanguage,
                                          appearance: NSAppearance.Name) async throws {
        AppLanguage.override = language
        let natural = titles().map {
            LeftoversPageRender.naturalWidth(of: $0.0, prominent: $0.1, appearance: appearance)
        }
        XCTAssertEqual(natural.filter { $0 > 0 }.count, 3,
                       "precondition: three buttons were measured on their own")

        let (mount, model) = await LeftoversPageRender.page(
            [Self.agent("com.vendor.gone")], language: language,
            width: Self.narrowest, appearance: appearance)
        defer { mount.drop() }
        // Something ticked: the bar is at its widest when it has a size to report,
        // which is the state the survey measured.
        model.tickAll()
        mount.settle(20)
        let drawn = barControls(mount)
        XCTAssertEqual(drawn.count, 3,
                       "precondition: \(language.rawValue) drew three controls in the bar, "
                       + "not \(drawn.count)")

        for (index, button) in drawn.enumerated() {
            XCTAssertGreaterThanOrEqual(button.width, natural[index], """
                \(language.rawValue), \(RenderedInk.label(of: appearance)): \
                «\(titles()[index].0)» is drawn \(button.width) pt wide where its own words \
                need \(natural[index]) — \(natural[index] - button.width) pt squeezed out of \
                it, and what a squeezed button loses is the end of the word. Measured at \
                40.0 pt on the destructive button in German.
                """)
        }
    }

    /// And nothing in the bar wraps: a caption that takes two lines pushes the
    /// buttons down, so the row sits at a different height in one language than in
    /// another. The German caption did exactly that at 606 pt.
    func testTheBarStandsAtTheSameHeightInEveryLanguage() async throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        var tops: [String: CGFloat] = [:]
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let (mount, model) = await LeftoversPageRender.page(
                [Self.agent("com.vendor.gone")], language: language,
                width: Self.narrowest, appearance: .aqua)
            defer { mount.drop() }
            model.tickAll()
            mount.settle(20)
            tops[language.rawValue] = barControls(mount).map(\.minY).min() ?? 0
        }

        let spread = (tops.values.max() ?? 0) - (tops.values.min() ?? 0)
        XCTAssertGreaterThan(tops.values.min() ?? 0, 0, "precondition: every language drew a bar")
        XCTAssertEqual(spread, 0, """
            the bar starts \(spread) pt lower in one language than in another: \
            \(tops.map { "\($0.key) \(Int($0.value))" }.sorted().joined(separator: ", ")). \
            Something in it is wrapping to a second line.
            """)
    }
}
