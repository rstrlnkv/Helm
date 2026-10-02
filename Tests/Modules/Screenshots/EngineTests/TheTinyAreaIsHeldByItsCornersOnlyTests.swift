import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **What an area too small for eight dots offers.** Under three points the screen draws no dot,
/// and above it four corner dots; the press offers the same four corners and not a middle the person
/// cannot see, and still takes a corner within the reach where no dot is drawn.
final class TheTinyAreaIsHeldByItsCornersOnlyTests: XCTestCase {

    func testUnderThreeDotDiametersOnlyTheCornersAreOffered() {
        let tiny = CGRect(x: 100, y: 100, width: 26, height: 26)
        XCTAssertEqual(AreaFrame.offered(on: tiny).map(\.handle), [.topLeft, .topRight, .bottomRight, .bottomLeft])
        XCTAssertNil(AreaFrame.handle(of: tiny, at: CGPoint(x: 113, y: 100)), "an unseen top middle was taken")
        XCTAssertNil(AreaFrame.handle(of: tiny, at: CGPoint(x: 126, y: 113)), "an unseen right middle was taken")
        XCTAssertEqual(AreaFrame.handle(of: tiny, at: CGPoint(x: 126, y: 100)), .topRight, "a corner was lost")
    }

    func testAtThreeDotDiametersAndOverAllEightAreOffered() {
        let rect = CGRect(x: 100, y: 100, width: 27, height: 27)
        XCTAssertEqual(AreaFrame.offered(on: rect).count, 8)
        XCTAssertEqual(AreaFrame.handle(of: rect, at: CGPoint(x: 113.5, y: 100)), .top)
        // The shorter side decides: a wide, low area is tiny too.
        XCTAssertEqual(AreaFrame.offered(on: CGRect(x: 0, y: 0, width: 500, height: 20)).count, 4)
    }
}
