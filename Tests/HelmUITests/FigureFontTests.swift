import XCTest
import SwiftUI
@testable import HelmUI

/// A byte size is a figure, and figures are set in one face.
///
/// They were set in four across adjacent lists — SF Mono 11, SF Pro 10 tabular,
/// `.caption` and `.callout` — which is invisible on any one screen and obvious
/// the moment two of them sit in the same window. Measured: "1,24 ГБ" at SF Mono
/// 11 pt renders 27% wider than the same string at SF Pro 10 pt with tabular
/// figures, so the columns of two lists in the same sidebar could not line up
/// even in principle.
final class FigureFontTests: XCTestCase {

    /// **SF Pro with tabular figures, and not a bare `.subheadline`.**
    ///
    /// The face moved off SF Mono on 2026-08-20 — a byte size in a settings row
    /// is not code, and macOS sets one in the interface face — but the property
    /// that was actually wanted is that the digits do not jump as they change.
    /// That is `monospacedDigit()`, and it is carried **on the token**, because
    /// seven call sites spell `.font(HelmText.figureFont)` without reaching for
    /// `helmFigure()` and would silently lose it.
    func testTheFigureTokenIsTabularAndNotJustTheDetailStyle() {
        XCTAssertEqual(HelmText.figureFont, Font.subheadline.monospacedDigit())
        XCTAssertNotEqual(HelmText.figureFont, .subheadline, """
            the figure token is the plain detail style, so its digits shift as they change — \
            which is the one thing a column of figures exists not to do
            """)
    }

    /// The headline figure carries it too, and there it was never on the
    /// modifier: `helmMetricFigure()` caps the line and lets it shrink and asks
    /// for no tabular digits at all. That cost nothing while the face was SF
    /// Mono and would have cost a counting figure the moment it stopped being.
    func testTheMetricTokenIsTabularToo() {
        XCTAssertEqual(HelmText.metricFont,
                       Font.system(size: 16, weight: .medium).monospacedDigit())
        XCTAssertNotEqual(HelmText.metricFont, .system(size: 16, weight: .medium))
    }

    /// The point of a token is that a caller cannot pick a different one and
    /// still look like it used the token — so it must not be equal to any of
    /// the four faces it replaces.
    func testTheFigureTokenIsNoneOfTheFacesItReplaces() {
        let replaced: [(String, Font)] = [
            ("SF Pro 10 tabular", .system(size: 10)),
            ("SF Mono 10", .system(size: 10, design: .monospaced)),
            ("SF Mono 11", .system(size: 11, design: .monospaced)),
            ("caption", .caption),
            ("callout", .callout),
        ]
        for (name, font) in replaced {
            XCTAssertNotEqual(HelmText.figureFont, font, "figureFont collapsed onto \(name)")
        }
    }
}
