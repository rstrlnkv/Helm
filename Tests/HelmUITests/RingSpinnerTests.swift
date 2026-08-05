import XCTest
import AppKit
@testable import HelmUI

/// The spinner is a fixed segment at a rotating angle. These assert the two
/// things a cache depends on: the same phase draws the same image, and
/// different phases do not.
final class RingSpinnerTests: XCTestCase {
    private func png(_ phase: Double) throws -> Data {
        let image = RingIcon.makeSpinner(style: .ring, size: .small,
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
        let still = RingIcon.make(style: .ring, size: .small, tintToken: "green")
        let spinning = RingIcon.makeSpinner(style: .ring, size: .small,
                                             tintToken: "green", phase: 0.3)
        XCTAssertEqual(still.size, spinning.size, "the menu bar would jump")
    }

    /// Thirty-six images, not one per frame at 30 Hz in the menu bar.
    func testFramesAreBuiltOnceAndReused() {
        let first = RingIcon.spinnerFrames(style: .ring, size: .small, tintToken: "green")
        let second = RingIcon.spinnerFrames(style: .ring, size: .small, tintToken: "green")
        XCTAssertEqual(first.count, 36)
        XCTAssertTrue(first[10] === second[10], "the frame cache is not returning the same objects")
    }
    // MARK: - The tint reaches the pixels

    /// Mean colour of the bright pixels — the ring, not the transparent field.
    private func ringColour(_ token: String) throws -> (r: Double, g: Double, b: Double) {
        let image = RingIcon.spinnerFrames(style: .ring, size: .small, tintToken: token)[4]
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var rs = 0.0, gs = 0.0, bs = 0.0, n = 0.0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
                rs += c.redComponent; gs += c.greenComponent; bs += c.blueComponent; n += 1
            }
        }
        XCTAssertGreaterThan(n, 0, "«\(token)» drew nothing")
        return (rs / n * 255, gs / n * 255, bs / n * 255)
    }

    /// The half of the VPN spin that no test reached: a token chosen in Settings
    /// has to arrive in the drawn frames. `VPNStatusAppearanceTests` proves the
    /// firing's kind picks the right token, and this proves the token becomes
    /// that colour — the live check was not available, because the tunnel on the
    /// development machine never comes up and a connect that changed nothing is
    /// deliberately not announced.
    func testTheSpinTintIsTheColourDrawn() throws {
        let cyan = try ringColour("cyan")
        let red = try ringColour("red")

        XCTAssertGreaterThan(cyan.b, cyan.r + 25, "cyan is not blue-dominant: \(cyan)")
        XCTAssertGreaterThan(red.r, red.b + 25, "red is not red-dominant: \(red)")
        XCTAssertGreaterThan(red.r, red.g + 25)
    }

    /// Two tokens must not draw the same picture — the cache is keyed by tint,
    /// and a key that ignored it would serve one colour for both.
    func testTwoTintsAreTwoPictures() throws {
        let a = try XCTUnwrap(RingIcon.spinnerFrames(style: .ring, size: .small,
                                                     tintToken: "cyan")[4].tiffRepresentation)
        let b = try XCTUnwrap(RingIcon.spinnerFrames(style: .ring, size: .small,
                                                     tintToken: "red")[4].tiffRepresentation)
        XCTAssertNotEqual(a, b, "the tint is not reaching the cache key")
    }
}
