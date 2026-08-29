import XCTest
@testable import Module_Layout_Engine

/// The 2×N tile owes an answer to «why is it that many», and the only thing
/// that can answer it is the shape of the days behind the figure.
///
/// **A day with nothing in it is a row, not a gap.** The ledger stores only
/// days something happened on, so reading `days` straight would draw a fortnight
/// of five bars evenly spaced — a week off work and a busy week look identical,
/// which is the one thing the drawing exists to tell apart.
final class ARecentRowIsADayEvenWhenEmptyTests: XCTestCase {

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

    func testItGivesOneNumberPerDayAskedFor() {
        let ledger = ConversionLedger()
        XCTAssertEqual(ledger.recent(days: 14, now: at("2026-08-30T10:00:00Z"),
                                     calendar: calendar).count, 14)
    }

    func testADayNothingHappenedOnIsAZero() {
        var ledger = ConversionLedger()
        ledger.add(characters: 5, on: at("2026-08-28T10:00:00Z"), calendar: calendar)
        ledger.add(characters: 5, on: at("2026-08-30T10:00:00Z"), calendar: calendar)
        let row = ledger.recent(days: 4, now: at("2026-08-30T23:00:00Z"), calendar: calendar)
        // 27th, 28th, 29th, 30th — the 29th is the day off, and it is a zero
        // sitting between two ones rather than an absence between them.
        XCTAssertEqual(row, [0, 1, 0, 1])
    }

    func testTheLastNumberIsToday() {
        var ledger = ConversionLedger()
        ledger.add(words: 7, characters: 30, on: at("2026-08-30T10:00:00Z"), calendar: calendar)
        let row = ledger.recent(days: 3, now: at("2026-08-30T10:00:00Z"), calendar: calendar)
        XCTAssertEqual(row.last, 7)
    }

    /// A clock that went backwards must not push today off the end of the row —
    /// the same rule `total(over:now:)` keeps, for the same reason.
    func testADayStampedInTheFutureIsLeftOut() {
        var ledger = ConversionLedger()
        ledger.add(characters: 5, on: at("2026-09-10T10:00:00Z"), calendar: calendar)
        ledger.add(characters: 5, on: at("2026-08-30T10:00:00Z"), calendar: calendar)
        let row = ledger.recent(days: 2, now: at("2026-08-30T10:00:00Z"), calendar: calendar)
        XCTAssertEqual(row, [0, 1])
    }

    func testAskingForNothingGivesNothing() {
        let ledger = ConversionLedger()
        XCTAssertTrue(ledger.recent(days: 0, now: at("2026-08-30T10:00:00Z"),
                                    calendar: calendar).isEmpty)
    }
}
