import AppKit
import XCTest
import Module_Layout_Engine
@testable import Module_Layout_UI

/// The flags shipped with three rendering faults that no test could see, so
/// these read the pixels back.
///
/// The faults were: bands whose edges fell mid-pixel, which produced a blended
/// row that was also partly transparent — the menu bar showed through the
/// middle of the flag; and an outline given in points, which is two physical
/// pixels on a Retina screen and ate a third of Russia's white band at the
/// smallest size. Both are invisible in a screenshot at 1× and obvious in the
/// numbers.
final class BadgeImageTests: XCTestCase {

    /// Renders at a fixed scale and reads the raw pixels, in device pixels.
    private func pixels(_ art: FlagArt, points: CGFloat, scale: CGFloat = 2)
    -> (rep: NSBitmapImageRep, width: Int, height: Int) {
        let image = BadgeImage.drawn(art, points: points, scale: scale)
        let width = Int((image.size.width * scale).rounded())
        let height = Int((image.size.height * scale).rounded())
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return (rep, width, height)
    }

    /// The middle column, top to bottom — where a horizontal band boundary
    /// shows itself.
    private func column(_ art: FlagArt, points: CGFloat) -> [NSColor] {
        let (rep, width, height) = pixels(art, points: points)
        return (0..<height).compactMap { rep.colorAt(x: width / 2, y: $0) }
    }

    // MARK: - Nothing translucent inside the flag

    /// A band edge landing on a fraction of a pixel produced a row blended
    /// from two colours *and* from the background: alpha 0.78 through the
    /// middle of the Dutch flag. Only the rounded corners may be partly
    /// transparent.
    func testTheInteriorIsFullyOpaqueAtEverySize() {
        for points in [CGFloat(9), 11, 13, 15, 18] {
            for region in FlagArt.drawnRegions {
                guard let art = FlagArt.flag(region: region) else { continue }
                for (row, colour) in column(art, points: points).enumerated() {
                    XCTAssertEqual(colour.alphaComponent, 1, accuracy: 0.02,
                                   "\(region) at \(points) pt, row \(row) is see-through")
                }
            }
        }
    }

    // MARK: - Bands are the colours they were given

    /// Every row of a striped flag must be one of the flag's own colours. A
    /// blend of two of them is the pink line that appeared between the Dutch
    /// red and white.
    func testEveryRowIsOneOfTheFlagsOwnColours() {
        let cases: [(String, FlagArt)] = FlagArt.drawnRegions.compactMap { region in
            guard case let .bands(_, _, vertical)? = FlagArt.flag(region: region), !vertical,
                  let art = FlagArt.flag(region: region) else { return nil }
            return (region, art)
        }
        XCTAssertFalse(cases.isEmpty)
        for points in [CGFloat(9), 11, 13, 15, 18] {
            for (region, art) in cases {
                guard case let .bands(colors, _, _) = art else { continue }
                let allowed = colors.map(rgb)
                // The outline covers the first and last row by design.
                for (row, colour) in column(art, points: points).enumerated().dropFirst()
                where row < Int((points * 2).rounded()) - 1 {
                    XCTAssertTrue(allowed.contains { near($0, colour) },
                                  "\(region) at \(points) pt, row \(row) is \(hex(colour)), "
                                  + "which is not one of \(colors)")
                }
            }
        }
    }

    // MARK: - Proportions

    /// Spain is 1:2:1. Drawn as equal thirds — which is how it shipped — the
    /// yellow band comes out a third of the height instead of a half.
    func testSpainsMiddleBandIsHalfTheFlag() {
        let art = FlagArt.flag(region: "ES")!
        let rows = column(art, points: 18)
        let yellow = rows.filter { near(rgb("F1BF00"), $0) }.count
        XCTAssertEqual(Double(yellow), Double(rows.count) / 2, accuracy: 2)
    }

    /// Equal bands stay equal: three thirds of 36 px is 12 rows each, not
    /// 13/11/12 with a blend between them.
    func testEqualBandsComeOutEqual() {
        let art = FlagArt.flag(region: "RU")!
        let rows = column(art, points: 18)
        for hexColour in ["FFFFFF", "0039A6", "D52B1E"] {
            let count = rows.filter { near(rgb(hexColour), $0) }.count
            XCTAssertEqual(Double(count), Double(rows.count) / 3, accuracy: 2, hexColour)
        }
    }

    // MARK: - The outline is one pixel

    /// One device pixel, not one point. At 9 pt the flag is 18 px tall and a
    /// band is 6; a two-pixel outline took a third of it.
    func testTheOutlineCostsOneRowAtEachEnd() {
        let art = FlagArt.flag(region: "RU")!
        let rows = column(art, points: 9)
        XCTAssertEqual(rows.count, 18)
        let white = rows.filter { near(rgb("FFFFFF"), $0) }.count
        // Six rows of white, less the single outline row over it.
        XCTAssertGreaterThanOrEqual(white, 5, "the outline is eating the band")
    }

    // MARK: - Size and shape

    func testEveryBadgeIsThreeByTwoAndAWholeNumberOfPixels() {
        for points in [CGFloat(9), 11, 13, 15, 18] {
            let (_, width, height) = pixels(FlagArt.flag(region: "JP")!, points: points)
            XCTAssertEqual(height, Int((points * 2).rounded()))
            XCTAssertEqual(width, Int((points * 1.5 * 2).rounded()))
        }
    }

    /// The badge must not change width when the layout changes, or switching
    /// layouts shoves everything else in the menu bar sideways.
    func testEveryFlagIsTheSameWidth() {
        let widths = Set(FlagArt.drawnRegions.compactMap { region -> Int? in
            guard let art = FlagArt.flag(region: region) else { return nil }
            return pixels(art, points: 13).width
        })
        XCTAssertEqual(widths.count, 1)
    }

    // MARK: - Crosses are crosses

    /// Sweden's badge must not be two bands — that is the shape that made it
    /// Ukraine. The cross shows as yellow on both the middle row and a column
    /// left of centre.
    func testSwedenHasACrossAndNotTwoBands() {
        let (rep, width, height) = pixels(FlagArt.flag(region: "SE")!, points: 18)
        let yellow = rgb("FECB00")
        // Inside the outline and clear of the rounded corners.
        let middleRow = (2..<(width - 2)).compactMap { rep.colorAt(x: $0, y: height / 2) }
        XCTAssertTrue(middleRow.allSatisfy { near(yellow, $0) },
                      "the horizontal arm does not run the full width")
        // 6/16 of the width, which is left of centre: that offset is what
        // makes it Nordic rather than a centred cross.
        let axis = Int((CGFloat(width) * 6 / 16).rounded())
        let armColumn = (2..<(height - 2)).compactMap { rep.colorAt(x: axis, y: $0) }
        XCTAssertTrue(armColumn.allSatisfy { near(yellow, $0) },
                      "the vertical arm is not at 6/16 of the width")
        XCTAssertTrue(near(rgb("005293"), rep.colorAt(x: width - 4, y: height / 4)!),
                      "the field is not blue where the cross is not")
    }

    // MARK: - Helpers

    private func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        return (CGFloat((value >> 16) & 0xFF) / 255,
                CGFloat((value >> 8) & 0xFF) / 255,
                CGFloat(value & 0xFF) / 255)
    }

    private func near(_ expected: (CGFloat, CGFloat, CGFloat), _ actual: NSColor) -> Bool {
        guard let c = actual.usingColorSpace(.deviceRGB) else { return false }
        return abs(c.redComponent - expected.0) < 0.06
            && abs(c.greenComponent - expected.1) < 0.06
            && abs(c.blueComponent - expected.2) < 0.06
    }

    private func hex(_ colour: NSColor) -> String {
        guard let c = colour.usingColorSpace(.deviceRGB) else { return "?" }
        return String(format: "%02X%02X%02X", Int(c.redComponent * 255),
                      Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
