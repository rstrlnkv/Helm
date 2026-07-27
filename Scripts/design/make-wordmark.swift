import AppKit

/// Candidates for a typographic mark for Helm.
///
/// The app already has a symbol — the ring — so what is missing is the word set
/// in a way that belongs beside it. Every candidate here is drawn from
/// something the app already does rather than from a font somebody liked.
///
/// Run: `swift Scripts/design/make-wordmark.swift out.png`
_ = NSApplication.shared

let cardWidth = 620.0, cardHeight = 150.0
let names = ["plain", "mono", "gauge", "lockup"]

func rounded(_ font: NSFont) -> NSFont {
    guard let d = font.fontDescriptor.withDesign(.rounded) else { return font }
    return NSFont(descriptor: d, size: font.pointSize) ?? font
}

/// The ring, as the icon draws it: an annulus, not a letter O.
func drawRing(in context: CGContext, centre: CGPoint, outer: Double, thickness: Double,
              colour: CGColor) {
    context.setStrokeColor(colour)
    context.setLineWidth(thickness)
    context.strokeEllipse(in: CGRect(x: centre.x - outer + thickness / 2,
                                     y: centre.y - outer + thickness / 2,
                                     width: (outer - thickness / 2) * 2,
                                     height: (outer - thickness / 2) * 2))
}

func draw(_ style: String, in context: CGContext, size: CGSize) {
    let ink = NSColor.black
    let baseline = size.height / 2

    func attributes(_ font: NSFont, _ kern: Double) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: ink, .kern: kern]
    }

    func centred(_ text: String, _ attrs: [NSAttributedString.Key: Any], dx: Double = 0) -> CGRect {
        let string = text as NSString
        let measured = string.size(withAttributes: attrs)
        let origin = CGPoint(x: (size.width - measured.width) / 2 + dx,
                             y: baseline - measured.height / 2)
        string.draw(at: origin, withAttributes: attrs)
        return CGRect(origin: origin, size: measured)
    }

    switch style {
    // What About sets today, for reference: the system face, tightened.
    case "plain":
        _ = centred("Helm", attributes(.systemFont(ofSize: 62, weight: .semibold), -1.2))

    // The face the app already uses for every number it reports. A utility that
    // measures things signing its name in the same type it writes its figures.
    case "mono":
        _ = centred("HELM", attributes(.monospacedSystemFont(ofSize: 46, weight: .medium), 7))

    // The word as an instrument reads it: an index tick above, a scale ruled
    // beneath. Same sixty-tick vocabulary as the bezel, laid flat.
    case "gauge":
        let box = centred("Helm", attributes(.systemFont(ofSize: 58, weight: .medium), 1.5))
        context.setStrokeColor(ink.cgColor)
        context.setLineCap(.round)
        // The index above the H: one long tick, the mark a dial is read
        // against. At two points it was a speck; it carries the top of the
        // lockup, so it is weighted like a stem.
        context.setLineWidth(3)
        context.move(to: CGPoint(x: size.width / 2, y: box.maxY + 9))
        context.addLine(to: CGPoint(x: size.width / 2, y: box.maxY + 27))
        context.strokePath()
        // The scale below, exactly as wide as the word — running past it made
        // the word look like a caption to somebody else's ruler — and ticked at
        // the fifths, the way the bezel is.
        let left = box.minX, right = box.maxX, rule = box.minY - 13
        context.setLineWidth(1)
        context.setStrokeColor(ink.withAlphaComponent(0.30).cgColor)
        context.move(to: CGPoint(x: left, y: rule)); context.addLine(to: CGPoint(x: right, y: rule))
        context.strokePath()
        for step in 0...10 {
            let x = left + (right - left) * Double(step) / 10
            let long = step % 5 == 0
            context.setStrokeColor(ink.withAlphaComponent(long ? 0.60 : 0.30).cgColor)
            context.setLineWidth(long ? 2 : 1.2)
            context.move(to: CGPoint(x: x, y: rule))
            context.addLine(to: CGPoint(x: x, y: rule - (long ? 8 : 4.5)))
            context.strokePath()
        }

    // Symbol and word on one line, which is what a mark has to survive as in a
    // menu bar, a README and a release page.
    case "lockup":
        let font = rounded(.systemFont(ofSize: 54, weight: .semibold))
        let attrs = attributes(font, -0.6)
        let measured = ("Helm" as NSString).size(withAttributes: attrs)
        // The ring is set to the cap height, not to the point size: at the
        // point size it stood a head taller than the H and read as a symbol
        // parked next to a word rather than one mark. Its stroke matches the
        // stem, measured off the font rather than guessed.
        let capHeight = font.capHeight
        let ringOuter = capHeight / 2, gap = 16.0
        let total = ringOuter * 2 + gap + measured.width
        let startX = (size.width - total) / 2
        // The H's stem, measured: the width of "H" less the two counters.
        let stem = ("H" as NSString).size(withAttributes: attrs).width * 0.19
        // `draw(at:)` places the line box's lower left, so the baseline is that
        // plus the descender. Measuring from the line's height instead put the
        // ring low enough to read as a lowercase o.
        let textOrigin = baseline - measured.height / 2
        let textBaseline = textOrigin - font.descender
        drawRing(in: context, centre: CGPoint(x: startX + ringOuter,
                                              y: textBaseline + capHeight / 2),
                 outer: ringOuter, thickness: stem, colour: ink.cgColor)
        ("Helm" as NSString).draw(at: CGPoint(x: startX + ringOuter * 2 + gap, y: textOrigin),
                                  withAttributes: attrs)
    default: break
    }
}

let scale = 2.0
let sheet = NSImage(size: NSSize(width: cardWidth, height: cardHeight * Double(names.count)))
sheet.lockFocus()
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight * Double(names.count)).fill()
let context = NSGraphicsContext.current!.cgContext
for (index, name) in names.enumerated() {
    context.saveGState()
    context.translateBy(x: 0, y: Double(names.count - 1 - index) * cardHeight)
    draw(name, in: context, size: CGSize(width: cardWidth, height: cardHeight))
    (name as NSString).draw(at: NSPoint(x: 12, y: cardHeight - 22),
        withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                         .foregroundColor: NSColor.systemRed])
    context.setStrokeColor(NSColor.black.withAlphaComponent(0.08).cgColor)
    context.setLineWidth(1)
    context.move(to: CGPoint(x: 0, y: 0)); context.addLine(to: CGPoint(x: cardWidth, y: 0))
    context.strokePath()
    context.restoreGState()
}
sheet.unlockFocus()
let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(names.count) candidates → \(CommandLine.arguments[1])")
