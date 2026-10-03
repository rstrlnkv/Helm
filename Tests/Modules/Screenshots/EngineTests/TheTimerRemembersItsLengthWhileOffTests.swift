import Foundation
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

/// `timer` is the seconds the next shot waits and 0 is off; it was never re-keyed. The length the timer cell switches on
/// with is its own key, `timerLength`, so that switching the timer off does not forget what it was. A store from before
/// that key holds only `timer`, and **only a missing key says so**.
final class TheTimerRemembersItsLengthWhileOffTests: XCTestCase {

    private typealias Key = ScreenshotsSettings.Key

    private func read(_ values: [String: Any] = [:]) -> ScreenshotsSettings {
        let backing = InMemoryKeyValueStore()
        for (key, value) in values { backing.set(value, forKey: "module.screenshots.\(key)") }
        return ScreenshotsSettings.read(NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing))
    }

    func testANewStoreHasNoTimerAndAFiveSecondLength() {
        let settings = read()
        XCTAssertEqual(settings.timer, .none)
        XCTAssertEqual(settings.timerLength, .five)
    }

    func testTheLengthSurvivesTheTimerBeingOff() {
        for length in CaptureTimer.allCases where length != .none {
            let settings = read([Key.timer: 0, Key.timerLength: length.rawValue])
            XCTAssertEqual(settings.timer, .none, "\(length)")
            XCTAssertEqual(settings.timerLength, length, "the timer is off and the length was lost: \(length)")
        }
    }

    func testTheLengthIsItsOwnWhileTheTimerIsOnAndDiffers() {
        let settings = read([Key.timer: 5, Key.timerLength: 30])
        XCTAssertEqual(settings.timer, .five)
        XCTAssertEqual(settings.timerLength, .thirty)
    }

    func testAStoreFromBeforeTheLengthTakesTheTimersNumberAndOtherwiseFive() {
        for (timer, length) in [(10, CaptureTimer.ten), (5, .five), (30, .thirty), (0, .five), (7, .five), (60, .five)] {
            let settings = read([Key.timer: timer])
            XCTAssertEqual(settings.timerLength, length, "a timer of \(timer) and no length")
        }
    }

    func testOnlyAMissingKeyIsAMigration() {
        // The length is there and is not one: the timer's number is not asked.
        for damaged: Any in [0, 7, -1, "10", "", 1e300, Double.nan, Int.max, Data([10]), [10]] {
            let settings = read([Key.timer: 10, Key.timerLength: damaged])
            XCTAssertEqual(settings.timerLength, .five, "a damaged length \(damaged) was read as the timer's ten")
        }
    }

    func testThirtyIsACaseAndKeepsItsSeconds() {
        XCTAssertEqual(CaptureTimer.thirty.seconds, 30)
        XCTAssertEqual(CaptureTimer(rawValue: 30), .thirty)
        XCTAssertEqual(CaptureTimer.allCases.map(\.seconds), [0, 5, 10, 30])
    }
}
