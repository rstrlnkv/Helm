import AppKit
import XCTest
import Module_Layout_Engine
@testable import Module_Layout_UI

/// The flags are files now, not code, and the failure mode moved with them:
/// a missing file is a layout that silently shows letters, and nothing in the
/// compiler notices. These read the bundle.
final class FlagAssetTests: XCTestCase {

    /// Every region the layout table can produce must have artwork. This is
    /// the test that fails when a file is added to the table and not to the
    /// folder, or renamed to lower case on a case-insensitive checkout.
    func testEveryRegionTheLayoutTableNamesHasArtwork() {
        let named = ["RU", "DE", "NL", "UA", "PL", "AT", "HU", "EE", "LT", "BG",
                     "AM", "IR", "ES", "LV", "TH", "FR", "IT", "BE", "IE", "RO",
                     "CA", "MX", "PT", "IL", "BY", "SK", "SI", "RS", "HR", "SE",
                     "DK", "FI", "NO", "IS", "CH", "GE", "JP", "KZ", "MK", "CZ",
                     "US", "GR", "TW", "GB", "AU", "TR", "KR", "BR", "CN", "VN"]
        for region in named {
            XCTAssertNotNil(FlagAsset.image(region: region), "no artwork for \(region)")
        }
        XCTAssertEqual(FlagAsset.regions.count, named.count)
    }

    func testTheRegionListMatchesTheFilesOnDisk() {
        // Read from the bundle rather than declared in code, so the list
        // cannot drift from what actually ships.
        XCTAssertFalse(FlagAsset.regions.isEmpty, "the Flags resource did not ship")
        for region in FlagAsset.regions {
            XCTAssertNotNil(FlagAsset.image(region: region), region)
        }
    }

    func testAnUnknownRegionHasNoArtworkRatherThanAWrongOne() {
        XCTAssertNil(FlagAsset.image(region: nil))
        XCTAssertNil(FlagAsset.image(region: "ZZ"))
        XCTAssertNil(FlagAsset.image(region: ""))
    }

    func testRegionLookupIsCaseInsensitive() {
        XCTAssertNotNil(FlagAsset.image(region: "ru"))
        XCTAssertNotNil(FlagAsset.image(region: "Ru"))
    }

    /// The same NSImage instance comes back: the menu bar redraws on every
    /// layout switch and every theme change, and decoding a PNG each time is
    /// work nobody asked for.
    func testArtworkIsCached() {
        let first = FlagAsset.image(region: "JP")
        let second = FlagAsset.image(region: "JP")
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
    }

    // MARK: - The badge built from it

    /// `NSStatusItem` scales whatever image it is handed, so the badge must
    /// carry the size that was asked for — a 128 pt picture in a 15 pt slot is
    /// not the same picture.
    func testTheBadgeIsTheSizeItWasAskedFor() {
        for points in [CGFloat(9), 11, 13, 15, 18] {
            let badge = BadgeImage.make(label: "JP", region: "JP",
                                        style: .flagDrawn, points: points)
            XCTAssertEqual(badge.size.height, points, accuracy: 0.01)
            // 4:3, the ratio the source set is drawn in — scaling a flag to
            // some other ratio is redrawing it.
            XCTAssertEqual(badge.size.width, (points * 4 / 3).rounded(), accuracy: 0.01)
        }
    }

    /// A layout with no artwork falls back to letters in a frame, not to a
    /// blank space where an indicator should be.
    func testALayoutWithNoArtworkFallsBackToLetters() {
        let badge = BadgeImage.make(label: "DV", region: nil,
                                    style: .flagDrawn, points: 15)
        XCTAssertGreaterThan(badge.size.width, 0)
        XCTAssertGreaterThan(badge.size.height, 0)
        XCTAssertNotEqual(badge.size.width, badge.size.height)
    }

    /// China's stars are a `<defs>` path referenced with `<use xlink:href>`,
    /// which `NSImage`'s SVG support does not resolve — it drew a plain red
    /// rectangle and reported success. The shipped PNGs are rendered through
    /// WebKit for that reason; this is the test that notices if that ever
    /// silently regresses.
    func testChinaHasItsStars() throws {
        let art = try XCTUnwrap(FlagAsset.image(region: "CN"))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(art.tiffRepresentation)))
        var yellow = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if c.redComponent > 0.8, c.greenComponent > 0.7, c.blueComponent < 0.4 { yellow += 1 }
            }
        }
        XCTAssertGreaterThan(yellow, 20, "the stars did not render — a flat red flag")
    }

    func testTheBadgeHasPixelsInIt() throws {
        let badge = BadgeImage.make(label: "RU", region: "RU",
                                    style: .flagDrawn, points: 18)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 36,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = badge.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        badge.draw(in: NSRect(origin: .zero, size: badge.size))
        NSGraphicsContext.restoreGraphicsState()
        // The centre of the Russian flag is blue, and opaque.
        let centre = try XCTUnwrap(rep.colorAt(x: 24, y: 18)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(centre.alphaComponent, 1, accuracy: 0.05)
        XCTAssertGreaterThan(centre.blueComponent, centre.redComponent)
    }
}
