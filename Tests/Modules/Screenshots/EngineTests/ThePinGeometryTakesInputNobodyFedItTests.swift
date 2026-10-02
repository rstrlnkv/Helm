import CoreGraphics
import HelmContract
import XCTest
@testable import Module_Screenshots_Engine

/// **Inputs the first geometry file did not feed.** Scroll deltas at the edge of the number line, a scroll
/// that must not make a pin smaller, a rehome that is asked twice, and a chain of scroll events whose
/// every step is clamped on its own.
///
/// Total failure of the subject prints: a scroll up that shrinks a pin (a pin carried to a smaller display and
/// then enlarged), a huge delta that leaves the clamp (infinite or NaN frame), a rehome that moves a pin it has
/// already put on a screen, a chain of events that walks the anchor off the pointer.
final class ThePinGeometryTakesInputNobodyFedItTests: XCTestCase {

    private let native = CGSize(width: 200, height: 100)
    private let display = CGRect(x: 0, y: 0, width: 4000, height: 3000)

    private func isSound(_ frame: CGRect) -> Bool {
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite) && frame.width > 0 && frame.height > 0
    }

    /// Both ends of the finite range, both kinds of wheel: the answer is a frame inside the bounds, never infinite.
    func testAHugeFiniteDeltaStaysInsideTheBounds() throws {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        for precise in [false, true] {
            for delta in [CGFloat.greatestFiniteMagnitude, -CGFloat.greatestFiniteMagnitude, 1e30, -1e30, 1e6, -1e6] {
                let next = try XCTUnwrap(PinGeometry.scaled(frame: frame, native: native, delta: delta, precise: precise,
                                                            about: CGPoint(x: 150, y: 150), display: display),
                                         "delta \(delta) was refused although it is a number")
                XCTAssertTrue(isSound(next), "delta \(delta) precise \(precise) made \(next)")
                XCTAssertLessThanOrEqual(next.width, 4000 + 0.001, "delta \(delta) went past the display")
                XCTAssertGreaterThanOrEqual(min(next.width, next.height), PinGeometry.minimumSide - 0.001, "delta \(delta) went under the floor")
            }
        }
    }

    /// A pin carried onto a display smaller than it is: a scroll *up* must not make it smaller.
    func testAScrollUpNeverShrinksAPin() throws {
        let big = CGSize(width: 3000, height: 1500)
        let small = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 0, y: 0, width: 3000, height: 1500)
        let next = try XCTUnwrap(PinGeometry.scaled(frame: frame, native: big, delta: 1, precise: true,
                                                    about: CGPoint(x: 100, y: 100), display: small))
        XCTAssertGreaterThanOrEqual(next.width, frame.width, "a scroll up shrank the pin from \(frame.width) to \(next.width)")
        let down = try XCTUnwrap(PinGeometry.scaled(frame: frame, native: big, delta: -1, precise: true,
                                                    about: CGPoint(x: 100, y: 100), display: small))
        XCTAssertLessThanOrEqual(down.width, frame.width, "a scroll down enlarged the pin")
    }

    /// Eight thousand alternating events: the scale returns to where it began, the point under the pointer stays.
    func testALongChainOfScrollsDoesNotDrift() throws {
        var frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        let about = CGPoint(x: 180, y: 130)
        let start = frame
        let wheel = [CGFloat(3), -3, 7, -7, 1, -1, 40, -40]
        for round in 0..<1000 {
            for delta in wheel {
                frame = try XCTUnwrap(PinGeometry.scaled(frame: frame, native: native, delta: delta, precise: round % 2 == 0,
                                                         about: about, display: display))
            }
        }
        XCTAssertEqual(frame.width, start.width, accuracy: 0.01, "the scale drifted over a chain of balanced scrolls")
        XCTAssertEqual(frame.minX, start.minX, accuracy: 0.05, "the anchor drifted")
        XCTAssertEqual(frame.minY, start.minY, accuracy: 0.05, "the anchor drifted")
        XCTAssertEqual(frame.width / frame.height, 2, accuracy: 1e-9)
    }

    /// A rehome is a fixed point: what it returned is wholly on the screen it chose, so asking again changes nothing.
    func testRehomeTwiceIsRehomeOnce() {
        let screens: [(id: DisplayID, frame: CGRect)] = [(DisplayID(1), CGRect(x: 0, y: 0, width: 1000, height: 800)),
                                                          (DisplayID(2), CGRect(x: 1000, y: 0, width: 600, height: 400))]
        for frame in [CGRect(x: 900, y: 50, width: 200, height: 100), CGRect(x: 1500, y: 300, width: 200, height: 100),
                      CGRect(x: -50, y: -50, width: 3000, height: 1500), CGRect(x: 5000, y: 5000, width: 200, height: 100)] {
            let once = PinGeometry.rehome(frame: frame, native: native, screens: screens)
            let twice = PinGeometry.rehome(frame: once, native: native, screens: screens)
            XCTAssertEqual(once, twice, "rehome of \(frame) is not a fixed point")
            XCTAssertTrue(screens.contains { $0.frame.contains(once) }, "rehome of \(frame) left it on no screen: \(once)")
        }
    }

    /// A frame the board never made: a zero-size or non-finite frame is left, not turned into a window.
    func testAFrameThatIsNotAFrameIsLeftAlone() {
        let screens: [(id: DisplayID, frame: CGRect)] = [(DisplayID(1), display)]
        let nan = CGFloat.nan
        let bad: [CGRect] = [CGRect.zero, CGRect(x: 0, y: 0, width: nan, height: 10), CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10)]
        for frame in bad {
            let out = PinGeometry.rehome(frame: frame, native: native, screens: screens)
            if frame.width.isNaN { XCTAssertTrue(out.width.isNaN, "\(frame) became \(out)") } else { XCTAssertEqual(out.width, frame.width, "\(frame) became \(out)") }
        }
        XCTAssertNil(PinGeometry.scaled(frame: .zero, native: native, delta: 1, precise: true, about: .zero, display: display))
        XCTAssertNil(PinGeometry.scaled(frame: CGRect(x: 0, y: 0, width: 10, height: 10), native: .zero, delta: 1,
                                        precise: true, about: .zero, display: display))
    }
}
