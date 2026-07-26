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
            let badge = BadgeImage.make(label: "JP", flag: nil, region: "JP",
                                        style: .flagDrawn, points: points)
            XCTAssertEqual(badge.size.width, points, accuracy: 0.01)
            XCTAssertEqual(badge.size.height, points, accuracy: 0.01)
        }
    }

    /// A layout with no artwork falls back to letters in a frame, not to a
    /// blank space where an indicator should be.
    func testALayoutWithNoArtworkFallsBackToLetters() {
        let badge = BadgeImage.make(label: "DV", flag: nil, region: nil,
                                    style: .flagDrawn, points: 15)
        XCTAssertGreaterThan(badge.size.width, 0)
        XCTAssertGreaterThan(badge.size.height, 0)
        // Letters are wider than they are tall in this frame; a flag is square.
        XCTAssertNotEqual(badge.size.width, badge.size.height)
    }

    func testTheBadgeHasPixelsInIt() throws {
        let badge = BadgeImage.make(label: "RU", flag: nil, region: "RU",
                                    style: .flagDrawn, points: 18)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = badge.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        badge.draw(in: NSRect(origin: .zero, size: badge.size))
        NSGraphicsContext.restoreGraphicsState()
        // The centre of the Russian flag is blue, and opaque.
        let centre = try XCTUnwrap(rep.colorAt(x: 18, y: 18)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(centre.alphaComponent, 1, accuracy: 0.05)
        XCTAssertGreaterThan(centre.blueComponent, centre.redComponent)
    }
}
