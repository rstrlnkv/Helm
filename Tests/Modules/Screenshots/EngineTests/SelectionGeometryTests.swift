import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// The rules of dragging a selection, as functions of the pointer and the
/// modifiers. Each modifier is tested in both states, because a rule proven from
/// one side only is unproven from the other.
final class SelectionGeometryTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    private func drag(from start: CGPoint, to end: CGPoint, shift: Bool = false, option: Bool = false) -> SelectionDrag {
        var drag = SelectionDrag(start: start, bounds: bounds)
        drag.move(to: end, shift: shift, option: option, space: false)
        return drag
    }

    func testADragIsTheRectangleBetweenTwoPointsInAnyDirection() {
        let forward = drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 250))
        let backward = drag(from: CGPoint(x: 300, y: 250), to: CGPoint(x: 100, y: 100))
        XCTAssertEqual(forward.rect, CGRect(x: 100, y: 100, width: 200, height: 150))
        XCTAssertEqual(backward.rect, forward.rect)
    }

    func testTheSelectionNeverLeavesTheDisplay() {
        let out = drag(from: CGPoint(x: 900, y: 500), to: CGPoint(x: 5000, y: -400))
        XCTAssertEqual(out.rect, CGRect(x: 900, y: 0, width: 100, height: 500))
    }

    func testAClickThatNeverMovedIsNotASelection() {
        XCTAssertFalse(drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10)).isUsable)
        XCTAssertFalse(drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10.5, y: 400)).isUsable, "a sliver is not a selection")
        XCTAssertTrue(drag(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 11, y: 11)).isUsable)
    }

    func testOptionGrowsTheSelectionFromItsCentreAndReleasingItGoesBack() {
        var drag = SelectionDrag(start: CGPoint(x: 500, y: 300), bounds: bounds)
        drag.move(to: CGPoint(x: 600, y: 340), shift: false, option: true, space: false)
        XCTAssertEqual(drag.rect, CGRect(x: 400, y: 260, width: 200, height: 80))
        drag.move(to: CGPoint(x: 600, y: 340), shift: false, option: false, space: false)
        XCTAssertEqual(drag.rect, CGRect(x: 500, y: 300, width: 100, height: 40))
    }

    func testShiftFreezesTheAxisThatMovedLessAndReleasingItGivesItBack() {
        var drag = SelectionDrag(start: CGPoint(x: 100, y: 100), bounds: bounds)
        drag.move(to: CGPoint(x: 300, y: 140), shift: false, option: false, space: false)
        // Shift goes down while the drag is wider than it is tall: the height is frozen at 40.
        drag.move(to: CGPoint(x: 400, y: 500), shift: true, option: false, space: false)
        XCTAssertEqual(drag.rect.height, 40, "the short axis moved with the pointer while shift was held")
        XCTAssertEqual(drag.rect.width, 300)
        drag.move(to: CGPoint(x: 450, y: 520), shift: true, option: false, space: false)
        XCTAssertEqual(drag.rect.height, 40)
        XCTAssertEqual(drag.rect.width, 350)
        drag.move(to: CGPoint(x: 450, y: 520), shift: false, option: false, space: false)
        XCTAssertEqual(drag.rect.height, 420, "releasing shift did not give the axis back")
    }

    func testShiftOnATallDragFreezesTheWidth() {
        var drag = SelectionDrag(start: CGPoint(x: 100, y: 100), bounds: bounds)
        drag.move(to: CGPoint(x: 130, y: 400), shift: false, option: false, space: false)
        drag.move(to: CGPoint(x: 600, y: 500), shift: true, option: false, space: false)
        XCTAssertEqual(drag.rect.width, 30)
        XCTAssertEqual(drag.rect.height, 400)
    }

    func testSpaceCarriesTheSelectionAndKeepsItsSize() {
        var drag = SelectionDrag(start: CGPoint(x: 100, y: 100), bounds: bounds)
        drag.move(to: CGPoint(x: 200, y: 160), shift: false, option: false, space: false)
        XCTAssertEqual(drag.rect, CGRect(x: 100, y: 100, width: 100, height: 60))
        drag.move(to: CGPoint(x: 260, y: 200), shift: false, option: false, space: true)
        XCTAssertEqual(drag.rect, CGRect(x: 160, y: 140, width: 100, height: 60))
        // Space released: the pointer goes on resizing from the moved anchor.
        drag.move(to: CGPoint(x: 300, y: 220), shift: false, option: false, space: false)
        XCTAssertEqual(drag.rect, CGRect(x: 160, y: 140, width: 140, height: 80))
    }

    func testASelectionCarriedIntoAWallStopsAtTheWallWithoutShrinking() {
        var drag = SelectionDrag(start: CGPoint(x: 800, y: 100), bounds: bounds)
        drag.move(to: CGPoint(x: 900, y: 200), shift: false, option: false, space: false)
        drag.move(to: CGPoint(x: 990, y: 200), shift: false, option: false, space: true)
        drag.move(to: CGPoint(x: 1000, y: 200), shift: false, option: false, space: true)
        XCTAssertEqual(drag.rect.size, CGSize(width: 100, height: 100), "the wall squeezed the selection")
        XCTAssertEqual(drag.rect.maxX, 1000)
    }

    func testAPointThatIsNotANumberIsNotASelection() {
        var drag = SelectionDrag(start: CGPoint(x: 100, y: 100), bounds: bounds)
        drag.move(to: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), shift: false, option: false, space: false)
        XCTAssertTrue(drag.rect.width.isFinite && drag.rect.height.isFinite)
        XCTAssertFalse(drag.rect.isNull)
    }

    func testEnterWithNothingSelectedIsTheWholeDisplay() {
        XCTAssertEqual(Selection.wholeDisplay(bounds), bounds)
    }

    func testTheSizeIsInPixelsAndNotPoints() {
        XCTAssertEqual(Selection.pixelSize(of: CGRect(x: 0, y: 0, width: 100.4, height: 50), scale: 2).width, 201)
        XCTAssertEqual(Selection.pixelSize(of: CGRect(x: 0, y: 0, width: 100, height: 50), scale: 2).height, 100)
        XCTAssertEqual(Selection.pixelSize(of: CGRect(x: 0, y: 0, width: 100, height: 50), scale: .nan).width, 0)
    }
}
