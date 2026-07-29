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

    func testTheFigureTokenIsMonospacedAtElevenPoint() {
        XCTAssertEqual(HelmText.figureFont, .system(size: 11, design: .monospaced))
    }

    /// The point of a token is that a caller cannot pick a different one and
    /// still look like it used the token — so it must not be equal to any of
    /// the four faces it replaces.
    func testTheFigureTokenIsNoneOfTheFacesItReplaces() {
        let replaced: [(String, Font)] = [
            ("SF Pro 10 tabular", .system(size: 10)),
            ("SF Mono 10", .system(size: 10, design: .monospaced)),
            ("caption", .caption),
            ("callout", .callout),
        ]
        for (name, font) in replaced {
            XCTAssertNotEqual(HelmText.figureFont, font, "figureFont collapsed onto \(name)")
        }
    }
}
