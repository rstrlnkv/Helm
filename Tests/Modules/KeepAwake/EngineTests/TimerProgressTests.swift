import XCTest
@testable import Module_KeepAwake_Engine

final class TimerProgressTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000)
    let end = Date(timeIntervalSince1970: 1_100)   // 100s session

    func testFullAtStartEmptyAtEnd() {
        XCTAssertEqual(TimerProgress.remainingFraction(now: start, start: start, end: end), 1, accuracy: 0.001)
        XCTAssertEqual(TimerProgress.remainingFraction(now: end, start: start, end: end), 0, accuracy: 0.001)
    }

    func testHalfway() {
        let mid = Date(timeIntervalSince1970: 1_050)
        XCTAssertEqual(TimerProgress.remainingFraction(now: mid, start: start, end: end), 0.5, accuracy: 0.001)
    }

    func testClampsOutsideTheWindow() {
        let before = Date(timeIntervalSince1970: 900), after = Date(timeIntervalSince1970: 1_200)
        XCTAssertEqual(TimerProgress.remainingFraction(now: before, start: start, end: end), 1, accuracy: 0.001)
        XCTAssertEqual(TimerProgress.remainingFraction(now: after, start: start, end: end), 0, accuracy: 0.001)
    }

    func testLabelFormatsBelowAndAboveAnHour() {
        XCTAssertEqual(TimerProgress.label(remaining: 545), "9:05")
        XCTAssertEqual(TimerProgress.label(remaining: 3849), "1:04:09")
        XCTAssertEqual(TimerProgress.label(remaining: 0), "0:00")
        XCTAssertEqual(TimerProgress.label(remaining: -5), "0:00")
    }

    func testZeroLengthSessionIsFinished() {
        XCTAssertEqual(TimerProgress.remainingFraction(now: start, start: start, end: start), 0, accuracy: 0.001)
    }
}
