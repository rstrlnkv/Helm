import XCTest
@testable import Module_Layout_Engine

/// **A day is a day the person had, not an instant in UTC.**
///
/// `ConversionLedger.Day.day` is stored as `calendar.startOfDay(for: now)` — an
/// absolute `Date` — and every reader matches it with `==` or with a dictionary
/// keyed on it. Both are exact comparisons of an instant, and the instant that
/// «the start of today» names depends on the time zone the Mac was in when the
/// row was written.
///
/// `add`'s own comment already says «a Mac can wake in another timezone», and
/// answers it by re-sorting the rows. Sorting fixes the order; it does not make
/// two stamps for the same day one row. So the Mac correcting its own time zone
/// at lunchtime — «Set time zone automatically» after a flight, or after being
/// set up somewhere else — splits one day into two rows nine hours apart, and
/// nothing downstream puts them back together:
///
/// - `total(over: .today)` floors at *this* zone's midnight, so the morning's
///   row is below the floor and «words fixed today» drops back to what has
///   happened since the change;
/// - `recent(days:)` looks each day up by this zone's midnight, so the
///   morning's row matches no bar at all and the words vanish from the tile —
///   not shifted to a neighbouring day, gone.
///
/// The figures are the whole of the module's page. A count that goes backwards
/// through nothing the reader did is the complaint the ledger was written to
/// answer, one scale over: it replaced a counter that reset at every launch.
final class ADayIsTheSameDayInEitherTimeZoneTests: XCTestCase {

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func instant(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    /// The Mac believed it was in Moscow and was corrected to New York at
    /// midday. Both conversions are on Sunday 30 August in New York, which is
    /// the zone the reader is in when they look at the page: 06:00 UTC is
    /// 02:00 there, and 18:00 UTC is 14:00 there.
    private let morning = "2026-08-30T06:00:00Z"
    private let afternoon = "2026-08-30T18:00:00Z"

    /// One calendar day is one row — the same invariant
    /// `testTwoConversionsOnOneDayAreOneRow` states, asked of a day the Mac
    /// changed its mind about halfway through.
    func testAZoneChangeAtLunchtimeDoesNotSplitTheDayInTwo() {
        var ledger = ConversionLedger()
        ledger.add(characters: 6, on: instant(morning), calendar: calendar("Europe/Moscow"))
        ledger.add(characters: 4, on: instant(afternoon), calendar: calendar("America/New_York"))
        XCTAssertEqual(ledger.days.count, 1, """
            one day became two rows because the two stamps are two different \
            instants — 30 August 00:00 in Moscow and 30 August 00:00 in New \
            York are nine hours apart, and `add` matches the existing row with \
            `==`.
            """)
    }

    /// What the person sees: they fixed two words today and the page says one.
    func testTodayStillCountsTheWordsFixedBeforeTheZoneChanged() {
        var ledger = ConversionLedger()
        ledger.add(characters: 6, on: instant(morning), calendar: calendar("Europe/Moscow"))
        ledger.add(characters: 4, on: instant(afternoon), calendar: calendar("America/New_York"))
        let today = ledger.total(over: .today, now: instant(afternoon),
                                 calendar: calendar("America/New_York"))
        XCTAssertEqual(today.words, 2, """
            «words fixed today» went backwards at lunchtime: the morning's row \
            is stamped at Moscow's midnight, which is below this zone's floor \
            for today, so it is excluded from the one figure the page is built \
            around.
            """)
        XCTAssertEqual(today.characters, 10,
                       "the character count is what the time estimate is taken from, "
                       + "and it loses the same words")
    }

    /// The 2×N tile exists to answer «why is it that many», and a word that
    /// matches no bar is not drawn short — it is not drawn.
    func testNoWordFallsOutOfTheFortnightTheTileDraws() {
        var ledger = ConversionLedger()
        ledger.add(characters: 6, on: instant(morning), calendar: calendar("Europe/Moscow"))
        ledger.add(characters: 4, on: instant(afternoon), calendar: calendar("America/New_York"))
        let newYork = calendar("America/New_York")
        let row = ledger.recent(days: 14, now: instant(afternoon), calendar: newYork)
        XCTAssertEqual(row.reduce(0, +),
                       ledger.total(over: .allTime, now: instant(afternoon),
                                    calendar: newYork).words, """
            the fortnight's bars and the all-time figure disagree over a \
            fortnight that holds everything there is: `recent` looks each day \
            up by this zone's midnight and the morning's row is keyed to \
            another zone's, so it matches no bar — the words are absent from \
            the drawing rather than moved.
            """)
        XCTAssertEqual(row.last, 2, "both of today's words belong to today's bar")
    }

    /// Eastwards as well as westwards, so a fix cannot be «assume the clock
    /// only ever moves one way». Both instants are chosen inside the window
    /// where New York and Moscow agree on the date — 05:00 UTC is 01:00 in New
    /// York and 08:00 in Moscow, 20:00 UTC is 16:00 and 23:00 — so which day
    /// they belong to is not a matter of opinion in either zone.
    func testTheSameHoldsWhenTheZoneMovesEastwards() {
        var ledger = ConversionLedger()
        ledger.add(characters: 6, on: instant("2026-08-30T05:00:00Z"),
                   calendar: calendar("America/New_York"))
        ledger.add(characters: 4, on: instant("2026-08-30T20:00:00Z"),
                   calendar: calendar("Europe/Moscow"))
        XCTAssertEqual(ledger.days.count, 1, "one day, two zones, still one row")
        XCTAssertEqual(ledger.total(over: .today, now: instant("2026-08-30T20:00:00Z"),
                                    calendar: calendar("Europe/Moscow")).words, 2)
    }

    /// The zone did not change and nothing must move: the guard against the
    /// split has to leave the ordinary case exactly where it was, including a
    /// row that really is yesterday's.
    func testAnUnchangedZoneStillSeparatesYesterdayFromToday() {
        let moscow = calendar("Europe/Moscow")
        var ledger = ConversionLedger()
        ledger.add(characters: 6, on: instant("2026-08-29T15:00:00Z"), calendar: moscow)
        ledger.add(characters: 4, on: instant("2026-08-30T15:00:00Z"), calendar: moscow)
        XCTAssertEqual(ledger.days.count, 2)
        XCTAssertEqual(ledger.total(over: .today, now: instant("2026-08-30T15:00:00Z"),
                                    calendar: moscow).words, 1)
    }
}
