import XCTest
import SwiftUI
@testable import Module_Layout_UI
@testable import Module_Layout_Engine
import HelmUI
import HelmTestSupport

/// The hero's caption says three things on one line, and it has to stay one.
///
/// The estimate used to be a line of its own under the period buttons — always
/// drawn, at `.opacity(0)` half the time, purely so that pressing the metric
/// glyph could not move the form. The glyph is gone, so the reservation guarded
/// nothing, and the estimate moved up into the caption: «23 · слов исправлено ·
/// месяц · ≈ 48 с не ушло на перенабор».
///
/// **That is the whole risk, and it is a translation risk.** A caption of one
/// string is one height by construction — until one language's version of it
/// wraps, and then the hero is a line taller in that language only. Spanish is
/// 66 characters against Chinese's 28.
///
/// Parameterised by language rather than reading `AppLanguage.current`: this Mac
/// runs in Russian, so a bare assertion would exercise one of eight and pass
/// while German broke (CLAUDE.md § A test parameterized by an explicit
/// language).
@MainActor
final class LayoutHeroIsOneHeightTests: XCTestCase {

    /// The narrowest pane the settings window can give this hero: the window's
    /// own minimum is 860 pt, which leaves roughly 645 for the page. 600 is
    /// below anything reachable and is here as the translator's headroom — a
    /// caption that fits only at the exact production width has none.
    private let widths: [CGFloat] = [645, 600]

    private func caption(_ language: AppLanguage) -> String {
        LyStr.wordsIn(.month, count: 23, language: language)
            + " · ≈ " + HelmDuration.string(48, language: language)
            + " " + LyStr.notSpentTypingAgain(language: language)
    }

    private func height(_ text: String, width: CGFloat) -> CGFloat {
        let render = MountedRender(
            Text(text).font(HelmText.rowTitle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true),
            width: width, height: 200, appearance: .aqua)
        defer { render.drop() }
        render.settle(10)
        return render.fittingHeight
    }

    func testTheEstimateNeverAddsALineInAnyLanguage() {
        for language in AppLanguage.allCases {
            let counted = LyStr.wordsIn(.month, count: 23, language: language)
            for width in widths {
                XCTAssertEqual(height(caption(language), width: width),
                               height(counted, width: width), accuracy: 0.5,
                               "\(language.rawValue) at \(Int(width)) pt: the estimate wrapped the "
                               + "caption onto a second line, so the hero is taller in this "
                               + "language than in the others")
            }
        }
    }

    /// The test above compares two strings and would pass just as well if the
    /// estimate had quietly stopped being part of the caption — the two would
    /// then be the same string. This is the half that says it is there.
    func testTheEstimateIsActuallyInTheCaption() {
        for language in AppLanguage.allCases {
            let counted = LyStr.wordsIn(.month, count: 23, language: language)
            let full = caption(language)
            XCTAssertTrue(full.hasPrefix(counted),
                          "\(language.rawValue): the caption no longer opens with the count")
            XCTAssertGreaterThan(full.count, counted.count + 4,
                                 "\(language.rawValue): the caption carries no estimate")
            XCTAssertTrue(full.contains(LyStr.notSpentTypingAgain(language: language)),
                          "\(language.rawValue): the estimate lost the words that say what it is")
        }
    }
}
