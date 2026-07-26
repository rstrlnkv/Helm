import AppKit
import XCTest
import Module_Layout_Engine
@testable import Module_Layout_UI

/// Temporary: dumps a contact sheet for visual inspection when asked.
final class FlagSheetDump: XCTestCase {
    func testDumpSheet() throws {
        guard let out = ProcessInfo.processInfo.environment["HELM_FLAG_SHEET"] else {
            throw XCTSkip("set HELM_FLAG_SHEET to dump")
        }
        let regions = FlagArt.drawnRegions
        let cell = CGSize(width: 64, height: 44)
        let cols = 10
        let rows = (regions.count + cols - 1) / cols
        let sheet = NSImage(size: NSSize(width: CGFloat(cols) * cell.width,
                                         height: CGFloat(rows) * cell.height))
        sheet.lockFocus()
        NSColor(white: 0.12, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.white]
        for (i, region) in regions.enumerated() {
            let col = i % cols, row = i / cols
            let ox = CGFloat(col) * cell.width
            let oy = sheet.size.height - CGFloat(row + 1) * cell.height
            let img = BadgeImage.drawn(FlagArt.flag(region: region)!, points: 15, scale: 2)
            img.draw(in: NSRect(x: ox + (cell.width - img.size.width) / 2, y: oy + 16,
                                width: img.size.width, height: img.size.height))
            (region as NSString).draw(at: NSPoint(x: ox + 26, y: oy + 3), withAttributes: attrs)
        }
        sheet.unlockFocus()
        let tiff = sheet.tiffRepresentation!
        let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: out))
    }
}
