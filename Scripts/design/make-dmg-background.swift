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
/// Run: `swift Scripts/design/make-dmg-background.swift out.png`

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
        context.setStrokeColor(gray(0.35, alpha * (long ? 1.0 : 0.5)))
        context.setLineWidth(long ? weight : weight * 0.72)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: centre.x + cos(angle) * (radius - reach),
                                 y: centre.y + sin(angle) * (radius - reach)))
        context.addLine(to: CGPoint(x: centre.x + cos(angle) * radius,
                                    y: centre.y + sin(angle) * radius))
        context.strokePath()
    }
}

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
    context.setStrokeColor(gray(0.28, 0.14 + 0.46 * (t * t)))
    context.setLineWidth(1.1 + 0.9 * t)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: x, y: appSlot.y - half))
    context.addLine(to: CGPoint(x: x, y: appSlot.y + half))
    context.strokePath()
}

guard let image = context.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: width, height: height)      // points, so Finder scales it right
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(Int(width * scale))x\(Int(height * scale)) → \(CommandLine.arguments[1])")
