import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Duplicates_UI

/// A group's header is a size, a reason and up to two buttons — and none of
/// the buttons was `fixedSize`, so on a narrow pane the *first* thing SwiftUI
/// compressed was «Restore the recommendation»: measured 15 pt short in French
/// at 540. The reason is the part with `lineLimit(1)`, so the reason is the
/// part that has to yield.
///
/// The arithmetic half proves the trade is affordable: both buttons whole,
/// the label whole, the reason free to truncate, inside the narrowest pane in
/// every language.
final class TheGroupHeaderKeepsItsButtonsTests: XCTestCase {

    private enum Key {
        static let restore = "Restore the recommendation"
        static let mark = "Mark the extra copies"
    }

    /// Mirrored from `DuplicatesView.header`: a default-spacing `HStack` (8 pt
    /// between four placed children) inside the inset list style's roughly
    /// 16 pt side insets, read off the audit's control map.
    private enum Chrome {
        static let total: CGFloat = 16 * 2 + 8 * 3
    }

    private func button(_ title: String) -> CGFloat {
        ControlMetrics.smallButton(title)
    }

    /// The size-and-count label at `HelmText.groupLabel` — system 11 semibold —
    /// with a figure a real library produces.
    private func sizeLabel(_ language: AppLanguage) -> CGFloat {
        let line = "\(HelmBytes.string(250_300_000, language: language.rawValue)) × 33"
        return ControlMetrics.label(line, font: .systemFont(ofSize: 11, weight: .semibold))
    }

    func testBothButtonsAndTheLabelFitTheNarrowestPane() {
        let narrowestPane: CGFloat = 540
        let (language, needs) = AppLanguage.allCases.map { language -> (AppLanguage, CGFloat) in
            (language, Chrome.total + sizeLabel(language)
                + button(L(Key.restore, language: language))
                + button(L(Key.mark, language: language)))
        }.max { $0.1 < $1.1 }!
        XCTAssertLessThan(needs, narrowestPane - 20, """
            With the reason given up entirely the header still needs \
            \(Int(needs)) pt in \(language.rawValue) against a \
            \(Int(narrowestPane)) pt pane, so pinning the buttons would clip \
            the label instead — the header needs a ladder, not a pin.
            """)
    }

    /// The shipped header pins both buttons, so the compressible child is the
    /// reason — which already truncates — and never a control's own words.
    func testTheShippedButtonsArePinned() throws {
        let page = try RepoSource.text(of: "Sources/Modules/Duplicates/UI/DuplicatesView.swift")
        let opens = try XCTUnwrap(page.range(of:
            "private func header(_ group: DuplicateGroup"))
        let closes = try XCTUnwrap(page.range(of: "\n    }",
                                              range: opens.upperBound..<page.endIndex))
        let header = String(page[opens.lowerBound..<closes.upperBound])
        for name in ["restoreRecommendation", "markGroupExtras"] {
            let call = try XCTUnwrap(header.range(of: "DupStr.\(name)"),
                                     "the header no longer draws \(name)")
            let after = String(header[call.upperBound...]).prefix(120)
            XCTAssertTrue(after.contains(".fixedSize()"), """
                The \(name) button is not pinned, so a narrow pane compresses \
                its words before the reason's — the defect the audit measured.
                """)
        }
    }

    /// The strings measured here are the ones the header draws.
    func testTheStringsMeasuredHereAreTheOnesTheHeaderDraws() {
        XCTAssertEqual(DupStr.restoreRecommendation,
                       L(Key.restore, language: AppLanguage.current))
        XCTAssertEqual(DupStr.markGroupExtras,
                       L(Key.mark, language: AppLanguage.current))
    }
}
