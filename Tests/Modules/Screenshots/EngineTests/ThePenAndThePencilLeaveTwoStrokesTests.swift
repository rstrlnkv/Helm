import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The pen leaves a smooth stroke and the pencil a grainy one, and the pencil's grain is the same wherever
/// it is drawn.** R26: the screen draws at the display's scale and the file draws a crop of it, so a random
/// grain would differ between them and between two exports. The grain is a function of the stroke's own points
/// and of the image's pixels, so it moves with the stroke and does not care where the cut begins.
///
/// What each would print if it failed totally: a grain that is all on is the pen (no gaps, "different pixels"
/// reports 0 differing); a grain that is all off draws nothing (the pencil's ink share is near 0, under the floor).
/// Every export here is a real `CaptureSession.annotated` over white, read for the ink share of black ink in the red channel.
final class ThePenAndThePencilLeaveTwoStrokesTests: XCTestCase {

    /// Ink share of every pixel, row-major from the top: 0 is white, 1 is black.
    private struct Ink {
        let width: Int, height: Int
        let values: [Double]
        let bytes: [UInt8]
        func at(_ x: Int, _ y: Int) -> Double { values[y * width + x] }
    }

    private func read(_ image: CGImage) -> Ink {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let raw = context.data!.assumingMemoryBound(to: UInt8.self)
        let bytes = Array(UnsafeBufferPointer(start: raw, count: image.width * image.height * 4))
        let values = (0..<(image.width * image.height)).map { (255 - Double(bytes[$0 * 4])) / 255 }
        return Ink(width: image.width, height: image.height, values: values, bytes: bytes)
    }

    private func export(_ layer: Annotation, scale: CGFloat, local: CGRect = CGRect(x: 0, y: 0, width: 200, height: 120),
                        name: String) async throws -> Ink {
        try await export([layer], scale: scale, local: local, name: name)
    }

    private func export(_ layers: [Annotation], scale: CGFloat, local: CGRect = CGRect(x: 0, y: 0, width: 200, height: 120),
                        name: String) async throws -> Ink {
        let image = makeImage(width: Int(200 * scale), height: Int(120 * scale), red: 255, green: 255, blue: 255)
        let freeze = Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 200, height: 120),
                                                            scale: scale, image: image))], windows: [])
        let rig = Rig(home: scratchDirectory(name))
        let drawn = await rig.session.annotated(freeze, display: DisplayID(1), local: local, layers: layers)
        return read(try XCTUnwrap(drawn))
    }

    private static let thick = CGFloat(5)  // the pencil's thick step, in points (`AnnotationThickness.points`)

    /// A horizontal run with a middle point, shifted by `by` points.
    private func layer(_ tool: AnnotationTool, by shift: CGPoint = .zero, mid: CGFloat = 95) -> Annotation {
        let from = CGPoint(x: 20 + shift.x, y: 60 + shift.y), to = CGPoint(x: 170 + shift.x, y: 60 + shift.y)
        return Annotation(tool: tool, start: from, end: to, points: [from, CGPoint(x: mid + shift.x, y: 60 + shift.y), to],
                          style: AnnotationStyle(color: .black, thickness: .thick, filled: false, opacity: 1))
    }

    /// The pixels well inside the pencil's stroke, derived from the geometry here and not from any export: a
    /// run 20…170 pt at y 60 pt, 5 pt wide, with 1.5 px kept off the edge and 3 px off the ends (the round caps).
    private func body(scale: CGFloat, shift: CGPoint = .zero) -> [(x: Int, y: Int)] {
        let half = Self.thick * scale / 2 - 1.5
        let centreY = (60 + shift.y) * scale
        let xs = Int(((20 + shift.x) * scale + Self.thick * scale / 2 + 1.5).rounded(.up))
        let xe = Int(((170 + shift.x) * scale - Self.thick * scale / 2 - 1.5).rounded(.down))
        var pixels: [(Int, Int)] = []
        for y in Int((centreY - half - 0.5).rounded(.up))...Int((centreY + half - 0.5).rounded(.down)) {
            for x in xs...xe { pixels.append((x, y)) }
        }
        return pixels
    }

    // MARK: - Two strokes

    func testThePencilHasGapsInItsBodyWhereThePenIsSolid() async throws {
        for scale in [CGFloat(1), 2] {
            let pixels = body(scale: scale)
            XCTAssertGreaterThan(pixels.count, 200, "the body probe is empty at \(scale)x")
            for tool in [AnnotationTool.pen, .line] {
                let ink = try await export(layer(tool), scale: scale, name: "pen-solid-\(tool)-\(Int(scale))")
                let thin = pixels.filter { ink.at($0.x, $0.y) < 0.98 }.count
                XCTAssertEqual(thin, 0, "\(tool) \(scale)x: \(thin) of \(pixels.count) body pixels are not solid; only the pencil has grain")
            }
            let pencil = try await export(layer(.pencil), scale: scale, name: "pencil-gaps-\(Int(scale))")
            let share = pixels.map { pencil.at($0.x, $0.y) }
            let gaps = Double(share.filter { $0 < 0.9 }.count) / Double(pixels.count)
            let solid = Double(share.filter { $0 >= 0.98 }.count) / Double(pixels.count)
            let bare = Double(share.filter { $0 <= 0.1 }.count) / Double(pixels.count)
            let mean = share.reduce(0, +) / Double(share.count)
            // The width the ink adds up to: every row of each body column, averaged over the columns, in points.
            let columns = Set(pixels.map(\.x))
            let mass = columns.reduce(0.0) { sum, x in sum + (0..<pencil.height).reduce(0.0) { $0 + pencil.at(x, $1) } }
            let effective = mass / Double(columns.count) / Double(scale)
            // The approved frame's graphite (palette-frames/f-strokes9.png, SVG `graphite9`: alpha = clamp(1.45 - 1.6 * noise)),
            // read at 2x over 2, 3.5 and 5 pt, over the body (deeper than w/2 - 0.75 px), by thirds of each stroke: fully inked
            // 3.6-6.1 %, nearly bare (<= 10 %) 0-0.3 %, mean ink 0.643-0.653, effective width 0.648-0.659 of the nominal.
            // Ours is held to the same distribution with room for a 1x body of 286 pixels (a binomial's spread at 5 % is 1.29 points):
            // at most 15 % fully inked (the old grain's hash, commit 2f1d9e2c, puts 50-57 % there: solid ink with holes), at most 2 % nearly bare
            // (the old grain ~5 %), mean ink 0.66 +- 0.06 (the old grain 0.77-0.78), effective width 0.65 of the nominal +- 0.07 (the old grain 0.78).
            // The pen is told apart by the gaps floor; no ceiling on gaps, since the reference's fine graphite is ~90 % under 0.9.
            XCTAssertGreaterThanOrEqual(gaps, 0.08, "pencil \(scale)x: gaps are \(gaps) of the body; a grain that is all on is the pen")
            XCTAssertLessThanOrEqual(solid, 0.15, "pencil \(scale)x: \(solid) of the body is fully inked; the reference's graphite has 4-6 %, a pencil of solid ink with holes has half")
            XCTAssertLessThanOrEqual(bare, 0.02, "pencil \(scale)x: \(bare) of the body is nearly bare; the reference has none to speak of")
            XCTAssertEqual(mean, 0.66, accuracy: 0.06, "pencil \(scale)x: mean ink \(mean); the reference's is 0.65, a grain all off draws nothing, all on is the pen")
            XCTAssertEqual(effective, 0.65 * Double(Self.thick), accuracy: 0.07 * Double(Self.thick),
                           "pencil \(scale)x: the ink adds up to \(effective) pt of the 5 pt stroke; the reference's is 0.65 of it")
            // The grain runs the length of the stroke: every 30-pixel band of columns has gaps, not one clump.
            let xs = pixels.map(\.x)
            let first = xs.min()!, last = xs.max()!
            var band = first
            while band + 30 <= last {
                let inBand = pixels.filter { $0.x >= band && $0.x < band + 30 }
                let bandGaps = Double(inBand.filter { pencil.at($0.x, $0.y) < 0.9 }.count) / Double(inBand.count)
                XCTAssertGreaterThan(bandGaps, 0.02, "pencil \(scale)x: columns \(band)..<\(band + 30) have no gaps; the grain is in one place")
                band += 30
            }
        }
    }

    func testTheSamePathDrawnWithThePenAndThePencilGivesDifferentPixelsInTheFile() async throws {
        let pixels = body(scale: 2)
        let pen = try await export(layer(.pen), scale: 2, name: "pen-vs-pencil-pen")
        let pencil = try await export(layer(.pencil), scale: 2, name: "pen-vs-pencil-pencil")
        let differing = pixels.filter { abs(pen.at($0.x, $0.y) - pencil.at($0.x, $0.y)) > 0.1 }.count
        XCTAssertGreaterThan(Double(differing) / Double(pixels.count), 0.08,
                             "\(differing) of \(pixels.count) body pixels differ between pen and pencil")
        XCTAssertNotEqual(pen.bytes, pencil.bytes, "the file is the same for the pen and the pencil")
    }

    // MARK: - One grain

    func testTwoExportsInARowGiveByteIdenticalPencilPixels() async throws {
        for scale in [CGFloat(1), 2] {
            let first = try await export(layer(.pencil), scale: scale, name: "pencil-twice-a-\(Int(scale))")
            let second = try await export(layer(.pencil), scale: scale, name: "pencil-twice-b-\(Int(scale))")
            XCTAssertEqual(first.bytes, second.bytes, "\(scale)x: the grain differs between two exports of one stroke")
            let gapped = body(scale: scale).filter { first.at($0.x, $0.y) < 0.9 }.count
            XCTAssertGreaterThan(gapped, 20, "\(scale)x: the two exports are identical because both are solid, which proves no grain")
        }
    }

    /// The invariant: the grain belongs to the stroke, not to the page. The same path moved by whole pixels
    /// (7 and 5 here, at 2×, 3.5 and 2.5 points) gives the same ink, moved by the same pixels.
    func testThePathMovedByWholePixelsCarriesItsGrainWithIt() async throws {
        let moved = CGPoint(x: 3.5, y: 2.5)  // 7 and 5 pixels at 2×
        let a = try await export(layer(.pencil), scale: 2, name: "pencil-moved-a")
        let b = try await export(layer(.pencil, by: moved), scale: 2, name: "pencil-moved-b")
        let pixels = body(scale: 2)
        let partial = pixels.filter { a.at($0.x, $0.y) > 0.05 && a.at($0.x, $0.y) < 0.95 }.count
        XCTAssertGreaterThan(partial, 100, "the stroke has too few grainy pixels (\(partial)) for the comparison to mean anything")
        let off = pixels.filter { abs(a.at($0.x, $0.y) - b.at($0.x + 7, $0.y + 5)) > 0.03 }.count
        XCTAssertEqual(off, 0, "\(off) of \(pixels.count) body pixels changed when the stroke moved by 7×5 pixels: the grain is keyed to the page")
        // The check can tell: against the wrong shift (6, 5) the same comparison fails widely.
        let wrong = pixels.filter { abs(a.at($0.x, $0.y) - b.at($0.x + 6, $0.y + 5)) > 0.03 }.count
        XCTAssertGreaterThan(Double(wrong) / Double(pixels.count), 0.05, "a shift of one pixel passes too: the grain is flat along the stroke")
    }

    /// Screen and file: the overlay draws the whole display, the file draws the cut, whose first pixel is
    /// elsewhere. The grain at a given pixel of the display is the same in both. (The overlay's own layer is
    /// in the UI half and is not reached from here; what this holds is the one thing that makes the two
    /// agree, a grain that does not depend on where the cut begins.)
    func testTheCutAndTheWholeDisplayGiveTheGrainOnTheSamePixels() async throws {
        for scale in [CGFloat(1), 2] {
            let whole = try await export(layer(.pencil), scale: scale, name: "pencil-whole-\(Int(scale))")
            // A cut that starts mid-point (10.5 pt = 21 px at 2×; 11 pt at 1×) and is not at the origin on either axis.
            let origin = scale == 2 ? CGPoint(x: 10.5, y: 7.5) : CGPoint(x: 11, y: 8)
            let cut = try await export(layer(.pencil), scale: scale,
                                       local: CGRect(x: origin.x, y: origin.y, width: 120, height: 80), name: "pencil-cut-\(Int(scale))")
            let dx = Int(origin.x * scale), dy = Int(origin.y * scale)
            let pixels = body(scale: scale).filter { $0.x - dx >= 0 && $0.x - dx < cut.width && $0.y - dy >= 0 && $0.y - dy < cut.height }
            XCTAssertGreaterThan(pixels.count, 200, "\(scale)x: the cut holds too little of the stroke")
            XCTAssertGreaterThan(pixels.filter { whole.at($0.x, $0.y) < 0.9 }.count, 20, "\(scale)x: no grain in the compared part")
            let off = pixels.filter { abs(whole.at($0.x, $0.y) - cut.at($0.x - dx, $0.y - dy)) > 0.03 }.count
            XCTAssertEqual(off, 0, "\(scale)x: \(off) of \(pixels.count) pixels carry another grain in the cut than on the whole display")
        }
    }

    /// A cut that begins in the middle of the stroke, so that the stroke's bounding box starts left of the cut and the mask
    /// is clipped to the cut: a grain anchored on the part of the box that is inside the cut (its corner, not the stroke's
    /// first point) is the same on a cut that holds the whole stroke and different on this one.
    func testACutThatBeginsInsideTheStrokeGivesTheGrainOfTheWholeDisplay() async throws {
        for scale in [CGFloat(1), 2] {
            let whole = try await export(layer(.pencil), scale: scale, name: "pencil-mid-whole-\(Int(scale))")
            let origin = CGPoint(x: 61, y: 53)  // inside the run (20…170 pt); the cut's rows (53…93 pt) span the stroke's (57.5…62.5 pt)
            let cut = try await export(layer(.pencil), scale: scale,
                                       local: CGRect(x: origin.x, y: origin.y, width: 90, height: 40), name: "pencil-mid-cut-\(Int(scale))")
            let dx = Int((origin.x * scale).rounded()), dy = Int((origin.y * scale).rounded())
            let pixels = body(scale: scale).filter { $0.x - dx >= 0 && $0.x - dx < cut.width && $0.y - dy >= 0 && $0.y - dy < cut.height }
            XCTAssertGreaterThan(pixels.count, 150, "\(scale)x: the cut holds too little of the stroke")
            XCTAssertGreaterThan(pixels.filter { whole.at($0.x, $0.y) < 0.9 }.count, 15, "\(scale)x: no grain in the compared part")
            let off = pixels.filter { abs(whole.at($0.x, $0.y) - cut.at($0.x - dx, $0.y - dy)) > 0.03 }.count
            XCTAssertEqual(off, 0, "\(scale)x: \(off) of \(pixels.count) pixels carry another grain in a cut that begins inside the stroke")
        }
    }

    /// The pencil's clip and transform are its own: what is drawn before it and after it, in either order, comes out as
    /// it does alone. Two layers on different rows, so that each one's ink is its own and the sum of the two single
    /// exports is the export of both. A clip that outlives the pencil takes the next layer's ink away outside the pencil's
    /// mask; a transform that outlives it moves the next layer.
    func testALayerBesideAPencilIsDrawnAsItIsAlone() async throws {
        let shift = CGPoint(x: 0, y: 40)  // the other stroke is at y 100 pt, the pencil's at 60 pt
        for scale in [CGFloat(1), 2] {
            for order in ["pencil-first", "pencil-last"] {
                let pencil = layer(.pencil), line = layer(.line, by: shift)
                let both = try await export(order == "pencil-first" ? [pencil, line] : [line, pencil], scale: scale, name: "beside-\(order)-\(Int(scale))")
                let onlyPencil = try await export(pencil, scale: scale, name: "beside-p-\(order)-\(Int(scale))")
                let onlyLine = try await export(line, scale: scale, name: "beside-l-\(order)-\(Int(scale))")
                XCTAssertGreaterThan(onlyLine.values.filter { $0 > 0.9 }.count, 100, "\(scale)x: the line left no ink to compare")
                XCTAssertGreaterThan(onlyPencil.values.filter { $0 > 0.3 }.count, 100, "\(scale)x: the pencil left no ink to compare")  // 0.3, not 0.9: the grain is grey, only ~7 % of it is fully inked
                let off = (0..<both.values.count).filter { abs(both.values[$0] - min(1, onlyPencil.values[$0] + onlyLine.values[$0])) > 0.02 }.count
                XCTAssertEqual(off, 0, "\(scale)x \(order): \(off) pixels differ between both layers together and each alone")
            }
        }
    }

    /// The pencil's width to the sub-pixel, through the grain: in each row the most ink any column of a 30 pt stretch takes
    /// is the stroke's own cover of that row (a pixel with the grain at full has all of it), so the rows' maxima sum to the
    /// width in pixels, as a column of a grainless stroke does. A count of rows past a threshold sees a whole pixel's error
    /// and not a half one: the thin step at 2.5 pt (a quarter too wide) leaves the same four rows at 2x.
    func testThePencilsThinStepIsItsWidthToTheSubPixelThroughTheGrain() async throws {
        for scale in [CGFloat(1), 2] {
            for centre in [CGFloat(60), 60.25] {
                let from = CGPoint(x: 20, y: centre), to = CGPoint(x: 170, y: centre)
                let thin = Annotation(tool: .pencil, start: from, end: to, points: [from, CGPoint(x: 95, y: centre), to],
                                      style: AnnotationStyle(color: .black, thickness: .thin, filled: false, opacity: 1))
                let ink = try await export(thin, scale: scale, name: "pencil-thin-\(Int(scale))-\(Int(centre * 4))")
                let columns = Int(60 * scale)..<Int(90 * scale)
                let width = (0..<ink.height).reduce(0.0) { sum, row in sum + (columns.map { ink.at($0, row) }.max() ?? 0) }
                XCTAssertEqual(width, 2 * Double(scale), accuracy: 0.4, "\(scale)x centre \(centre): the pencil's thin step is \(width / Double(scale)) points, not 2")
            }
        }
    }

    // MARK: - No randomness

    /// Beside the behavioural checks above, not instead of them: the file draws no random number and reads no clock.
    func testThePencilGrainFileHasNoSourceOfRandomnessAndNoAppKit() throws {
        let path = "Sources/Modules/Screenshots/Engine/Logic/PencilGrain.swift"
        let code = SwiftSource.code(try RepoSource.text(of: path))
        XCTAssertGreaterThan(code.count, 200, "\(path) is empty: a scan of nothing finds nothing")
        for word in ["random", "arc4random", "SystemRandomNumberGenerator", "Date", "drand48", "UUID", "CFAbsoluteTime", "mach_absolute_time", "DispatchTime"] {
            XCTAssertFalse(code.lowercased().contains(word.lowercased()), "\(path) mentions \(word): the grain would differ between screen and file")
        }
        for word in ["import AppKit", "import SwiftUI", "import Cocoa"] {
            XCTAssertFalse(code.contains(word), "\(path) is engine code and imports no UI: \(word)")
        }
        XCTAssertTrue(code.contains("import CoreGraphics"), "the grain is a pure CG function")
    }
}
