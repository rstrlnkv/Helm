import XCTest
import AppKit
import SwiftUI
import HelmTestSupport
@testable import HelmUI

/// The colour picker's menu has to *show* the ten colours.
///
/// It arrived as ten words. A `Picker` with the menu style is drawn by AppKit
/// as an `NSMenu`, and an `NSMenuItem` takes an image — the tint SwiftUI is
/// asked to apply to an SF Symbol inside one is dropped on the way, so
/// `Image(systemName: "circle.fill").foregroundStyle(palette.color)` is a grey
/// dot at best and nothing at worst. The swatch is drawn here and handed over
/// already coloured.
///
/// Checked on the pixels, because that is the only part of this that can be
/// wrong: the menu itself is AppKit's and cannot be photographed from a test.
@MainActor
final class TheColourMenuShowsColoursTests: XCTestCase {

    private func centre(of image: NSImage) throws -> NSColor {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: image.tiffRepresentation ?? Data()))
        let point = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2))
        return try XCTUnwrap(point.usingColorSpace(.sRGB))
    }

    /// Every swatch that is a colour is drawn as one — not as grey.
    ///
    /// **Not compared against `NSColor(palette.color)` component by
    /// component**, and that was tried: the image's own representation is in a
    /// different colour space, so a round trip through `usingColorSpace(.sRGB)`
    /// moves every channel by two to nine hundredths. Chasing that number would
    /// be pinning the conversion, not the drawing. What the failure actually
    /// looked like is grey — a symbol whose tint the menu dropped — and grey is
    /// a channel spread of nothing.
    func testEverySwatchIsDrawnAsAColourAndNotAsGrey() throws {
        for palette in PaletteColor.allCases where palette != .white {
            let c = try centre(of: palette.swatchImage)
            let spread = max(c.redComponent, c.greenComponent, c.blueComponent)
                - min(c.redComponent, c.greenComponent, c.blueComponent)
            XCTAssertGreaterThan(spread, 0.1,
                                 "\(palette.rawValue) is drawn grey — the menu dropped the "
                                 + "tint, which is what an SF Symbol does here")
        }
    }

    /// …and no two of them are the same, which is the whole reason a person
    /// looks at this menu rather than reading it.
    func testTheTenAreTenDifferentColours() throws {
        var seen: [String] = []
        for palette in PaletteColor.allCases {
            let c = try centre(of: palette.swatchImage)
            seen.append(String(format: "%.2f-%.2f-%.2f",
                               c.redComponent, c.greenComponent, c.blueComponent))
        }
        XCTAssertEqual(Set(seen).count, PaletteColor.allCases.count,
                       "two swatches are drawn the same colour: \(seen)")
    }

    /// The image must not be a template: a template is recoloured by whatever
    /// menu draws it, which is exactly the failure this replaced.
    func testTheSwatchIsNotATemplate() {
        for palette in PaletteColor.allCases {
            XCTAssertFalse(palette.swatchImage.isTemplate,
                           "\(palette.rawValue) would be recoloured by the menu")
        }
    }

    /// **And the picker uses it.** The three checks above are about the image;
    /// putting the tinted symbol back into the menu passes all of them, because
    /// nothing there reads what the control is built from. Found by mutation,
    /// which is the only way a hole of this shape is found.
    ///
    /// A source check, because there is nothing to assert against at runtime:
    /// the menu is AppKit's and a test cannot photograph it.
    func testThePickerDrawsTheImageRatherThanATintedSymbol() throws {
        let url = RepoSource.root
            .appendingPathComponent("Sources/HelmUI/DesignSystem/PaletteSwatches.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertGreaterThan(source.count, 500, "the file was not read at all")
        XCTAssertTrue(source.contains("Image(nsImage: palette.swatchImage)"),
                      "the menu items are not built from the drawn swatch")
        XCTAssertFalse(source.contains("Image(systemName: \"circle.fill\")"),
                       "a tinted SF Symbol is back in the menu, where AppKit drops the tint "
                       + "and the ten colours arrive as ten words")
    }
}
