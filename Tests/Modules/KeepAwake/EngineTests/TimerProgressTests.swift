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

/// One countdown, wherever it is read.
///
/// There were three: this one, the panel tile's private copy, and the settings
/// page's — which had no hours field at all, so a two-hour session (an offered
/// preset) read "120:00" in the metric strip while the menu bar beside it read
/// "2:00:00". The other two truncated where this one rounds, so the same
/// instant could differ by a second between two surfaces of the same app.
final class OneCountdownTests: XCTestCase {

    func testPastAnHourItSaysHours() {
        XCTAssertEqual(TimerProgress.label(remaining: 120 * 60), "2:00:00")
        XCTAssertEqual(TimerProgress.label(remaining: 61 * 60), "1:01:00")
    }

    func testUnderAnHourItDoesNot() {
        XCTAssertEqual(TimerProgress.label(remaining: 59 * 60 + 59), "59:59")
        XCTAssertEqual(TimerProgress.label(remaining: 90), "1:30")
    }

    /// A countdown does not run past zero, and does not show a negative.
    func testItStopsAtZero() {
        XCTAssertEqual(TimerProgress.label(remaining: 0), "0:00")
        XCTAssertEqual(TimerProgress.label(remaining: -10), "0:00")
    }

    /// The boundary the hours field turns on at, from both sides.
    func testTheHourBoundary() {
        XCTAssertEqual(TimerProgress.label(remaining: 3599), "59:59")
        XCTAssertEqual(TimerProgress.label(remaining: 3600), "1:00:00")
    }

    /// The last layer of the same defect. Every surface calls this with
    /// `end.timeIntervalSinceNow`, and `Int(seconds.rounded())` **traps** on a
    /// `Double` past `Int.max` — so a deadline that got past the engine takes
    /// the menu bar, the panel widget and the settings page with it on the next
    /// redraw, once a second. The engine bounds what it restores; this bounds
    /// what is drawn, because a countdown is not the place to find out.
    func testANumberNoCountdownCouldReachIsNotDrawn() {
        for absurd in [1e300, .infinity, -Double.infinity, Double.nan] {
            XCTAssertFalse(TimerProgress.label(remaining: absurd).isEmpty,
                           "\(absurd) is not a countdown, and it is not a crash either")
        }
    }
}
