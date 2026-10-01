import AppKit
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// Two inputs the page did not survive: a foreign first line in the file, and a
/// time zone changed under a running app.
final class TheLogsDayHeadingNamesTheDayItsLinesWereDrawnOnTests: XCTestCase {

    private func headings(_ lines: [LogEntry]) -> [String?] {
        lines.indices.map { index in
            LogView.dayHeading(for: lines[index], after: index > 0 ? lines[index - 1] : nil,
                               language: AppLanguage.en.rawValue)
        }
    }

    /// A file whose first line is not one this app wrote — an older format, a
    /// hand edit — has no line above it to borrow a day from, so `LogSeed`
    /// dates it with the file's modification time: the newest moment in the
    /// file. The page then heads the file with the day it was last written,
    /// and the lines under it with the day they were actually written: the
    /// days read 30, 29 for a file that holds only the 29th.
    func testAFileWhoseFirstLineIsForeignIsHeadedByItsOwnDay() throws {
        let root = scratchDirectory("log-day-foreign-head")
        let file = root.appendingPathComponent("helm.log")
        try """
            Helm log, older format
            2026-09-29 10:00:00.000 [info] [app] one
            2026-09-29 11:00:00.000 [info] [app] two

            """.write(to: file, atomically: true, encoding: .utf8)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let lastWritten = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30,
                                                             hour: 18))!
        try FileManager.default.setAttributes([.modificationDate: lastWritten],
                                              ofItemAtPath: file.path)

        let seeded = LogSeed.read([file], atMost: 1 << 20, limit: 1000)
        XCTAssertEqual(seeded.count, 3, "the fixture did not seed three lines")
        XCTAssertEqual(seeded.first?.category, "", "the foreign line was read as one of ours")

        let drawn = headings(seeded).compactMap { $0 }
        let theDay = HelmDates.day(seeded[1].date, language: AppLanguage.en.rawValue)
        XCTAssertEqual(drawn, [theDay], """
            a file holding only \(theDay) was headed \(drawn) — the foreign first \
            line claimed the file's modification day
            """)
    }

    /// The heading and the row's clock must read the same zone. The day
    /// formatter copies a zone once, when a language first asks for it; the
    /// row's clock and the grouping calendar follow the zone the process is in
    /// now. Moved to UTC+14 after the page was first drawn, a line at 02:00 on
    /// the 30th is headed «September 29», and a line at 23:00 on the 29th
    /// beside it gets a second «September 29» — two headings, one day, and
    /// neither is the day the row under it shows.
    ///
    /// The move is made through `NSTimeZone.default`, which is what
    /// `Calendar.current` and a formatter without an explicit zone follow; that
    /// macOS routes a real time-zone change (travel, automatic zone) through
    /// the same default in a running app is inferred, not measured here.
    func testTheHeadingFollowsAZoneChangedWhileRunning() {
        // Every language's day formatter exists before the move, as it does in
        // an app that has drawn the page once; none is built inside the move,
        // so nothing here can leave a formatter holding the wrong zone behind.
        for language in AppLanguage.allCases {
            _ = HelmDates.day(Date(), language: language.rawValue)
        }
        let before = NSTimeZone.default
        addTeardownBlock { NSTimeZone.default = before }
        let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!
        XCTAssertNotEqual(before.secondsFromGMT(), kiritimati.secondsFromGMT(),
                          "this Mac is already in the zone the test moves to")
        NSTimeZone.default = kiritimati

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // 09:00 and 12:00 UTC on the 29th: 23:00 on the 29th and 02:00 on the
        // 30th in Kiritimati.
        let late = LogEntry(date: utc.date(from: DateComponents(year: 2026, month: 9, day: 29,
                                                                hour: 9))!,
                            level: .info, category: "app", message: "late")
        let early = LogEntry(date: utc.date(from: DateComponents(year: 2026, month: 9, day: 29,
                                                                 hour: 12))!,
                             level: .info, category: "app", message: "early")
        XCTAssertEqual(HelmDates.logTime(early.date), "02:00:00",
                       "the row's clock did not move with the zone — the fixture proves nothing")

        let reader = DateFormatter()
        reader.locale = Locale(identifier: AppLanguage.en.rawValue)
        reader.dateStyle = .long
        reader.timeStyle = .none
        reader.timeZone = kiritimati

        let drawn = headings([late, early])
        XCTAssertEqual(drawn[0], reader.string(from: late.date), "the first heading")
        XCTAssertEqual(drawn[1], reader.string(from: early.date), """
            the row reads \(HelmDates.logTime(early.date)) on \(reader.string(from: early.date)) \
            and its heading reads \(drawn[1] ?? "nil")
            """)
        XCTAssertNotEqual(drawn[0], drawn[1], "two headings in a row name one day")
    }
}
