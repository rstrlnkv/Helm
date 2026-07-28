import XCTest
@testable import Module_Layout_Engine

/// The page says "today". Before this the engine counted from launch.
final class DailyCountTests: XCTestCase {

    /// Fixed to UTC so the fixtures mean the same day wherever this runs —
    /// `Calendar(identifier:)` takes the machine's zone, which moved every
    /// timestamp below across midnight.
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func at(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    func testItCountsWithinTheDay() {
        var count = DailyCount()
        XCTAssertEqual(count.add(on: at("2026-07-28T09:00:00Z"), calendar: calendar), 1)
        XCTAssertEqual(count.add(on: at("2026-07-28T23:59:00Z"), calendar: calendar), 2)
    }

    func testItStartsAgainOnTheNextDay() {
        var count = DailyCount()
        _ = count.add(on: at("2026-07-28T23:59:00Z"), calendar: calendar)
        _ = count.add(on: at("2026-07-28T23:59:30Z"), calendar: calendar)
        XCTAssertEqual(count.add(on: at("2026-07-29T00:01:00Z"), calendar: calendar), 1,
                       "a Mac left running overnight starts the day at zero")
    }

    /// Reading has to answer for the day being asked about, or a Mac nobody
    /// touched since yesterday shows yesterday's total under "today".
    func testReadingAcrossMidnightIsZeroWithoutCounting() {
        var count = DailyCount()
        _ = count.add(on: at("2026-07-28T22:00:00Z"), calendar: calendar)
        XCTAssertEqual(count.value(on: at("2026-07-28T22:30:00Z"), calendar: calendar), 1)
        XCTAssertEqual(count.value(on: at("2026-07-29T08:00:00Z"), calendar: calendar), 0)
    }

    func testAFreshCountIsZero() {
        XCTAssertEqual(DailyCount().value(on: at("2026-07-28T09:00:00Z"), calendar: calendar), 0)
    }
}
