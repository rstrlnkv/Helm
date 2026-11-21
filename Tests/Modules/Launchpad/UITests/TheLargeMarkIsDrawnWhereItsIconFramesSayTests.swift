import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
@testable import Module_Launchpad_UI

/// A click on a mini icon is read from `LaunchpadFolderMark.frame(ofIcon:size:)`; the drawing must put the icons there. Nine
/// icons of nine plain colours are drawn and the middle of each frame is read back.
@MainActor final class TheLargeMarkIsDrawnWhereItsIconFramesSayTests: XCTestCase {
    private let colours: [NSColor] = [.red, .green, .blue, .yellow, .cyan, .magenta, .black, NSColor(white: 0.5, alpha: 1), NSColor(white: 0.25, alpha: 1)]

    private func image(_ c: NSColor) -> NSImage {
        let i = NSImage(size: NSSize(width: 16, height: 16))
        i.lockFocus(); c.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill(); i.unlockFocus()
        return i
    }

    private func render(_ mark: LaunchpadFolderMark, side: CGFloat) throws -> NSBitmapImageRep {
        let m = MountedRender(mark.frame(width: side, height: side), width: side, height: side, appearance: .aqua)
        m.settle()
        let rep = try XCTUnwrap(m.host.bitmapImageRepForCachingDisplay(in: m.host.bounds))
        m.host.cacheDisplay(in: m.host.bounds, to: rep)
        return rep
    }

    private func pixel(_ rep: NSBitmapImageRep, _ p: CGPoint, side: CGFloat) -> NSColor? {
        let k = CGFloat(rep.pixelsWide) / side
        return rep.colorAt(x: Int(p.x * k), y: Int(p.y * k))?.usingColorSpace(.sRGB)
    }

    private func distance(_ a: NSColor?, _ b: NSColor) -> CGFloat {
        guard let a = a?.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return 9 }
        return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
    }

    /// What each colour of `palette` reads back as when it fills the whole mark's cell 0: a render's colour space is not the one the colours were made in.
    private func calibrated(_ palette: [NSColor], side: CGFloat) throws -> [NSColor?] {
        try palette.map { c in
            let rep = try render(LaunchpadFolderMark(icons: [image(c)], size: side), side: side)
            let f = LaunchpadFolderMark.frame(ofIcon: 0, size: side)
            return pixel(rep, CGPoint(x: f.midX, y: f.midY), side: side)
        }
    }

    private func nearest(_ a: NSColor?, in reference: [NSColor?]) -> Int? {
        reference.indices.min { distance(a, reference[$0] ?? .clear) < distance(a, reference[$1] ?? .clear) }
    }

    private func near(_ a: NSColor?, _ b: NSColor?) -> Bool { b.map { distance(a, $0) < 0.1 } ?? false }

    func testEachIconIsDrawnInTheFrameThatNamesIt() throws {
        for side in [120.0, 200.0, 301.0] {
            let rep = try render(LaunchpadFolderMark(icons: colours.map(image), size: side), side: side)
            var hits = 0
            let reference = try calibrated(colours, side: side)
            for (i, c) in colours.enumerated() {
                let f = LaunchpadFolderMark.frame(ofIcon: i, size: side)
                let got = pixel(rep, CGPoint(x: f.midX, y: f.midY), side: side)
                XCTAssertEqual(nearest(got, in: reference), i, "size \(side), icon \(i): \(String(describing: got)) is not \(c)")
                hits += nearest(got, in: reference) == i && near(got, reference[i]) ? 1 : 0
                // The frame's corners are the icon, and a step outside any side of it is not.
                for (x, y) in [(f.minX + 2, f.minY + 2), (f.maxX - 2, f.minY + 2), (f.minX + 2, f.maxY - 2), (f.maxX - 2, f.maxY - 2)] {
                    XCTAssertTrue(near(pixel(rep, CGPoint(x: x, y: y), side: side), reference[i]), "size \(side), icon \(i): the corner \(x),\(y) is not the icon")
                }
                for (x, y) in [(f.minX - 2, f.midY), (f.maxX + 2, f.midY), (f.midX, f.minY - 2), (f.midX, f.maxY + 2)] {
                    XCTAssertFalse(near(pixel(rep, CGPoint(x: x, y: y), side: side), reference[i]), "size \(side), icon \(i): the icon spills out of its frame at \(x),\(y)")
                }
            }
            XCTAssertEqual(hits, 9, "subject: nine icons were read back")
        }
    }

    func testPastNineTheNinthCellHoldsTheTinyIconsAndNotAnAppFrame() throws {
        let side = 240.0
        let tiny = [NSColor.red, .green, .blue, .yellow]
        let reference = try calibrated(tiny, side: side)
        let rep = try render(LaunchpadFolderMark(icons: colours.prefix(8).map(image), size: side, overflow: tiny.map(image)), side: side)
        let cell = LaunchpadFolderMark.frame(ofIcon: 8, size: side)
        let inset = cell.width * 0.10, between = cell.width * 0.06, t = (cell.width - 2 * inset - between) / 2
        for i in tiny.indices {
            let p = CGPoint(x: cell.minX + inset + CGFloat(i % 2) * (t + between) + t / 2, y: cell.minY + inset + CGFloat(i / 2) * (t + between) + t / 2)
            XCTAssertEqual(nearest(pixel(rep, p, side: side), in: reference), i, "tiny icon \(i)")
            XCTAssertTrue(near(pixel(rep, p, side: side), reference[i]), "tiny icon \(i) is its colour")
        }
    }
}
