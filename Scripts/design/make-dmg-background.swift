import AppKit

/// Draws the background of the disk image window.
///
/// The window is the first thing anybody sees of Helm, before the app has run
/// once, so it is drawn in the app's own vocabulary rather than in the usual
/// disk-image idiom of a big arrow on a photograph.
///
/// That vocabulary is the bezel: sixty ticks, every fifth one longer, which is
/// what turns behind the mark on the About page and what the menu bar icon is a
/// small copy of. Here it does two jobs. Around the left slot it frames the app
/// the way the About page frames it. Between the slots it becomes the arrow —
/// a run of the same ticks, rising in weight towards the destination. A drawn
/// arrow would have been a second visual language on a 640 pt window.
///
/// No words. The disk image is one file for eight languages, and Finder writes
/// the two labels — "Helm" and "Applications" — in the reader's own.
///
/// Run: `swift Scripts/design/make-dmg-background.swift out.png [style] [--dev]`
/// where style is `bezel` (what ships), `field` or `sweep`.

let arguments = CommandLine.arguments
let outputPath = arguments[1]
let style = arguments.dropFirst(2).first { !$0.hasPrefix("--") } ?? "bezel"
/// Dev images say so on their face. A screenshot of a dev window turns up in an
/// issue sooner or later, and it must not be mistaken for a release.
let isDev = arguments.contains("--dev")

// 380 rather than 400: at 400 the composition sat in the top two thirds with a
// band of nothing under it, because the icons and their labels only occupy the
// middle.
let width = 640.0, height = 380.0, scale = 2.0

// Where the two icons sit. Finder is told the same numbers by make-dmg.sh, so
// they live here as the single statement of the layout.
// Icons are drawn 128 pt square centred on these, with Finder's label below —
// so anything drawn here has to clear a box roughly 128 wide and 170 tall.
let appSlot = CGPoint(x: 168, y: 178)
let dropSlot = CGPoint(x: 472, y: 178)
/// Half of the 128 pt Finder draws each icon at.
let iconHalf = 64.0
/// Named because the chevron is placed against it, not beside it.
let bezelRadius = 126.0

guard let context = CGContext(data: nil,
                              width: Int(width * scale), height: Int(height * scale),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("no context") }
context.scaleBy(x: scale, y: scale)
// Core Graphics is bottom-up; the slot coordinates above read from the top,
// the way Finder states them.
context.translateBy(x: 0, y: height)
context.scaleBy(x: 1, y: -1)

func gray(_ value: Double, _ alpha: Double = 1) -> CGColor {
    CGColor(srgbRed: value, green: value, blue: value, alpha: alpha)
}

/// The ink. Dev takes the blue of its own badge in About, so the two say the
/// same thing in the same colour; the release image stays neutral.
/// The system blue the DEV badge is tinted with, so the two match rather than
/// merely rhyme.
let tint = CGColor(srgbRed: 0.0, green: 0.478, blue: 1.0, alpha: 1)

extension NSFont {
    /// `.system(size:weight:design: .rounded)` has no AppKit spelling.
    func rounded() -> NSFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

/// Grey whichever channel this is. Dev used to tint the whole drawing blue as
/// well as adding the badge, which made the two builds look like two different
/// products rather than one product at two stages. The badge says it, and the
/// badge is enough.
func ink(_ alpha: Double) -> CGColor { gray(0.32, alpha) }

// A near-white that is not white: on a white desktop the window would have no
// edge, and the black app icon needs something to sit on that is not paper.
let backdrop = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [gray(0.976), gray(0.941)] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(backdrop, start: CGPoint(x: 0, y: height),
                           end: CGPoint(x: 0, y: 0), options: [])

/// The bezel: sixty ticks, every fifth one longer, as `HelmBezel` draws it.
func bezel(around centre: CGPoint, radius: Double, length: Double,
           weight: Double, alpha: Double) {
    for tick in 0..<60 {
        let long = tick % 5 == 0
        let reach = long ? length : length * 0.57
        let angle = Double(tick) / 60 * 2 * .pi
        context.setStrokeColor(ink(alpha * (long ? 1.0 : 0.5)))
        context.setLineWidth(long ? weight : weight * 0.72)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: centre.x + cos(angle) * (radius - reach),
                                 y: centre.y + sin(angle) * (radius - reach)))
        context.addLine(to: CGPoint(x: centre.x + cos(angle) * radius,
                                    y: centre.y + sin(angle) * radius))
        context.strokePath()
    }
}

/// Everything below draws in points from the top left, the way the slots read.

// MARK: - bezel — the About page's frame, and the ticks unrolled into an arrow

func drawBezelStyle() {
    // Around the app: the same frame the About page puts the mark in, closed all
    // the way round, and the only ring in the window.
    //
    // Radius 126, from 82 by way of 105. At 82 the ring cut through the word
    // "Helm" that Finder writes under the icon; 105 cleared it but only just, so
    // the ring was opened at the bottom to make room. Standing further off, it
    // clears the name on its own: the label sits about 72 pt below the
    // centre, where the ring is 103 pt out to either side and the word
    // reaches about 13. The gap was no longer paying for anything.
    bezel(around: appSlot, radius: bezelRadius, length: 11, weight: 1.5, alpha: 0.75)

    // The run between them: the bezel unrolled into a straight line, rising in
    // weight towards the destination. This is the arrow.
    // A chevron and nothing else. The run of growing ticks that used to lead up
    // to it was the bezel's vocabulary applied where it did not belong: a row
    // of marks reads as a scale, and a scale between two icons is a measurement
    // rather than an instruction.
    //
    // Centred in the corridor it actually sits in — from the ring's outer edge
    // to the folder's left edge — rather than between the two slot centres.
    // Those are the same thing only while the ring is small: at radius 126 the
    // midpoint between the centres falls 25 pt inside the ring's half of the
    // gap, and the chevron sat visibly closer to the app than to the folder.
    let reach = 15.0, spread = 14.0
    let corridor = (appSlot.x + bezelRadius + (dropSlot.x - iconHalf)) / 2
    let tip = CGPoint(x: corridor + reach / 2, y: appSlot.y)
    context.setStrokeColor(ink(0.55))
    context.setLineWidth(3)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: tip.x - reach, y: tip.y - spread))
    context.addLine(to: tip)
    context.addLine(to: CGPoint(x: tip.x - reach, y: tip.y + spread))
    context.strokePath()
}

// MARK: - field — squared paper, because measuring is what the app does

/// Helm measures things, so the window is the paper they get measured on: a
/// faint grid, the two slots standing on it as stations, and a ruled scale
/// between them that reads as a distance rather than an arrow. Quieter than the
/// bezel, and more literal about the subject.
func drawFieldStyle() {
    /// The paper stops before the window does. A grid ruled hard into all four
    /// edges reads as a screenshot of something larger that got cropped.
    func fade(_ position: Double, _ extent: Double) -> Double {
        let margin = 56.0
        return min(1, min(position, extent - position) / margin)
    }

    let step = 20.0
    context.setLineWidth(0.5)
    var x = step
    while x < width {
        context.setStrokeColor(ink(fade(x, width) * (x.truncatingRemainder(dividingBy: 100) < 0.5 ? 0.13 : 0.05)))
        context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: height))
        context.strokePath()
        x += step
    }
    var y = step
    while y < height {
        context.setStrokeColor(ink(fade(y, height) * (y.truncatingRemainder(dividingBy: 100) < 0.5 ? 0.13 : 0.05)))
        context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: width, y: y))
        context.strokePath()
        y += step
    }

    // The stations are cleared of the grid, so the icons are not read through it.
    for slot in [appSlot, dropSlot] {
        let clear = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                               colors: [gray(0.965, 1.0), gray(0.965, 0.0)] as CFArray,
                               locations: [0.30, 1])!
        context.drawRadialGradient(clear, startCenter: slot, startRadius: 0,
                                   endCenter: slot, endRadius: 145, options: [])
    }

    let y0 = appSlot.y, left = appSlot.x + 104, right = dropSlot.x - 104
    context.setStrokeColor(ink(0.40))
    context.setLineWidth(1)
    context.setLineCap(.butt)
    context.move(to: CGPoint(x: left, y: y0)); context.addLine(to: CGPoint(x: right, y: y0))
    context.strokePath()
    for end in [left, right] {
        context.move(to: CGPoint(x: end, y: y0 - 6)); context.addLine(to: CGPoint(x: end, y: y0 + 6))
        context.strokePath()
    }
    for tick in 1..<8 {
        let x = left + (right - left) * Double(tick) / 8
        context.setStrokeColor(ink(0.24))
        context.move(to: CGPoint(x: x, y: y0 - 3)); context.addLine(to: CGPoint(x: x, y: y0 + 3))
        context.strokePath()
    }
}

// MARK: - sweep — one wedge of the ring, opened out across the window

/// The other thing Helm draws all day is a wedge of the sunburst. Here one
/// opens from the app towards Applications — a single gesture instead of a
/// frame plus a dotted line — with the bezel's ticks riding its outer edge.
func drawSweepStyle() {
    let centre = appSlot
    let inner = 96.0, outer = 214.0
    let from = -0.26, to = 0.26

    context.saveGState()
    let wedge = CGMutablePath()
    wedge.addArc(center: centre, radius: outer, startAngle: from, endAngle: to, clockwise: false)
    wedge.addArc(center: centre, radius: inner, startAngle: to, endAngle: from, clockwise: true)
    wedge.closeSubpath()
    context.addPath(wedge)
    context.clip()
    let fill = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [ink(0.02), ink(0.11)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(fill, start: CGPoint(x: centre.x + inner, y: 0),
                               end: CGPoint(x: centre.x + outer, y: 0), options: [])
    context.restoreGState()

    // Ticks along the two edges of the wedge rather than a comb across its
    // mouth: the comb read as teeth and closed off the very opening the wedge
    // exists to make.
    for edge in [from, to] {
        for step in stride(from: 0.0, through: 1.0, by: 1.0 / 7) {
            let radius = inner + (outer - inner) * step
            let long = Int(step * 7 + 0.5) % 2 == 0
            let reach = long ? 7.0 : 4.0
            let outward = CGPoint(x: cos(edge + (edge < 0 ? -0.02 : 0.02)),
                                  y: sin(edge + (edge < 0 ? -0.02 : 0.02)))
            context.setStrokeColor(ink(long ? 0.34 : 0.20))
            context.setLineWidth(long ? 1.4 : 1)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: centre.x + cos(edge) * radius,
                                     y: centre.y + sin(edge) * radius))
            context.addLine(to: CGPoint(x: centre.x + cos(edge) * radius + outward.x * reach,
                                        y: centre.y + sin(edge) * radius + outward.y * reach))
            context.strokePath()
        }
    }

    let socket = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                            colors: [gray(0.87, 0.8), gray(0.87, 0.0)] as CFArray,
                            locations: [0.55, 1])!
    context.drawRadialGradient(socket, startCenter: dropSlot, startRadius: 0,
                               endCenter: dropSlot, endRadius: 116, options: [])
}

switch style {
case "field": drawFieldStyle()
case "sweep": drawSweepStyle()
default: drawBezelStyle()
}

/// The dev mark, drawn the way `HelmBadge`'s prominent emphasis draws it — the
/// same capsule that sits beside the wordmark in About, so the disk image and
/// the app say it in one voice. The first version was monospaced text in a flat
/// pill, which said the same word in a different accent.
///
/// Kept in step by hand, because a Swift script cannot import HelmUI: rounded
/// bold at 9 with 0.5 of tracking, 6 by 2.5 of padding, a fill that lightens by
/// 5% towards the top, a hairline of the light along the upper edge, and a
/// shadow of the tint rather than a neutral one.
if isDev {
    let text = "DEV" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9, weight: .bold).rounded(),
        .foregroundColor: NSColor.white,
        .kern: 0.5,
    ]
    let textSize = text.size(withAttributes: attrs)
    let pad = CGSize(width: 6, height: 2.5)
    let box = CGRect(x: width - textSize.width - pad.width * 2 - 26,
                     y: height - textSize.height - pad.height * 2 - 24,
                     width: textSize.width + pad.width * 2,
                     height: textSize.height + pad.height * 2)
    let capsule = CGPath(roundedRect: box, cornerWidth: box.height / 2,
                         cornerHeight: box.height / 2, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -1), blur: 2,
                      color: tint.copy(alpha: 0.35))
    context.addPath(capsule)
    context.setFillColor(tint)
    context.fillPath()
    context.restoreGState()

    // The gradient, inside the capsule.
    context.saveGState()
    context.addPath(capsule)
    context.clip()
    let fill = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [tint.copy(alpha: 0.95)!, tint] as CFArray,
                          locations: [0, 1])!
    context.drawLinearGradient(fill, start: CGPoint(x: 0, y: box.maxY),
                               end: CGPoint(x: 0, y: box.minY), options: [])
    // A hairline of the light source along the top edge, fading by the middle.
    context.addPath(capsule)
    context.clip()
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [CGColor(gray: 1, alpha: 0.45),
                                    CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    context.saveGState()
    context.addPath(CGPath(roundedRect: box.insetBy(dx: 0.35, dy: 0.35),
                           cornerWidth: box.height / 2, cornerHeight: box.height / 2,
                           transform: nil))
    context.setLineWidth(0.7)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(sheen, start: CGPoint(x: 0, y: box.maxY),
                               end: CGPoint(x: 0, y: box.midY), options: [])
    context.restoreGState()
    context.restoreGState()

    context.saveGState()
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    text.draw(at: CGPoint(x: box.minX + pad.width, y: height - box.maxY + pad.height),
              withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    context.restoreGState()
}

guard let image = context.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: width, height: height)      // points, so Finder scales it right
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(style)\(isDev ? " dev" : "") → \(outputPath)")
