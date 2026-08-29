import XCTest
@testable import Module_Layout_Engine

/// The count that outlives a launch.
///
/// `DailyCount` holds one day and holds it in memory, so the page's one figure
/// went back to zero at every launch — and the silent updater relaunches the
/// app. A Mac left running overnight showed yesterday's total until the next
/// conversion; a restart at noon showed the afternoon.
///
/// **No word is written down.** A day, a count, and how many characters those
/// words held — nothing else. The characters are there so «time saved» is
/// estimated from the length of the words that were actually fixed rather than
/// from an average, and they are as close to the text as this file ever gets.
final class TheLedgerCountsDaysNotLaunchesTests: XCTestCase {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: iso + "T12:00:00Z")!
    }

    func testAnEmptyLedgerHasNothingToSay() {
        let ledger = ConversionLedger()
        XCTAssertEqual(ledger.total(over: .today, now: day("2026-08-27"), calendar: calendar).words, 0)
        XCTAssertNil(ledger.since)
    }

    func testTwoConversionsOnOneDayAreOneRow() {
        var ledger = ConversionLedger()
        ledger.add(characters: 6, on: day("2026-08-27"), calendar: calendar)
        ledger.add(characters: 4, on: day("2026-08-27"), calendar: calendar)
        let today = ledger.total(over: .today, now: day("2026-08-27"), calendar: calendar)
        XCTAssertEqual(today.words, 2)
        XCTAssertEqual(today.characters, 10)
        XCTAssertEqual(ledger.days.count, 1, "one day is one row, however many words it holds")
    }

    /// The defect `DailyCount` could not fix: the figure survives the process.
    func testYesterdayIsStillThereToday() {
        var ledger = ConversionLedger()
        ledger.add(characters: 6, on: day("2026-08-26"), calendar: calendar)
        ledger.add(characters: 5, on: day("2026-08-27"), calendar: calendar)

        let now = day("2026-08-27")
        XCTAssertEqual(ledger.total(over: .today, now: now, calendar: calendar).words, 1,
                       "«today» must not count yesterday")
        XCTAssertEqual(ledger.total(over: .week, now: now, calendar: calendar).words, 2)
        XCTAssertEqual(ledger.total(over: .allTime, now: now, calendar: calendar).words, 2)
    }

    /// **The windows slide, they do not follow the calendar.** «This month» on
    /// the first of the month would be a figure that collapses overnight
    /// through no doing of the person reading it, which is the same complaint
    /// `DailyCount` was written for one scale down.
    func testAWeekIsTheLastSevenDaysAndAMonthTheLastThirty() {
        var ledger = ConversionLedger()
        ledger.add(characters: 3, on: day("2026-08-27"), calendar: calendar)          // today
        ledger.add(characters: 3, on: day("2026-08-22"), calendar: calendar)          // 5 days back
        ledger.add(characters: 3, on: day("2026-08-10"), calendar: calendar)          // 17 days back
        ledger.add(characters: 3, on: day("2024-01-01"), calendar: calendar)          // older than a year

        let now = day("2026-08-27")
        XCTAssertEqual(ledger.total(over: .today, now: now, calendar: calendar).words, 1)
        XCTAssertEqual(ledger.total(over: .week, now: now, calendar: calendar).words, 2)
        XCTAssertEqual(ledger.total(over: .month, now: now, calendar: calendar).words, 3)
        XCTAssertEqual(ledger.total(over: .year, now: now, calendar: calendar).words, 3)
        XCTAssertEqual(ledger.total(over: .allTime, now: now, calendar: calendar).words, 4)
    }

    /// «All time» has to say when all time began, or it is a number with no
    /// scale: 40 words is a lot in a week and nothing in three years.
    func testAllTimeKnowsWhenItStarted() {
        var ledger = ConversionLedger()
        ledger.add(characters: 3, on: day("2026-03-04"), calendar: calendar)
        ledger.add(characters: 3, on: day("2026-08-27"), calendar: calendar)
        XCTAssertEqual(ledger.since.map { calendar.startOfDay(for: $0) },
                       calendar.startOfDay(for: day("2026-03-04")))
    }

    /// A clock that went backwards — a stamp from the future — must not make
    /// «today» unreachable for the rest of the day.
    func testADayFromTheFutureDoesNotSwallowToday() {
        var ledger = ConversionLedger()
        ledger.add(characters: 4, on: day("2027-01-01"), calendar: calendar)
        ledger.add(characters: 4, on: day("2026-08-27"), calendar: calendar)
        let today = ledger.total(over: .today, now: day("2026-08-27"), calendar: calendar)
        XCTAssertEqual(today.words, 1)
    }

    func testTheRowsAreKeptInOrderSoTheFileReadsAsAHistory() {
        var ledger = ConversionLedger()
        ledger.add(characters: 1, on: day("2026-08-27"), calendar: calendar)
        ledger.add(characters: 1, on: day("2026-08-20"), calendar: calendar)
        XCTAssertEqual(ledger.days.map(\.words), [1, 1])
        XCTAssertTrue(ledger.days[0].day < ledger.days[1].day, "oldest first")
    }
}
