import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **Every tool's mark lands where it was drawn on both axes of an edited picture, at the thickness its step says.**
/// «Edit» exports the layers over the finished picture at its own size, and `CaptureSession.annotated(_:local:layers:)`
/// takes them there with a ratio per axis (`Annotation.mapped(_:)`), so a mark of any tool is moved by the same two
/// numbers and drawn with one stroke width, `pixelsPerPoint`. The check is read out of the file, tool by tool
/// (the strokes in `strokeTools`, every case of `AnnotationTool.allCases` in the mapping test: a tool added to the list stops the switches below from compiling): where the ink is, how far
/// it spans, how thick a stroke is, and that a picture that is not larger than the display is drawn as it always was.
///
/// The pictures: a thin tall one and a wide short one, whose two ratios differ by tens of per cent (the rounding of the
/// side that does not decide), and two larger than the display, on a 100 × 60-point display. The model has no rotation.
///
/// Total failure of the subject prints: a mark that lands off its drawn place by tens of pixels, a stroke scaled on one axis,
/// a tool the transform forgot.
final class TheMappedMarksLandWhereDrawnForEveryToolTests: XCTestCase {

    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private func solid(_ width: Int, _ height: Int, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: srgb, components: [r, g, b, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func freeze(scale: CGFloat) -> Freeze {
        Freeze(displays: [.image(FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 60), scale: scale,
                                               image: solid(Int(100 * scale), Int(60 * scale), 1, 0, 0)))], windows: [])
    }

    private func placed(_ w: Int, _ h: Int, scale: CGFloat, file: StaticString = #filePath, line: UInt = #line) throws -> PictureOnScreen {
        try XCTUnwrap(PictureOnScreen.place(solid(w, h, 1, 1, 1), over: freeze(scale: scale), on: nil), "\(w)×\(h) not placed", file: file, line: line)
    }

    /// The whole picture's export, read as a picture: a refusal to make one is a failure here and not a nil.
    private func exported(_ shown: PictureOnScreen, _ layers: [Annotation], _ what: String = "",
                          file: StaticString = #filePath, line: UInt = #line) async throws -> CGImage {
        let image = await session().annotated(shown, local: shown.rect, layers: layers)
        return try XCTUnwrap(image, what, file: file, line: line)
    }

    private func session() -> CaptureSession { Rig(home: scratchDirectory("shots-mapped")).session }

    /// The picture's pixels in device RGB, row 0 at the top.
    fileprivate static func bytes(_ image: CGImage) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
        out.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return out
    }

    /// How much of the ink each column and each row of the file holds, as the lowest channel's distance from white.
    private struct Ink {
        let columns: [Double], rows: [Double], width: Int, height: Int
        init(_ image: CGImage) {
            let b = TheMappedMarksLandWhereDrawnForEveryToolTests.bytes(image), w = image.width, h = image.height
            var columns = [Double](repeating: 0, count: w), rows = [Double](repeating: 0, count: h)
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    let darkest = min(b[i], b[i + 1], b[i + 2])
                    guard darkest < 235 else { continue }
                    columns[x] += 1
                    rows[y] += 1
                }
            }
            self.columns = columns; self.rows = rows; width = w; height = h
        }
        /// First and last row, or column, with ink, the last as an edge: nil when the picture holds none.
        func extent(vertical: Bool) -> (lo: Double, hi: Double)? {
            let share = vertical ? rows : columns
            guard let first = share.firstIndex(where: { $0 > 0 }), let last = share.lastIndex(where: { $0 > 0 }) else { return nil }
            return (Double(first), Double(last + 1))
        }
    }

    /// A picture's pixels at `(x, y)`: the darkest channel's distance from white.
    private func weight(_ b: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> Double {
        let i = (y * w + x) * 4
        return 255 - Double(min(b[i], b[i + 1], b[i + 2]))
    }

    /// The thickness of the stroke along a line of pixels: the sum of the weights over the line's strongest one.
    private func thickness(_ image: CGImage, along column: Int?, row: Int?) -> Double {
        let b = Self.bytes(image), w = image.width, h = image.height
        let line: [Double] = column.map { x in (0..<h).map { weight(b, w, x, $0) } } ?? (0..<w).map { weight(b, w, $0, row!) }
        let peak = line.max() ?? 0
        guard peak > 0 else { return 0 }
        return line.reduce(0) { $0 + $1 / peak }
    }

    // MARK: What each tool draws

    /// A mark of `tool` between two fractions of the picture's rectangle, in the points of the display, thin; and the
    /// fractions in the order x1, y1, x2, y2 that the file's ink must stand at.
    private func mark(_ tool: AnnotationTool, on shown: PictureOnScreen, _ f: (x1: Double, y1: Double, x2: Double, y2: Double),
                      thickness: AnnotationThickness = .thin) -> Annotation {
        let r = shown.rect
        func at(_ fx: Double, _ fy: Double) -> CGPoint { CGPoint(x: r.minX + CGFloat(fx) * r.width, y: r.minY + CGFloat(fy) * r.height) }
        let a = at(f.x1, f.y1), b = at(f.x2, f.y2)
        let style = AnnotationStyle(thickness: thickness)
        switch tool {
        case .arrow, .rectangle, .ellipse, .line:
            return Annotation(tool: tool, start: a, end: b, style: style)
        case .pen, .pencil, .highlighter:
            // Collinear points: the smoothing leaves a straight run, so the ink is a stroke of a known box.
            let points = (0...4).map { at(f.x1 + (f.x2 - f.x1) * Double($0) / 4, f.y1 + (f.y2 - f.y1) * Double($0) / 4) }
            return Annotation(tool: tool, start: a, end: b, points: points, style: style)
        case .blur, .text, .step, .spotlight, .magnifier, .emoji:
            preconditionFailure("\(tool) draws no stroke; `testMappingKeepsEveryFieldOfEveryTool` is its check")
        }
    }

    /// Whether the span of the ink is the geometry's plus the stroke on both sides, exactly: the stroke has round or
    /// mitred ends (the line, the pen, the box tools) and no grain.
    private func spansExactly(_ tool: AnnotationTool) -> Bool {
        switch tool {
        case .line, .pen, .rectangle, .ellipse: true
        case .arrow, .pencil, .highlighter: false
        case .blur, .text, .step, .spotlight, .magnifier, .emoji: false
        }
    }

    /// The tools whose mark is a stroke, measured by ink on a plain picture; the others (a mosaic, a line of text, a
    /// numbered circle, a dim with a hole) are not ink on a plain picture and are held by the test of the mapping itself.
    private static let strokeTools: [AnnotationTool] = [.arrow, .rectangle, .ellipse, .line, .pen, .pencil, .highlighter]

    /// `Annotation.mapped(_:)` takes the geometry through the transform and nothing else away: a field it forgot would
    /// export a mark that is not the one on the screen (the text a layer holds is the field it once forgot).
    func testMappingKeepsEveryFieldOfEveryTool() {
        for tool in AnnotationTool.allCases {
            let style = AnnotationStyle(thickness: .thick, opacity: 0.5)
            let layer = Annotation(tool: tool, start: CGPoint(x: 1, y: 2), end: CGPoint(x: 5, y: 8),
                                   points: [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)], style: style, text: "words", id: 7)
            let moved = layer.mapped { CGPoint(x: $0.x * 2, y: $0.y + 10) }
            XCTAssertEqual(moved.tool, tool)
            XCTAssertEqual(moved.start, CGPoint(x: 2, y: 12), "\(tool)")
            XCTAssertEqual(moved.end, CGPoint(x: 10, y: 18), "\(tool)")
            XCTAssertEqual(moved.points, [CGPoint(x: 2, y: 12), CGPoint(x: 6, y: 14)], "\(tool)")
            XCTAssertEqual(moved.style, style, "\(tool)")
            XCTAssertEqual(moved.text, "words", "\(tool): the text a layer holds is not dropped by the mapping")
            XCTAssertEqual(moved.id, 7, "\(tool)")
            switch tool {  // no `default:`: a tool added to the list is named here
            case .arrow, .rectangle, .ellipse, .line, .pen, .pencil, .highlighter, .blur, .text, .step, .spotlight, .magnifier, .emoji: break
            }
        }
    }

    private static let pictures: [(w: Int, h: Int, scale: CGFloat, name: String)] = [
        (201, 5003, 2, "thin and tall"), (49, 3000, 2, "a hairline tall"), (5003, 201, 2, "wide and short"),
        (6000, 40, 2, "a hairline wide"), (1601, 959, 2, "larger than the display"), (1001, 667, 1, "larger than a display at 1×"),
    ]

    func testEveryToolsMarkLandsWhereItWasDrawnOnBothAxesAndSpansAsFarAsItWasDrawn() async throws {
        var measured: [String: Int] = [:]
        var report: [String] = []
        for p in Self.pictures {
            let shown = try placed(p.w, p.h, scale: p.scale)
            let ppp = Double(shown.pixelsPerPoint)
            let tolerance = ppp / Double(p.scale) + 1.5
            for tool in Self.strokeTools {
                // The arrow is measured along its own length: a horizontal one, whose tip and tail are exact.
                let f = tool == .arrow ? (x1: 0.2, y1: 0.5, x2: 0.7, y2: 0.5) : (x1: 0.2, y1: 0.3, x2: 0.7, y2: 0.8)
                let layer = mark(tool, on: shown, f)
                let out = try await exported(shown, [layer], "\(p.name) \(tool)")
                XCTAssertEqual(out.width, p.w, "\(p.name) \(tool)")
                XCTAssertEqual(out.height, p.h, "\(p.name) \(tool)")
                let ink = Ink(out)
                let half = (layer.stroke?.width ?? 0) * CGFloat(ppp) / 2
                for (vertical, size, lo, hi) in [(false, p.w, f.x1, f.x2), (true, p.h, f.y1, f.y2)] {
                    // A stroke that reaches the picture's edge is clipped there and its centre is not the geometry's;
                    // an arrow is measured along its length only (its head is as wide as ten times the shaft).
                    let reach = tool == .arrow ? (vertical ? Double.infinity : 0) : Double(half)
                    guard reach.isFinite, lo * Double(size) - reach > 1, hi * Double(size) + reach < Double(size) - 1 else { continue }
                    guard let found = ink.extent(vertical: vertical) else { XCTFail("\(p.name) \(tool): no ink"); continue }
                    measured[String(describing: tool), default: 0] += 1
                    let slack = tool == .pencil ? tolerance + 4 : tolerance
                    let centre = (found.lo + found.hi) / 2, want = (lo + hi) / 2 * Double(size)
                    report.append("\(p.name) \(tool) \(vertical ? "y" : "x"): \(String(format: "%+.1f", centre - want)) of \(String(format: "%.1f", slack))")
                    XCTAssertEqual(centre, want, accuracy: slack, "\(p.name) \(tool): the ink's \(vertical ? "vertical" : "horizontal") centre is \(centre) of \(size), drawn at \(want)")
                    if spansExactly(tool) {
                        let span = found.hi - found.lo, wantSpan = (hi - lo) * Double(size) + 2 * Double(half)
                        XCTAssertEqual(span, wantSpan, accuracy: 2 * slack, "\(p.name) \(tool): the ink spans \(span), drawn \(wantSpan)")
                    }
                }
            }
        }
        for tool in Self.strokeTools {
            XCTAssertGreaterThanOrEqual(measured[String(describing: tool), default: 0], 4,
                                        "the control: too few axes of \(tool) were measurable\n\(report.joined(separator: "\n"))")
        }
        print("MAPPED MARKS\n" + report.joined(separator: "\n"))
    }

    /// Pictures a stroke fits across on both sides: a hairline's stroke is wider than the picture, so only these can be measured.
    private static let broadPictures: [(w: Int, h: Int, scale: CGFloat, name: String)] = [
        (2001, 5003, 2, "tall, the width's ratio rounded"), (5003, 2001, 2, "wide, the height's ratio rounded"),
        (1601, 959, 2, "larger than the display"), (1001, 667, 1, "larger than a display at 1×"),
    ]

    /// A stroke is `width × pixelsPerPoint` thick across its own line on BOTH axes of a picture whose ratios differ: a
    /// stroke scaled by each axis's own ratio would be thicker one way than the other.
    func testAStrokeIsAsThickAcrossAsAlongOnAPictureWhoseRatiosDiffer() async throws {
        var measured = 0
        for p in Self.broadPictures {
            let shown = try placed(p.w, p.h, scale: p.scale)
            let ppp = Double(shown.pixelsPerPoint)
            // The edges of a box and the arcs of an ellipse: the top arc across the vertical, the left arc across the horizontal.
            for tool in [AnnotationTool.rectangle, .ellipse] {
                let layer = mark(tool, on: shown, (x1: 0.2, y1: 0.2, x2: 0.8, y2: 0.8))
                let want = Double(layer.stroke!.width) * ppp
                guard want < 0.15 * Double(min(p.w, p.h)) else { continue }
                let out = try await exported(shown, [layer])
                // The middle column crosses the top edge and the bottom edge, the middle row the left and the right.
                for (across, label) in [(true, "top and bottom"), (false, "left and right")] {
                    let got = across ? thickness(out, along: p.w / 2, row: nil) : thickness(out, along: nil, row: p.h / 2)
                    measured += 1
                    XCTAssertEqual(got, 2 * want, accuracy: max(2, 0.03 * want), "\(p.name) \(tool) \(label): \(got / 2) of \(want) pixels thick each")
                }
            }
            // A line or a stroke across the picture: the thickness across it.
            for tool in [AnnotationTool.line, .pen, .highlighter] {
                for horizontal in [true, false] {
                    let f = horizontal ? (x1: 0.2, y1: 0.5, x2: 0.8, y2: 0.5) : (x1: 0.5, y1: 0.2, x2: 0.5, y2: 0.8)
                    let layer = mark(tool, on: shown, f)
                    let want = Double(layer.stroke!.width) * ppp
                    guard want < 0.15 * Double(min(p.w, p.h)) else { continue }
                    let out = try await exported(shown, [layer])
                    let got = horizontal ? thickness(out, along: p.w / 2, row: nil) : thickness(out, along: nil, row: p.h / 2)
                    measured += 1
                    XCTAssertEqual(got, want, accuracy: max(2, 0.03 * want),
                                   "\(p.name) \(tool) \(horizontal ? "horizontal" : "vertical"): \(got) of \(want) pixels thick")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(measured, 30, "the control: too few thicknesses were measurable")
    }

    // MARK: A narrowed area

    /// A narrowed area is a cut of the same marks on the same pixels: the ink in the cut stands where it stood in the whole
    /// export, less the cut's own origin, on both axes, whatever the ratios of the picture are. The area is the lower right
    /// 60 % of the picture's rectangle; a line stands across it at 50 % and 90 %, one way and the other.
    func testANarrowedAreaKeepsTheMarksOnTheSamePixelsOfThePicture() async throws {
        var measured = 0
        for p in Self.broadPictures + [Self.pictures[0], Self.pictures[2]] {
            let shown = try placed(p.w, p.h, scale: p.scale)
            let r = shown.rect
            let layers = [mark(.line, on: shown, (x1: 0.5, y1: 0.55, x2: 0.9, y2: 0.55)),
                          mark(.line, on: shown, (x1: 0.55, y1: 0.5, x2: 0.55, y2: 0.9))]
            let area = CGRect(x: r.minX + 0.4 * r.width, y: r.minY + 0.4 * r.height, width: 0.6 * r.width, height: 0.6 * r.height)
            let whole = try await exported(shown, layers, p.name)
            let cut = await session().annotated(shown, local: area, layers: layers)
            let part = try XCTUnwrap(cut, p.name)
            let originX = p.w - part.width, originY = p.h - part.height
            XCTAssertEqual(Double(originX), 0.4 * Double(p.w), accuracy: Double(shown.pixelsPerPoint) + 2, "\(p.name): the cut's own origin across")
            XCTAssertEqual(Double(originY), 0.4 * Double(p.h), accuracy: Double(shown.pixelsPerPoint) + 2, "\(p.name): the cut's own origin down")
            let inWhole = Ink(whole), inPart = Ink(part)
            for (vertical, origin) in [(false, originX), (true, originY)] {
                guard let w = inWhole.extent(vertical: vertical), let c = inPart.extent(vertical: vertical) else {
                    XCTFail("\(p.name): no ink"); continue
                }
                // The line along the axis starts at 50 % in the whole export, the cut's own edge is at 40 %.
                let wanted = max(w.lo - Double(origin), 0)
                measured += 1
                XCTAssertEqual(c.lo, wanted, accuracy: 2.5, "\(p.name): the ink of the cut begins \(c.lo) from its edge, \(wanted) in the whole export")
            }
        }
        XCTAssertGreaterThanOrEqual(measured, 12)
    }

    // MARK: A picture that is not larger than the display

    /// The old way: the layers shifted to the picture's own origin and drawn with `draw`, no ratio at all.
    private func unmapped(_ shown: PictureOnScreen, _ layers: [Annotation]) -> CGImage? {
        let picture = shown.picture, ppp = shown.pixelsPerPoint, stand = shown.rect
        let shift = { (p: CGPoint) in CGPoint(x: p.x - stand.minX, y: p.y - stand.minY) }
        guard let pixels = ScreenSpace.pixels(ofLocal: CGRect(origin: .zero, size: stand.size), scale: ppp,
                                              imageWidth: picture.width, imageHeight: picture.height),
              let cut = picture.cropping(to: pixels) else { return nil }
        return CaptureSession.draw(layers.map { $0.mapped(shift) }, over: cut, at: pixels.origin, scale: ppp, display: picture)
    }

    func testAPictureNotLargerThanTheDisplayExportsByteForByteAsItDidWithNoRatio() async throws {
        var compared = 0, differing: [String] = []
        for scale in [CGFloat(1), 2, 3] {
            for (w, h) in [(100, 60), (80, 40), (333, 77), (201, 121), (1, 1), (299, 179), (150, 90), (97, 59), (61, 33)] {
                guard CGFloat(w) <= 100 * scale, CGFloat(h) <= 60 * scale else { continue }
                let shown = try placed(w, h, scale: scale)
                XCTAssertEqual(shown.pixelsPerPoint, scale, "the control: \(w)×\(h) at \(scale)× fits, one pixel to a pixel")
                let layers = Self.strokeTools.enumerated().map { index, tool in
                    mark(tool, on: shown, (x1: 0.1 + 0.05 * Double(index), y1: 0.15, x2: 0.9 - 0.03 * Double(index), y2: 0.85),
                         thickness: .medium)
                }
                let now = try await exported(shown, layers)
                let then = try XCTUnwrap(unmapped(shown, layers))
                compared += 1
                if Self.bytes(now) != Self.bytes(then) { differing.append("\(w)×\(h)@\(Int(scale))") }
            }
        }
        XCTAssertGreaterThan(compared, 15, "the control: the sweep compared pictures")
        XCTAssertTrue(differing.isEmpty, "a picture that fits the display is drawn differently from before the ratio: \(differing)")
    }

    func testTheIdentityTransformChangesNoMark() {
        for tool in Self.strokeTools {
            let layer = Annotation(tool: tool, start: CGPoint(x: 1.5, y: 2.5), end: CGPoint(x: 30, y: 40),
                                   points: tool.isFreehand ? [CGPoint(x: 1.5, y: 2.5), CGPoint(x: 9, y: 9), CGPoint(x: 30, y: 40)] : [],
                                   style: AnnotationStyle(color: .blue, thickness: .thick, filled: true, opacity: 0.5), id: 7)
            let same = layer.mapped { $0 }
            XCTAssertEqual(same.start, layer.start, "\(tool)")
            XCTAssertEqual(same.end, layer.end, "\(tool)")
            XCTAssertEqual(same.points, layer.points, "\(tool)")
            XCTAssertEqual(same.style, layer.style, "\(tool)")
            XCTAssertEqual(same.id, layer.id, "\(tool)")
            XCTAssertEqual(same.tool, layer.tool)
            let doubled = layer.mapped { CGPoint(x: $0.x * 2, y: $0.y * 3) }
            XCTAssertEqual(doubled.end, CGPoint(x: 60, y: 120), "\(tool): the end")
            XCTAssertEqual(doubled.points, layer.points.map { CGPoint(x: $0.x * 2, y: $0.y * 3) }, "\(tool): every point of the trail")
            XCTAssertEqual(doubled.style, layer.style, "\(tool): a move of the geometry is not a restyle")
        }
    }

    // MARK: Geometry nobody meant

    /// Marks that are no geometry: not a number, infinite, huge. A mark whose points are not numbers draws nothing and
    /// takes nothing with it: the file with them before and after an ordinary mark is that mark alone, byte for byte; and
    /// the wild ones (infinite, far past the picture, 1e300) leave a file of the picture's size and never the display's.
    func testMarksOfNoGeometryLeaveTheFileTheSizeAndTheOrdinaryMarkInPlace() async throws {
        for p in [Self.pictures[0], Self.pictures[2], Self.pictures[4]] {
            let shown = try placed(p.w, p.h, scale: p.scale)
            let ordinary = mark(.line, on: shown, (x1: 0.2, y1: 0.5, x2: 0.8, y2: 0.5))
            let alone = try await exported(shown, [ordinary])
            let nan = CGFloat.nan, inf = CGFloat.infinity
            var notNumbers: [Annotation] = [], wild: [Annotation] = []
            for tool in Self.strokeTools {
                let points = tool.isFreehand ? [CGPoint(x: nan, y: 1), CGPoint(x: 5, y: nan)] : []
                notNumbers.append(Annotation(tool: tool, start: CGPoint(x: nan, y: nan), end: CGPoint(x: nan, y: nan), points: points))
                wild.append(Annotation(tool: tool, start: CGPoint(x: inf, y: -inf), end: CGPoint(x: -inf, y: inf),
                                       points: tool.isFreehand ? [CGPoint(x: inf, y: 0), CGPoint(x: 0, y: -inf)] : []))
                // The pencil is left out of the 1e300 marks: its grain traps on a point whose pixel is past Int
                // (`PencilGrain.build`), and a trap ends the whole run. Nothing the editor holds comes near it: a point stays in the display.
                guard tool != .pencil else { continue }
                wild.append(Annotation(tool: tool, start: CGPoint(x: 1e300, y: -1e300), end: CGPoint(x: -1e300, y: 1e300),
                                       points: tool.isFreehand ? [CGPoint(x: 1e300, y: 1e300), CGPoint(x: -1e300, y: 0)] : []))
            }
            let around = try await exported(shown, notNumbers + [ordinary] + notNumbers, p.name)
            XCTAssertEqual(around.width, p.w, p.name)
            XCTAssertEqual(around.height, p.h, p.name)
            XCTAssertTrue(Self.bytes(around) == Self.bytes(alone), "\(p.name): marks that are not numbers changed the file")
            let rough = try await exported(shown, wild + [ordinary] + wild, p.name)
            XCTAssertEqual(rough.width, p.w, p.name)
            XCTAssertEqual(rough.height, p.h, p.name)
            XCTAssertGreaterThan(Ink(rough).rows[p.h / 2], 0, "\(p.name): the ordinary mark is gone from the middle row")
        }
    }
}
