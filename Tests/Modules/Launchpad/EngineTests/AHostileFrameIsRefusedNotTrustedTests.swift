import XCTest
@testable import Module_Launchpad_Engine

/// The frames come out of a private layout Apple does not document, so whatever the memory holds reaches `TouchFrame`: a count that
/// is no count, a position that is no number, a state the system does not have. Each is refused, and a wild count reads no record.
final class AHostileFrameIsRefusedNotTrustedTests: XCTestCase {
    private func frame(count: Int = 1, time: Double = 1, device: Int = 0, x: Double = 0.5, y: Double = 0.5, state: Int = 4) -> TouchFrame? {
        TouchFrame(device: device, time: time, count: count) { _ in (x, y, state) }
    }

    func testAnOrdinaryFrameIsTakenSoTheRefusalsBelowAreTheCheck() {
        XCTAssertEqual(frame()?.down.count, 1)
        XCTAssertEqual(frame(count: 10)?.touches.count, 10)
        XCTAssertEqual(frame(count: 0)?.touches.count, 0)
    }

    func testAPositionThatIsNoNumberOrOutsideThePadIsRefused() {
        for bad in [Double.nan, .infinity, -.infinity, 1.2, -0.2, 1e300, -1e300] {
            XCTAssertNil(frame(x: bad), "x \(bad)")
            XCTAssertNil(frame(y: bad), "y \(bad)")
        }
    }

    func testACountOutsideZeroToTenIsRefusedBeforeAnyRecordIsRead() {
        for count in [-1, 11, 1000, Int.max, Int.min] {
            var asked = 0
            let read = TouchFrame(device: 0, time: 1, count: count) { _ in asked += 1; return (0.5, 0.5, 4) }
            XCTAssertNil(read, "count \(count)")
            XCTAssertEqual(asked, 0, "count \(count) read a record")
        }
    }

    func testAStateTheSystemDoesNotHaveAndATimeThatIsNoNumberAreRefused() {
        XCTAssertNil(frame(state: 8))
        XCTAssertNil(frame(state: -1))
        XCTAssertNil(frame(state: Int(Int32.max)))
        XCTAssertNil(frame(time: .nan))
        XCTAssertNil(frame(time: .infinity))
        XCTAssertNil(frame(device: -1))
        XCTAssertNil(frame(device: TouchFrame.maxDevices))
    }

    /// Total failure of the layout: every frame is refused, and the watch stands down at the limit, once.
    func testAPadThatSendsOnlyRefusedFramesStandsTheWatchDownOnceAtTheLimit() {
        var trust = FrameTrust()
        var reached = 0
        for _ in 0..<(FrameTrust.limit * 3) where trust.note(accepted: frame(x: .nan) != nil) { reached += 1 }
        XCTAssertEqual(reached, 1)
    }

    func testAGoodFrameClearsTheRunSoNoiseDoesNotStandItDown() {
        var trust = FrameTrust()
        for _ in 0..<5 {
            for _ in 0..<(FrameTrust.limit - 1) { XCTAssertFalse(trust.note(accepted: false)) }
            XCTAssertFalse(trust.note(accepted: true))
        }
    }

    func testAHostileHandNeverFiresARecognizer() {
        var recognizer = PinchRecognizer()
        let frames = Hand.landing() + [frame(count: 11), frame(x: .nan), frame(count: -3)].compactMap { $0 }
        XCTAssertEqual(frames.count, Hand.landing().count)
        XCTAssertTrue(frames.compactMap { recognizer.feed($0) }.isEmpty)
    }
}
