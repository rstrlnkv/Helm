import AppKit
import CoreGraphics
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The angle's plate sits in the middle of the strip whatever the strip's length.** `RulerLayer` builds the plate when
/// the text changes and the strip when the length does; an area of another width brings a strip of another length at the
/// same "0°", and a plate left where it was is off the middle.
///
/// What it would print if it failed totally: a plate rebuilt on the text alone stays at the first strip's middle, and the
/// second assertion reads the longer strip's middle where the shorter one's is wanted.
@MainActor
final class TheRulersAnglePlateStaysInTheMiddleOfTheStripTests: XCTestCase {

    private func plateMiddle(of layer: RulerLayer) throws -> CGFloat {
        let strip = try XCTUnwrap(layer.sublayers?.first)
        let plate = try XCTUnwrap(strip.sublayers?.compactMap { $0 as? CAShapeLayer }.last)
        return try XCTUnwrap(plate.path).boundingBox.midX
    }

    func testANewLengthAtTheSameAngleMovesThePlateToTheNewMiddle() throws {
        let layer = RulerLayer()
        let wide = CGRect(x: 0, y: 0, width: 600, height: 400), narrow = CGRect(x: 0, y: 0, width: 200, height: 400)
        let first = Ruler.centred(in: wide), second = Ruler.centred(in: narrow)
        XCTAssertNotEqual(first.length, second.length, "the fixture gave both areas one length")
        layer.show(first, in: wide, height: 400, scale: 2)
        XCTAssertEqual(try plateMiddle(of: layer), first.length / 2, accuracy: 0.5)
        layer.show(second, in: narrow, height: 400, scale: 2)
        XCTAssertEqual(try plateMiddle(of: layer), second.length / 2, accuracy: 0.5, "the plate stayed where the longer strip had it")
    }
}
