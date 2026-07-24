import XCTest
import CoreGraphics
@testable import Module_KeepAwake_Engine

final class JiggleTargetTests: XCTestCase {
    func test_center_of_rect_nudges_right() {
        let p = CGPoint(x: 50, y: 50)
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(JiggleTarget.nudge(from: p, in: bounds), CGPoint(x: 51, y: 50))
    }
    func test_degenerate_bounds_returns_nil() {
        let p = CGPoint(x: 0, y: 0)
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        XCTAssertNil(JiggleTarget.nudge(from: p, in: bounds))
    }
    func test_point_at_right_edge_nudges_left() {
        let p = CGPoint(x: 98, y: 50)
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(JiggleTarget.nudge(from: p, in: bounds), CGPoint(x: 97, y: 50))
    }
}
