import XCTest
import AppKit
import SwiftUI
import HelmTestSupport
@testable import HelmUI

/// A colour the person chose themselves has to survive the round trip to the
/// plist and back, and it has to be told apart from the eight that have names.
///
/// The palette is names — `"orange"` — and everything that draws the menu-bar
/// icon takes one optional token and always has. A free choice cannot be a
/// name, so it is the value, and both live in one string. `#` is what separates
/// them: no palette case begins with one, so no hand edit can produce a string
/// that is ambiguous.
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
    /// `NSColorPanel` hands back whatever space the person picked in, and this
    /// Mac's panel opens in Display P3. Three bytes of P3 stored and read back
    /// as sRGB is a visibly different colour on the next launch — saturated
    /// green moves by a fifth of the channel.
    ///
    /// Written first against `deviceRGB` and that was a check that could not
    /// fail: deviceRGB is close enough to sRGB that the difference hid under
    /// the tolerance, and removing the conversion broke nothing.
    func testAColourFromAnotherSpaceIsStoredAsSRGB() throws {
        // Inside both gamuts, and measured: this one moves 0.32 in total
        // between P3 and sRGB. A *primary* does not — P3 green clamps at the
        // edge of sRGB and comes back with the same numbers, so the first
        // version of this test compared a colour with itself and its own
        // control said so.
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

    /// And the menu-bar renderer draws it, rather than falling back to white —
    /// which is what every unknown token did before there was such a thing as a
    /// known one that is not a name.
    func testTheMenuBarIconDrawsACustomTint() throws {
        let drawn = try XCTUnwrap(MenuBarIcon.nsColor(forTintToken: "#3399E6")
            .usingColorSpace(.sRGB))
        XCTAssertEqual(Double(drawn.redComponent), 0.2, accuracy: 0.01)
        XCTAssertEqual(Double(drawn.greenComponent), 0.6, accuracy: 0.01)
        XCTAssertEqual(Double(drawn.blueComponent), 0.9, accuracy: 0.01)
    }

    /// The control: an unknown token is still white, so the test above is about
    /// the custom colour rather than about the fallback having changed.
    func testAnUnknownTokenIsStillWhite() throws {
        let drawn = try XCTUnwrap(MenuBarIcon.nsColor(forTintToken: "chartreuse")
            .usingColorSpace(.sRGB))
        XCTAssertEqual(Double(drawn.redComponent), 1, accuracy: 0.01)
    }

    /// The retired names still resolve. They are somebody's stored setting on a
    /// Mac that has already run Helm, and a case that stops existing reads back
    /// as white with no explanation.
    func testTheRetiredNamesStillResolve() {
        for name in ["mint", "cyan", "pink"] {
            let palette = PaletteColor(rawValue: name)
            XCTAssertNotNil(palette, "\(name) was removed rather than retired")
            XCTAssertFalse(PaletteColor.offered.contains { $0.rawValue == name },
                           "\(name) is still offered, so it was not retired at all")
        }
    }

    /// And the eight that are offered are Calendar's, in Calendar's order.
    func testTheMenuOffersCalendarsEight() {
        XCTAssertEqual(PaletteColor.offered.map(\.rawValue),
                       ["white", "red", "orange", "yellow", "green", "blue", "purple", "brown"])
    }

    /// **«Other…» opens the system panel, not a popover with a well in it.**
    ///
    /// A SwiftUI `ColorPicker` *is* a colour well — a button whose whole job is
    /// to open `NSColorPanel` — so presenting one inside a popover put a second
    /// click and a floating swatch between the menu item and the thing it
    /// names. Reported as «remove this popup».
    ///
    /// A source check: the panel is AppKit's own window and a test cannot open
    /// it without taking over the machine.
    func testTheMenuOpensTheSystemPanelDirectly() throws {
        let url = RepoSource.root
            .appendingPathComponent("Sources/HelmUI/DesignSystem/PaletteSwatches.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertGreaterThan(source.count, 500, "the file was not read at all")
        XCTAssertTrue(source.contains("NSColorPanel.shared"),
                      "«Other…» does not reach the system panel")
        XCTAssertFalse(source.contains("ColorPicker("),
                       "a colour well is being presented instead of the panel, which is the "
                       + "extra click this replaced")
        XCTAssertFalse(source.contains(".popover("),
                       "the popover is back")
    }

    /// And the panel's target is held. `NSColorPanel` keeps it **weakly**, so a
    /// bridge created inside the action that opens the panel is gone before the
    /// first colour comes back — which reads as a panel that does nothing.
    func testTheColourPanelsTargetIsRetained() throws {
        let url = RepoSource.root
            .appendingPathComponent("Sources/HelmUI/DesignSystem/PaletteSwatches.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("@State private var bridge = ColorPanelBridge()"),
                      "the target is not held by the view, so it is deallocated before the "
                      + "panel can call it")
    }
}
