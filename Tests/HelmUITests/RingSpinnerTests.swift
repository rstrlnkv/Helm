import XCTest
import AppKit
@testable import HelmUI

/// The spinner is a fixed segment at a rotating angle. These assert the two
/// things a cache depends on: the same phase draws the same image, and
/// different phases do not.
final class RingSpinnerTests: XCTestCase {
    private func png(_ phase: Double) throws -> Data {
        let image = RingIcon.makeSpinner(style: .ring, size: .medium,
                                          tintToken: "green", phase: phase)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testThePhaseChangesThePicture() throws {
        XCTAssertNotEqual(try png(0), try png(0.25), "the segment did not move")
        XCTAssertNotEqual(try png(0.25), try png(0.5))
    }

    func testTheSamePhaseDrawsTheSamePicture() throws {
        XCTAssertEqual(try png(0.4), try png(0.4),
                       "the drawing is not deterministic, so it cannot be cached")
    }

    /// Two revolutions across the window means phase 0.5 is one full turn: the
    /// segment is back where it started.
    func testHalfWayIsAWholeRevolution() throws {
        XCTAssertEqual(try png(0), try png(0.5))
    }

    func testTheIconKeepsItsFootprint() {
        let still = RingIcon.make(style: .ring, size: .medium, tintToken: "green")
        let spinning = RingIcon.makeSpinner(style: .ring, size: .medium,
                                             tintToken: "green", phase: 0.3)
        XCTAssertEqual(still.size, spinning.size, "the menu bar would jump")
    }

    /// Thirty-six images, not one per frame at 30 Hz in the menu bar.
    func testFramesAreBuiltOnceAndReused() {
        let first = RingIcon.spinnerFrames(style: .ring, size: .medium, tintToken: "green")
        let second = RingIcon.spinnerFrames(style: .ring, size: .medium, tintToken: "green")
        XCTAssertEqual(first.count, 36)
        XCTAssertTrue(first[10] === second[10], "the frame cache is not returning the same objects")
    }
}
