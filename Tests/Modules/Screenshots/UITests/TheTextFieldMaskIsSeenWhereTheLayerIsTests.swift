import AppKit
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The mask is looked at, not only measured:** the geometry test of the field's mask trusts that a mask's frame is laid in
/// the flipped field's own top-down points. This one draws the field, filled red, in a superview and reads the pixels: red
/// stands exactly where the area is, at all four edges, and nowhere outside it. Also the three inputs the geometry test did
/// not feed: a field wider than the area, a field wholly outside it, an area smaller than the field in both axes.
///
/// What it would print if it failed totally: a mask that hides everything leaves no red inside and fails the "inside" count of
/// every case; a mask that is missing leaves red outside the area.
@MainActor
final class TheTextFieldMaskIsSeenWhereTheLayerIsTests: XCTestCase {
    private let size = CGSize(width: 400, height: 300)

    private func render(anchor: CGPoint, area: CGRect, text: String = "") throws -> (inside: Int, insideRed: Int, outsideRed: Int) {
        let superview = NSView(frame: CGRect(origin: .zero, size: size))
        let window = NSWindow(contentRect: superview.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = superview
        let field = OverlayTextField()
        var style = AnnotationStyle.standard
        style.thickness = .thick
        field.restyle(style)
        field.drawsBackground = true
        field.backgroundColor = .red
        field.clip = area
        superview.addSubview(field)
        field.start(at: anchor)
        if !text.isEmpty { field.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0)) }
        superview.wantsLayer = true
        superview.displayIfNeeded()
        let rep = try XCTUnwrap(superview.bitmapImageRepForCachingDisplay(in: superview.bounds))
        superview.cacheDisplay(in: superview.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / size.width
        var inside = 0, insideRed = 0, outsideRed = 0
        var y = field.frame.minY + 3.25
        while y < field.frame.maxY - 3 {
            var x = field.frame.minX + 3.25
            while x < field.frame.maxX - 3 {
                let color = rep.colorAt(x: Int(x * scale), y: Int((size.height - y) * scale))?.usingColorSpace(.sRGB)
                let red = (color?.redComponent ?? 0) > 0.8 && (color?.greenComponent ?? 1) < 0.3 && (color?.alphaComponent ?? 0) > 0.8
                let held = area.contains(CGPoint(x: x, y: y))
                if held { inside += 1; if red { insideRed += 1 } } else if red { outsideRed += 1 }
                x += 2
            }
            y += 2
        }
        return (inside, insideRed, outsideRed)
    }

    private func check(_ name: String, anchor: CGPoint, area: CGRect, expectInside: Bool = true, file: StaticString = #filePath, line: UInt = #line) throws {
        // The instrument first: with the whole superview as the area the field is not cut, and every sample of it must show red.
        let whole = try render(anchor: anchor, area: CGRect(origin: .zero, size: size))
        XCTAssertGreaterThan(whole.inside, 20, "\(name): the field is not inside the superview", file: file, line: line)
        XCTAssertEqual(whole.insideRed, whole.inside, "\(name): the reading sees red in \(whole.insideRed) of \(whole.inside) uncut samples: the instrument is blind", file: file, line: line)
        let seen = try render(anchor: anchor, area: area)
        XCTAssertEqual(seen.outsideRed, 0, "\(name): red shows outside the area", file: file, line: line)
        if expectInside {
            XCTAssertGreaterThan(seen.inside, 20, "\(name): the case has nothing inside the area", file: file, line: line)
            XCTAssertEqual(seen.insideRed, seen.inside, "\(name): the area holds \(seen.inside) samples of the field and \(seen.insideRed) show", file: file, line: line)
        } else {
            XCTAssertEqual(seen.inside, 0, "\(name): the case is not wholly outside", file: file, line: line)
        }
    }

    func testRedStandsWhereTheAreaIsAtEveryEdge() throws {
        let area = CGRect(x: 100, y: 100, width: 200, height: 100)
        try check("bottom", anchor: CGPoint(x: 150, y: area.minY + 15), area: area)
        try check("top", anchor: CGPoint(x: 150, y: area.maxY + 10), area: area)
        try check("left", anchor: CGPoint(x: area.minX - 10, y: 150), area: area)
        try check("right", anchor: CGPoint(x: area.maxX - 10, y: 150), area: area)
    }

    func testAFieldWiderThanTheAreaAndOneWhollyOutsideAndAnAreaSmallerThanTheFieldInBothAxes() throws {
        let narrow = CGRect(x: 150, y: 100, width: 40, height: 100)
        let line = String(repeating: "W", count: 30)
        let wide = try render(anchor: CGPoint(x: 100, y: 150), area: narrow, text: line)
        XCTAssertEqual(wide.outsideRed, 0, "wider than the area: red outside")
        XCTAssertGreaterThan(wide.inside, 20)
        XCTAssertGreaterThan(wide.insideRed * 2, wide.inside, "wider than the area: the area shows less than half of the field (the glyphs are the rest)")
        try check("outside", anchor: CGPoint(x: 350, y: 50), area: CGRect(x: 100, y: 100, width: 200, height: 100), expectInside: false)
        try check("smaller in both axes", anchor: CGPoint(x: 100, y: 150), area: CGRect(x: 110, y: 142, width: 12, height: 8))
    }
}
