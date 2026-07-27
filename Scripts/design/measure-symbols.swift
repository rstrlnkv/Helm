import AppKit

/// How much of its own square each SF Symbol actually paints.
///
/// A symbol is drawn at a point size, but the ink inside that size is the
/// designer's business: `keyboard` fills its box nearly edge to edge, while
/// `moon.zzz.fill` leaves a wide margin. Setting one point size for every
/// symbol therefore sets a different *visual* size for each one, which is why
/// some tiles in the sidebar looked crowded and others looked empty.
///
/// This renders each symbol and measures the ink, so the ratios in `SymbolInk`
/// can be derived rather than guessed.
///
/// Read these as *relative* numbers only. `NSImage.SymbolConfiguration` and
/// SwiftUI's `.font(.system(size:))` do not agree on what a point size means —
/// SwiftUI sizes a symbol against the font's metrics and paints about 1.34× as
/// much ink — so the absolute fraction of a tile has to be read off a real
/// render (`Scripts/design/shoot.sh`, then measure the pixels). What survives
/// the difference is the ratio between one symbol and another, which is what
/// the table is for.
let symbols = [
    "gearshape", "info.circle", "moon.zzz.fill", "lock.shield", "trash",
    "chart.pie", "doc.on.doc", "wand.and.rays", "keyboard", "shippingbox",
]
let point: CGFloat = 100

func inkBox(_ name: String) -> CGRect? {
    let config = NSImage.SymbolConfiguration(pointSize: point, weight: .semibold)
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return nil }
    let size = image.size
    let box = NSRect(origin: .zero, size: NSSize(width: ceil(size.width) + 40,
                                                 height: ceil(size.height) + 40))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(box.width), pixelsHigh: Int(box.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.black.setFill()
    image.draw(at: NSPoint(x: 20, y: 20), from: NSRect.zero,
               operation: NSCompositingOperation.sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

print("symbol                 ink w×h at \(Int(point)) pt      widest side / point size")
var ratios: [(String, CGFloat)] = []
for name in symbols {
    guard let box = inkBox(name) else { print("  \(name): MISSING"); continue }
    let widest = max(box.width, box.height)
    ratios.append((name, widest / point))
    print(String(format: "  %-16s %6.1f × %-6.1f            %.3f",
                 (name as NSString).utf8String!, box.width, box.height, widest / point))
}
let mean = ratios.map(\.1).reduce(0, +) / CGFloat(ratios.count)
print(String(format: "\nmean %.3f — the size to normalise towards", mean))
print("\nper-symbol correction to hit the mean:")
for (name, ratio) in ratios.sorted(by: { $0.1 > $1.1 }) {
    print(String(format: "  %-16s ×%.3f", (name as NSString).utf8String!, mean / ratio))
}
