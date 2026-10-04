import AppKit
import CoreGraphics
import CoreText
import Foundation
import XCTest
@testable import Module_Screenshots_Engine

/// **The system's reader, through the session and the blur, on a picture whose every line is drawn by this file:** the text of each personal
/// line is dark on white, so a pixel of it that is the same in the file as in the cut is a pixel of the text that the blur left. Silent
/// without `HELM_BENCH=1` (the answer is the system's models' on this Mac, which makes it a report and not a gate): run it as
/// `HELM_BENCH=1 bash Scripts/test.sh --filter TheRealReaderThroughTheSessionBlursWhatItFindsBenchmark`.
///
/// A line of plain words is on the picture too and must come out untouched, so a blur over everything would not pass.
final class TheRealReaderThroughTheSessionBlursWhatItFindsBenchmark: XCTestCase {

    private struct Row {
        let label: String
        let words: String
        /// The part of the words that is personal, or nil for a line of plain words.
        let secret: String?
        var personal: Bool { secret != nil }
    }

    private let rows = [
        Row(label: "A1", words: "Write to jane.doe@example.com for details", secret: "jane.doe@example.com"),
        Row(label: "A2", words: "Plain words that name nobody at all today", secret: nil),
        Row(label: "A3", words: "Call +1 415 555 0132 any day", secret: "+1 415 555 0132"),
        Row(label: "A4", words: "Card 4111 1111 1111 1111 exp 12/29", secret: "4111 1111 1111 1111"),
        Row(label: "A5", words: "See https://example.com/path?x=1 for more", secret: "https://example.com/path?x=1"),
    ]

    /// The picture, and for each row the pixel rectangle of the whole line as drawn (top-left origin) and the pixel columns of the secret in it.
    private func render(scale: CGFloat, size pointSize: CGFloat) throws -> (CGImage, [(line: CGRect, secret: Range<Int>?)]) {
        let width = Int(600 * scale), height = Int(300 * scale)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        var rects: [(line: CGRect, secret: Range<Int>?)] = []
        var y: CGFloat = 270
        for row in rows {
            let string = NSAttributedString(string: "\(row.label) \(row.words)", attributes: [
                .font: NSFont.systemFont(ofSize: pointSize), .foregroundColor: NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)])
            let line = CTLineCreateWithAttributedString(string)
            context.textPosition = CGPoint(x: 20, y: y)
            CTLineDraw(line, context)
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let advance = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            // Bottom-left points → top-left pixels: the line's own box, from its baseline, ascent and descent.
            let whole = CGRect(x: 20 * scale, y: (300 - (y + ascent)) * scale, width: CGFloat(advance) * scale, height: (ascent + descent) * scale).integral
            var columns: Range<Int>?
            if let secret = row.secret, let found = string.string.range(of: secret) {
                let range = NSRange(found, in: string.string)
                let from = (20 + CTLineGetOffsetForStringIndex(line, range.location, nil)) * scale
                let to = (20 + CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)) * scale
                columns = (Int(from.rounded(.up)) + 1)..<(Int(to.rounded(.down)) - 1)
            }
            rects.append((whole, columns))
            y -= 52
        }
        return (try XCTUnwrap(context.makeImage()), rects)
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    func testEveryPersonalLineLosesItsInkAndThePlainLineKeepsIt() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1", "set HELM_BENCH=1: the system's reader is this Mac's")
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("helm-real-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let fakes = Rig(home: home)
        let session = CaptureSession(capture: fakes.capture, writer: fakes.writer, trash: fakes.trash, pasteboard: fakes.pasteboard, preferences: fakes.preferences,
                                     shutter: fakes.shutter, textReader: VisionTextReader(), settings: { .defaults }, naming: { .english },
                                     now: { Date(timeIntervalSince1970: 1_790_000_000) },
                                     locations: ScreenshotsLocations(home: home, desktop: fakes.desktop))
        for (scale, size) in [(CGFloat(2), CGFloat(15)), (1, 15), (2, 11)] {
            let (image, rects) = try render(scale: scale, size: size)
            let display = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 600, height: 300), scale: scale, image: image)
            let freeze = Freeze(displays: [.image(display)], windows: [])
            let local = CGRect(x: 0, y: 0, width: 600, height: 300)
            guard case .read(let lines, let source) = await session.readText(freeze, display: DisplayID(1), local: local) else {
                return XCTFail("scale \(scale) size \(size): the system's reader did not read")
            }
            let kinds = lines.flatMap(\.matches).map(\.kind)
            XCTAssertGreaterThanOrEqual(kinds.count, 4, "scale \(scale) size \(size): the reader found \(kinds) in \(lines.count) lines")
            let finds = PersonalFinds.finds(in: lines, source: source, under: [])
            var editing = AnnotationEditing(bounds: local)
            editing.insert(blurs: finds)
            let cut = try XCTUnwrap(session.crop(freeze, display: DisplayID(1), local: local))
            let blurred = await session.annotated(freeze, display: DisplayID(1), local: local, layers: editing.layers)
            let file = try XCTUnwrap(blurred)
            let before = rgba(cut), after = rgba(file)
            for (row, drawn) in zip(rows, rects) {
                let rect = drawn.line
                var inked = 0, survived = 0
                let columns = drawn.secret ?? Int(rect.minX)..<Int(rect.maxX)
                for y in Int(rect.minY)..<min(file.height, Int(rect.maxY)) {
                    for x in max(0, columns.lowerBound)..<min(file.width, columns.upperBound) {
                        let at = (y * file.width + x) * 4
                        guard Int(before[at]) + Int(before[at + 1]) + Int(before[at + 2]) < 3 * 110 else { continue }
                        inked += 1
                        if before[at..<at + 4] == after[at..<at + 4] { survived += 1 }
                    }
                }
                XCTAssertGreaterThan(inked, 20, "\(row.label): the line has no ink to look at")
                if row.personal {
                    // The columns of the personal text alone: not one of its ink pixels may be as it was.
                    XCTAssertEqual(survived, 0, "scale \(scale) size \(size) \(row.label): \(survived) of \(inked) ink pixels of the personal text survive the blur")
                } else {
                    XCTAssertEqual(survived, inked, "scale \(scale) size \(size) \(row.label): the plain line was blurred")
                }
            }
        }
    }
}
