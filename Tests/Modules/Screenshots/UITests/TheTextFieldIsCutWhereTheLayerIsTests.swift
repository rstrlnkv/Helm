import AppKit
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The field is cut by the area at all four edges, on the side the layer is cut.** The field is a flipped view in an
/// unflipped superview, and its clip mask is laid in the field's own (top-down) points. The check is geometry, not
/// pixels: a grid of points of the field's own space is taken to the superview by AppKit's own conversion, and the mask
/// must hold exactly those that the area holds. A field of the 22 pt step is put 15 pt inside each edge, so it stands
/// across that edge.
///
/// What it would print if it failed totally: a mask that is missing makes `field.layer?.mask` nil and the first
/// assertion of every edge fails by name; a mask on the wrong side holds the points the area does not.
@MainActor
final class TheTextFieldIsCutWhereTheLayerIsTests: XCTestCase {
    private let area = CGRect(x: 100, y: 100, width: 200, height: 100)

    private func field(at anchor: CGPoint, in superview: NSView) -> OverlayTextField {
        let field = OverlayTextField()
        var style = AnnotationStyle.standard
        style.thickness = .thick
        field.restyle(style)
        field.clip = area
        field.start(at: anchor)
        superview.addSubview(field)
        return field
    }

    func testTheMaskHoldsWhatTheAreaHoldsAtEveryEdge() throws {
        let superview = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        // The line's top-left, in the superview's bottom-left points: each puts the field across one edge.
        let anchors: [(String, CGPoint)] = [
            ("bottom", CGPoint(x: 150, y: area.minY + 15)),
            ("top", CGPoint(x: 150, y: area.maxY + 10)),
            ("left", CGPoint(x: area.minX - 10, y: 150)),
            ("right", CGPoint(x: area.maxX - 10, y: 150)),
        ]
        for (edge, anchor) in anchors {
            let field = field(at: anchor, in: superview)
            defer { field.removeFromSuperview() }
            let mask = try XCTUnwrap(field.layer?.mask, "\(edge): the field has no clip mask")
            var inside = 0, outside = 0
            var y = field.bounds.minY + 0.37
            while y < field.bounds.maxY {
                var x = field.bounds.minX + 0.37
                while x < field.bounds.maxX {
                    let point = CGPoint(x: x, y: y)
                    let held = area.contains(field.convert(point, to: superview))
                    if held { inside += 1 } else { outside += 1 }
                    XCTAssertEqual(mask.frame.contains(point), held,
                                   "\(edge): the point \(point) of the field is \(held ? "inside" : "outside") the area, the mask says otherwise")
                    x += 3
                }
                y += 3
            }
            XCTAssertGreaterThan(inside, 0, "\(edge): the field has nothing inside the area, the case is not across the edge")
            XCTAssertGreaterThan(outside, 0, "\(edge): the field is wholly inside the area, the case is not across the edge")
        }
    }
}
