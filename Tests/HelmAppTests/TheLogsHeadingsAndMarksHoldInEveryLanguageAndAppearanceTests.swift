import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// Whether a warning row still says it is one with the bar gone, in both
/// appearances, read off the drawn row and not off the declaration the page
/// draws it from.
@MainActor
final class TheLogsHeadingsAndMarksHoldInEveryLanguageAndAppearanceTests: XCTestCase {

    // MARK: - The level without the bar

    /// **With the bar gone the glyph is what says «warning» to anyone who cannot
    /// tell the wash from the card**, so it has to stand off the wash it sits on
    /// as a mark does — 3:1 — in both appearances. Read off a drawn row on the
    /// card it sits on in the page (`HelmSurface.cardFill` over the window's
    /// background): the glyph's most saturated pixel against the wash in the
    /// row's own left padding.
    func testTheLevelGlyphStandsOffItsWashInBothAppearances() throws {
        var faint: [String] = []
        for appearance in RenderedInk.bothAppearances {
            for level in [LogLevel.warn, .error] {
                let entry = LogEntry(date: Date(timeIntervalSince1970: 1_790_000_000), level: level,
                                     category: "layout", message: "no accessibility grant — not watching")
                let view = LogRowView(row: LogPresentation.Row(lines: [entry], heading: nil))
                    .background(HelmSurface.cardFill)
                    .background(Color(nsColor: .windowBackgroundColor))
                let mount = MountedRender(view, width: 600, height: 24, appearance: appearance)
                defer { mount.drop() }
                mount.settle(10)
                let host = mount.host
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let data = try XCTUnwrap(rep.bitmapData)
                let scale = max(1, rep.pixelsWide / max(1, Int(host.bounds.width)))
                func color(_ x: Int, _ y: Int) -> NSColor {
                    let at = y * rep.bytesPerRow + x * 4
                    return NSColor(srgbRed: CGFloat(data[at]) / 255, green: CGFloat(data[at + 1]) / 255,
                                   blue: CGFloat(data[at + 2]) / 255, alpha: 1)
                }
                let wash = color(6 * scale, rep.pixelsHigh / 2)
                var glyph = wash
                var saturation: CGFloat = 0
                for y in 0..<rep.pixelsHigh {
                    for x in 0..<min(rep.pixelsWide, 160 * scale) {
                        let c = color(x, y)
                        let s = max(c.redComponent, c.greenComponent, c.blueComponent)
                            - min(c.redComponent, c.greenComponent, c.blueComponent)
                        if s > saturation { saturation = s; glyph = c }
                    }
                }
                // The subject: a glyph in a colour was drawn at all.
                XCTAssertGreaterThan(saturation, 0.3, "\(level) in \(RenderedInk.label(of: appearance)): no glyph drawn")
                let ratio = Contrast.ratio(glyph, wash)
                print("glyph against wash: \(level) in \(RenderedInk.label(of: appearance)) "
                      + String(format: "%.2f:1", ratio))
                if ratio < Contrast.markFloor {
                    faint.append("\(level) in \(RenderedInk.label(of: appearance)): \(String(format: "%.2f", ratio)):1")
                }
            }
        }
        XCTAssertTrue(faint.isEmpty, "the level glyph does not stand off its wash as a mark must — "
                      + faint.joined(separator: "; "))
    }
}
