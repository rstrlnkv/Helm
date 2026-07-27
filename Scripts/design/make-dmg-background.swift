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
/// where style is `bezel` (default), `field` or `sweep`.

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
func ink(_ alpha: Double) -> CGColor {
    isDev ? CGColor(srgbRed: 0.00, green: 0.38, blue: 0.85, alpha: alpha * 0.85)
          : gray(0.32, alpha)
}

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
    // The destination: a socket rather than a mark. A hard-edged disc came out
    // smaller than the folder standing on it and read as a stray circle behind an
    // icon, so it fades out instead of ending — no edge to be the wrong size.
    let socket = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                            colors: [gray(0.87, 0.85), gray(0.87, 0.0)] as CFArray,
                            locations: [0.55, 1])!
    context.drawRadialGradient(socket, startCenter: dropSlot, startRadius: 0,
                               endCenter: dropSlot, endRadius: 118, options: [])

    // Around the app: the same frame the About page puts the mark in, and the only
    // ring in the window. Radius 105 rather than the 82 it started at — at 82 the
    // ring cut straight through the word "Helm" that Finder writes under the icon.
    bezel(around: appSlot, radius: 105, length: 10, weight: 1.5, alpha: 0.75)

    // The run between them: the bezel unrolled into a straight line, rising in
    // weight towards the destination. This is the arrow.
    let runStart = appSlot.x + 122, runEnd = dropSlot.x - 104
    let steps = 8
    for step in 0...steps {
        let t = Double(step) / Double(steps)
        let x = runStart + (runEnd - runStart) * t
        // Growing as it goes, in height as well as weight: a tick that is longer
        // than the one behind it points without being an arrowhead.
        let half = (5.0 + 7.0 * t) / 2
        context.setStrokeColor(ink(0.14 + 0.46 * (t * t)))
        context.setLineWidth(1.1 + 0.9 * t)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: x, y: appSlot.y - half))
        context.addLine(to: CGPoint(x: x, y: appSlot.y + half))
        context.strokePath()
    }

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

/// The dev mark: the capsule About puts beside the wordmark, in the same blue,
/// so a dev image and a dev About page say it the same way.
if isDev {
    let text = "DEV" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
        .foregroundColor: NSColor.white,
        .kern: 1.4,
    ]
    let textSize = text.size(withAttributes: attrs)
    let pad = CGSize(width: 12, height: 5)
    let box = CGRect(x: width - textSize.width - pad.width * 2 - 24,
                     y: height - textSize.height - pad.height * 2 - 22,
                     width: textSize.width + pad.width * 2,
                     height: textSize.height + pad.height * 2)
    context.setFillColor(CGColor(srgbRed: 0.00, green: 0.38, blue: 0.85, alpha: 1))
    context.addPath(CGPath(roundedRect: box, cornerWidth: box.height / 2,
                           cornerHeight: box.height / 2, transform: nil))
    context.fillPath()

    context.saveGState()
    // Undo the flip applied at the top so the letters read the right way up.
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
