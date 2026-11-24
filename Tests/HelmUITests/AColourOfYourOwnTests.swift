import XCTest
import AppKit
import SwiftUI
import HelmTestSupport
@testable import HelmUI

/// A colour the person chose themselves has to survive the round trip to the
/// plist and back, and it has to be told apart from the eight that have names.
///
/// A free choice cannot be a name, so it is stored as the value, `#` first: no
/// palette case begins with one, so no hand edit can produce an ambiguous string.
final class AColourOfYourOwnTests: XCTestCase {

    func testAColourSurvivesTheRoundTrip() throws {
        let chosen = Color(nsColor: NSColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        let token = PaletteTint.token(for: chosen)
        XCTAssertEqual(token, "#3399E6")
        let back = try XCTUnwrap(PaletteTint.custom(token)?.usingColorSpace(.sRGB))
        XCTAssertEqual(Double(back.redComponent), 0.2, accuracy: 0.004)
        XCTAssertEqual(Double(back.greenComponent), 0.6, accuracy: 0.004)
        XCTAssertEqual(Double(back.blueComponent), 0.9, accuracy: 0.004)
    }

    /// **The conversion happens on the way in.**
    ///
    /// `NSColorPanel` hands back whatever space the person picked in, often
    /// Display P3, and P3 bytes read back as sRGB are a visibly different colour
    /// on the next launch. Checked against sRGB, not `deviceRGB`, which is close
    /// enough to hide the difference under the tolerance.
    func testAColourFromAnotherSpaceIsStoredAsSRGB() throws {
        // Inside both gamuts, and moved by the conversion. A primary is not:
        // P3 green clamps at the edge of sRGB and comes back unchanged.
        let p3 = NSColor(displayP3Red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
        let token = PaletteTint.token(for: Color(nsColor: p3))
        let back = try XCTUnwrap(PaletteTint.custom(token)?.usingColorSpace(.sRGB))
        let wanted = try XCTUnwrap(p3.usingColorSpace(.sRGB))
        XCTAssertEqual(Double(back.redComponent), Double(wanted.redComponent), accuracy: 0.01)
        XCTAssertEqual(Double(back.greenComponent), Double(wanted.greenComponent), accuracy: 0.01)
        XCTAssertEqual(Double(back.blueComponent), Double(wanted.blueComponent), accuracy: 0.01)
        // The control: the two spaces really do disagree about this colour, or
        // the three assertions above are comparing a colour with itself.
        XCTAssertGreaterThan(abs(Double(wanted.blueComponent) - 0.2), 0.03,
                             "this colour is the same in both spaces, so the test measures "
                             + "nothing")
    }

    /// A palette name is not a custom colour, and neither is junk.
    func testOnlyAHashIsACustomColour() {
        for token in ["orange", "white", "", "#12345", "#GGGGGG", "3399E6", "#3399E67"] {
            XCTAssertNil(PaletteTint.custom(token), "\(token) was read as a colour")
        }
    }

    /// The retired names still resolve: they are somebody's stored setting.
    func testTheRetiredNamesStillResolve() {
        for name in ["mint", "cyan", "pink"] {
            let palette = PaletteColor(rawValue: name)
            XCTAssertNotNil(palette, "\(name) was removed rather than retired")
            XCTAssertFalse(PaletteColor.offered.contains { $0.rawValue == name },
                           "\(name) is still offered, so it was not retired at all")
        }
    }
}
