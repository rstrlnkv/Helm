import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **An emoji is one grapheme, and the file draws it in its own colours.** «👍🏽» (a skin tone joined to a base) and «🇫🇷» (two regional
/// indicators that make one flag) are put on a grey picture through the editor's entry, in a green ink, and exported; inside the layer's frame
/// the file's own bytes are read: pixels of a saturation well above grey's, several distinct colours, no one colour holding most of the
/// ink (a box in the ink's green, or a red one, is one colour), and for the flag blue and red both, which no foreground colour paints. The 24 of the
/// grid are held to the same, and to being one grapheme each, and the entry takes exactly what is one: a joined family, a flag, a skin tone and
/// a heart with its selector, and nothing of the empty string, two letters, two thumbs, a zero-width character alone and a selector alone.
/// The opacity is the group's: half of it is the half of every pixel's difference from the picture, and the screen's tile is the file's pixels.
///
/// What it would print if it failed totally: an emoji drawn nowhere leaves the file equal to the picture (the changed count is zero); a grey
/// silhouette leaves no saturated pixel; the export that forgets the emoji tool fills its frame with the ink and leaves one colour.
final class TheEmojiIsOneGraphemeAndDrawsInColourTests: XCTestCase {
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private let area = CGRect(x: 0, y: 0, width: 200, height: 120)
    private let ink = AnnotationStyle(color: .green, thickness: .medium)

    private func picture(scale: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(200 * scale), height: Int(120 * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200 * scale, height: 120 * scale))
        return try XCTUnwrap(context.makeImage())
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let raw = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: raw, count: image.width * image.height * 4))
    }

    private struct Seen {
        let layer: Annotation
        let file: [UInt8]
        let was: [UInt8]
        let scale: CGFloat
        /// Inside the layer's frame: the pixels that differ from the picture, the saturated ones among them, the distinct colours (sixteen
        /// levels a channel), the share of the commonest one, and whether blue and red ones are both there.
        var changed = 0, saturated = 0, distinct = 0, share = 0.0, blue = 0, red = 0
    }

    private func seen(_ emoji: String, scale: CGFloat, style: AnnotationStyle? = nil, at point: CGPoint = CGPoint(x: 100, y: 60)) throws -> Seen {
        var editing = AnnotationEditing(bounds: area)
        XCTAssertTrue(editing.place(emoji: emoji, at: point, style: style ?? ink), "\(emoji) was refused")
        let layer = try XCTUnwrap(editing.layers.first, emoji)
        let ground = try picture(scale: scale)
        let file = try bytes(try XCTUnwrap(CaptureSession.draw([layer], over: ground, at: .zero, scale: scale, display: ground)))
        var made = Seen(layer: layer, file: file, was: try bytes(ground), scale: scale)
        let width = ground.width
        let box = layer.frame.insetBy(dx: -2, dy: -2).intersection(area)
        var buckets: [Int: Int] = [:]
        for y in Int(box.minY * scale)..<Int(box.maxY * scale) {
            for x in Int(box.minX * scale)..<Int(box.maxX * scale) {
                let at = (y * width + x) * 4
                let (r, g, b) = (Int(file[at]), Int(file[at + 1]), Int(file[at + 2]))
                guard (0..<3).contains(where: { abs(Int(file[at + $0]) - Int(made.was[at + $0])) > 2 }) else { continue }
                made.changed += 1
                buckets[(r / 16) << 8 | (g / 16) << 4 | b / 16, default: 0] += 1
                let top = max(r, g, b), bottom = min(r, g, b)
                if top > 0, Double(top - bottom) / Double(top) > 0.35 { made.saturated += 1 }
                if b > r + 50, b > g + 20 { made.blue += 1 }
                if r > b + 80, r > g + 80 { made.red += 1 }
            }
        }
        made.distinct = buckets.count
        made.share = Double(buckets.values.max() ?? 0) / Double(max(made.changed, 1))
        return made
    }

    // MARK: Colour in the file

    func testTheSkinToneAndTheFlagDrawInColourInTheFile() throws {
        for scale in [CGFloat(1), 2] {
            let pixels = Int(scale * scale)
            for emoji in ["👍🏽", "🇫🇷"] {
                let made = try seen(emoji, scale: scale)
                let name = "\(Int(scale))x \(emoji)"
                XCTAssertGreaterThan(made.changed, 200 * pixels, "\(name): the file shows no emoji (\(made.changed) pixels changed)")
                XCTAssertGreaterThan(made.saturated, 150 * pixels, "\(name): grey: \(made.saturated) of \(made.changed) pixels are saturated")
                XCTAssertGreaterThan(made.distinct, 6, "\(name): \(made.distinct) distinct colours")
                XCTAssertLessThan(made.share, 0.5, "\(name): one colour holds \(Int(made.share * 100)) % of the ink: a box and no picture")
            }
            let flag = try seen("🇫🇷", scale: scale)
            XCTAssertGreaterThan(flag.blue, 40 * pixels, "\(Int(scale))x: the flag has no blue in the file (\(flag.blue))")
            XCTAssertGreaterThan(flag.red, 40 * pixels, "\(Int(scale))x: the flag has no red in the file (\(flag.red))")
        }
    }

    func testTheInkIsNotTheEmojisColour() throws {
        // The same emoji in two inks is the same pixels: the colour is the emoji's own.
        let green = try seen("👍🏽", scale: 1, style: AnnotationStyle(color: .green, thickness: .medium))
        let purple = try seen("👍🏽", scale: 1, style: AnnotationStyle(color: .purple, thickness: .medium))
        XCTAssertEqual(green.file, purple.file, "the ink changed an emoji's pixels")
    }

    func testEveryEmojiOfTheGridIsOneGraphemeAndDrawsInColour() throws {
        XCTAssertEqual(EmojiSet.all.count, 24)
        XCTAssertEqual(Set(EmojiSet.all).count, EmojiSet.all.count, "an emoji stands in the grid twice")
        XCTAssertEqual(EmojiSet.all.count % EmojiSet.perRow, 0, "the last row of the grid is not full")
        for emoji in EmojiSet.all {
            XCTAssertTrue(EmojiSet.isOne(emoji), "\(emoji) is not one emoji by the grid's own test")
            let made = try seen(emoji, scale: 1)
            XCTAssertGreaterThan(made.changed, 100, "\(emoji): the file shows nothing")
            XCTAssertGreaterThan(made.distinct, 3, "\(emoji): \(made.distinct) distinct colours: a silhouette")
            XCTAssertLessThan(made.share, 0.85, "\(emoji): one colour holds \(Int(made.share * 100)) % of the ink")
            XCTAssertGreaterThan(made.saturated, 0, "\(emoji): no saturated pixel at all")
        }
    }

    // MARK: One grapheme

    func testTheEntryTakesExactlyOneGrapheme() {
        let accepted = ["👍", "👍🏽", "🇫🇷", "👨‍👩‍👧‍👦", "❤️", "⚠️", "1️⃣", "🏳️‍🌈"]
        let refused: [(String, String)] = [
            ("", "the empty string"), ("ab", "two letters"), ("👍👍", "two thumbs"), ("👍🏽👍🏽", "two skin tones"), ("🇫🇷🇫🇷", "two flags"),
            ("\u{200B}", "a zero-width space"), ("\u{200D}", "a joiner"), ("\u{FE0F}", "a variation selector"), ("\u{FE0F}\u{FE0F}", "two selectors"),
            (" ", "a space"), ("\n", "a break"), ("\t", "a tab"), ("👍 ", "a thumb and a space"), ("\u{200B}👍", "a thumb after a zero-width space"),
            (String(repeating: "👍", count: 300), "three hundred thumbs"),
            ("e" + String(repeating: "\u{0301}", count: 40), "one letter with forty accents"),
        ]
        for text in accepted {
            var editing = AnnotationEditing(bounds: area)
            XCTAssertTrue(EmojiSet.isOne(text), "\(text) is one emoji")
            XCTAssertTrue(editing.place(emoji: text, at: CGPoint(x: 100, y: 60)), "\(text) was refused")
            XCTAssertEqual(editing.layers.count, 1, text)
            XCTAssertEqual(editing.layers.first?.text, text, "\(text) was changed on its way in")
            XCTAssertTrue(editing.canUndo, text)
            editing.undo()
            XCTAssertTrue(editing.layers.isEmpty, "\(text): one undo step does not take it away")
            XCTAssertFalse(editing.canUndo, "\(text): more than one step")
        }
        for (text, what) in refused {
            var editing = AnnotationEditing(bounds: area)
            XCTAssertFalse(EmojiSet.isOne(text), "\(what) is one emoji")
            XCTAssertFalse(editing.place(emoji: text, at: CGPoint(x: 100, y: 60)), "\(what) was taken")
            XCTAssertTrue(editing.layers.isEmpty, "\(what) left a layer")
            XCTAssertFalse(editing.canUndo, "\(what) left a step")
        }
    }

    func testAJoinedFamilyIsOneLayerOfOneFramesSize() throws {
        let family = try seen("👨‍👩‍👧‍👦", scale: 1)
        let thumb = try seen("👍", scale: 1)
        XCTAssertGreaterThan(family.saturated, 100, "the family is grey")
        // A joined family is one glyph of the line, so one emoji's room: not four people side by side.
        XCTAssertLessThan(family.layer.frame.width, thumb.layer.frame.width * 1.5, "\(family.layer.frame) against \(thumb.layer.frame)")
    }

    // MARK: Opacity is the group's

    func testHalfOpacityIsHalfOfEveryPixelsDifferenceFromThePicture() throws {
        for scale in [CGFloat(1), 2] {
            for emoji in ["👍🏽", "🇫🇷", "👨‍👩‍👧‍👦"] {
                let full = try seen(emoji, scale: scale, style: AnnotationStyle(color: .green, thickness: .medium, opacity: 1))
                for opacity in [0.5, 0.1] {
                    let part = try seen(emoji, scale: scale, style: AnnotationStyle(color: .green, thickness: .medium, opacity: opacity))
                    XCTAssertGreaterThan(part.changed, 0, "\(emoji) at \(opacity): nothing drawn")
                    var worst = 0
                    for index in 0..<(full.file.count / 4) {
                        for channel in 0..<3 {
                            let was = Double(full.was[index * 4 + channel]), whole = Double(full.file[index * 4 + channel])
                            let expected = was + (whole - was) * opacity
                            worst = max(worst, Int(abs(Double(part.file[index * 4 + channel]) - expected).rounded()))
                        }
                    }
                    XCTAssertLessThanOrEqual(worst, 4, "\(Int(scale))x \(emoji) at \(opacity): a pixel is \(worst) off a linear fade of the full emoji")
                }
            }
        }
    }

    // MARK: Screen and file

    func testTheScreensTileAndTheFilesPixelsAreTheSame() throws {
        for scale in [CGFloat(1), 2] {
            for emoji in ["👍🏽", "🇫🇷", "❤️", "👨‍👩‍👧‍👦"] {
                let made = try seen(emoji, scale: scale, style: AnnotationStyle(color: .blue, thickness: .thick, opacity: 0.85),
                                    at: CGPoint(x: 80.3, y: 50.6))
                let ground = try picture(scale: scale)
                let tile = try XCTUnwrap(AnnotationText.tile(of: made.layer, scale: scale), emoji)
                let context = try XCTUnwrap(CGContext(data: nil, width: ground.width, height: ground.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(ground, in: CGRect(x: 0, y: 0, width: ground.width, height: ground.height))
                context.draw(tile.image, in: CGRect(x: tile.pixels.minX, y: CGFloat(ground.height) - tile.pixels.maxY,
                                                    width: tile.pixels.width, height: tile.pixels.height))
                let screen = try bytes(try XCTUnwrap(context.makeImage()))
                var off = 0, worst = 0
                for (a, b) in zip(screen, made.file) { worst = max(worst, abs(Int(a) - Int(b))); if abs(Int(a) - Int(b)) > 2 { off += 1 } }
                XCTAssertEqual(off, 0, "\(Int(scale))x \(emoji): \(off) bytes differ between the screen's tile and the file, the worst by \(worst)")
                XCTAssertGreaterThan(made.changed, 100, "\(Int(scale))x \(emoji): the file shows nothing")
            }
        }
    }
}
