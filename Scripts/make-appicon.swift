import AppKit

// Renders the Helm app icon (dark squircle + white ring) into an .iconset dir.
// Usage: swift Scripts/make-appicon.swift <output.iconset dir>

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let f = CGFloat(px)

    // Squircle background with a subtle vertical gradient.
    let pad = f * 0.075
    let rect = NSRect(x: pad, y: pad, width: f - 2 * pad, height: f - 2 * pad)
    let bg = NSBezierPath(roundedRect: rect, xRadius: f * 0.225, yRadius: f * 0.225)
    let grad = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.22, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 1),
    ])!
    grad.draw(in: bg, angle: -90)

    // Centered white ring.
    let inset = f * 0.30
    let ringRect = NSRect(x: inset, y: inset, width: f - 2 * inset, height: f - 2 * inset)
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = max(1, f * 0.055)
    NSColor.white.setStroke()
    ring.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments[1]
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in specs {
    try! render(px).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("iconset written to \(outDir)")
