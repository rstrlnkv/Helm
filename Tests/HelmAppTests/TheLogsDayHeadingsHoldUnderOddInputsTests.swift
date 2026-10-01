import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The day headings on the Log page, fed what the first test of them was not:
/// a line the seed could not read, a clock that stepped back over midnight, a
/// night whose hour repeats, a language switched between two renders, and a
/// time zone that changed while the app was running.
///
/// The rule under all of them: a heading is a claim about the lines below it,
/// so its words must name the day those lines' own times were drawn on, and a
/// run of lines on one day carries one heading however it reached the page.
final class TheLogsDayHeadingsHoldUnderOddInputsTests: XCTestCase {

    private func headings(_ lines: [LogEntry], calendar: Calendar = .current,
                          language: String = AppLanguage.en.rawValue) -> [String?] {
        lines.indices.map { index in
            LogView.dayHeading(for: lines[index], after: index > 0 ? lines[index - 1] : nil,
                               language: language, calendar: calendar)
        }
    }

    private func line(_ date: Date, _ message: String = "line") -> LogEntry {
        LogEntry(date: date, level: .info, category: "app", message: message)
    }

    /// A day in the process's own zone, the one the file's stamps are read in.
    private func local(_ day: Int, _ hour: Int, _ minute: Int = 0,
                       zone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: day,
                                                  hour: hour, minute: minute))!
    }

    // MARK: - The language

    /// The default argument is read at the call, not at first use: the page is
    /// rebuilt on a language change and must spell the day in the new one.
    func testTheHeadingFollowsALanguageSwitchedBetweenTwoCalls() {
        let first = line(local(29, 12))
        var spelled: [AppLanguage: String] = [:]
        AppLanguage.each { language in
            spelled[language] = LogView.dayHeading(for: first, after: nil)
        }
        for language in AppLanguage.allCases {
            XCTAssertEqual(spelled[language], HelmDates.day(first.date, language: language.rawValue),
                           "\(language): the heading kept a language the app had left")
        }
        // Chinese and Japanese write this day identically, so the spread is
        // asked of three languages that cannot agree.
        XCTAssertEqual(Set([spelled[.en], spelled[.ru], spelled[.de]]).count, 3,
                       "the switch did not reach the heading: \(spelled)")
    }

    // MARK: - The clock

    /// The live tail is in arrival order, and a clock stepped back over midnight
    /// puts a line from yesterday under today's. It is from yesterday, so the
    /// page has to say so again rather than fold it into the day above.
    func testALineFromYesterdayAfterMidnightIsNamedAgain() {
        let lines = [line(local(29, 23, 59)), line(local(30, 0, 1)), line(local(29, 23, 58))]
        let drawn = headings(lines)
        XCTAssertNotNil(drawn[0])
        XCTAssertNotNil(drawn[1], "midnight passed with no heading")
        XCTAssertNotNil(drawn[2], "a line from the 29th sat under the 30th's heading")
        XCTAssertEqual(drawn[2], drawn[0])
        XCTAssertNotEqual(drawn[1], drawn[0])
    }

    /// The night the clocks go back holds 01:30 twice and 25 hours; it is one
    /// day and gets one heading.
    func testTheNightTheClocksGoBackIsOneDay() {
        let york = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = york
        // 2026-11-01 01:30 EDT, then 01:30 EST an hour later.
        let firstHalfPast = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 1, hour: 1, minute: 30))!
        let secondHalfPast = firstHalfPast.addingTimeInterval(3600)
        XCTAssertEqual(calendar.component(.hour, from: secondHalfPast), 1,
                       "the fixture missed the repeated hour")
        let night = [calendar.date(from: DateComponents(year: 2026, month: 11, day: 1,
                                                         hour: 0, minute: 5))!,
                     firstHalfPast, secondHalfPast,
                     calendar.date(from: DateComponents(year: 2026, month: 11, day: 1,
                                                        hour: 23, minute: 55))!]
        let drawn = headings(night.map { line($0) }, calendar: calendar)
        XCTAssertNotNil(drawn[0])
        XCTAssertEqual(drawn.dropFirst().compactMap { $0 }, [],
                       "a 25-hour day was split: \(drawn)")
    }

    // MARK: - A line the seed could not read

    /// A torn line takes the day of the line above it, so it never opens a day
    /// of its own in the middle of a file.
    func testATornLineMidFileKeepsTheRunOfItsDay() {
        let text = """
            2026-09-29 23:59:00.000 [info] [app] before
            half a line with no stamp
            2026-09-30 00:01:00.000 [info] [app] after
            """
        let seeded = LogSeed.entries(from: text, startedMidFile: false,
                                     dated: local(30, 18), using: LogSeed.Stamps())
        XCTAssertEqual(seeded.count, 3)
        XCTAssertEqual(seeded[1].category, "", "the fixture's middle line was read")
        let drawn = headings(seeded)
        XCTAssertNotNil(drawn[0])
        XCTAssertNil(drawn[1], "the torn line opened a day of its own")
        XCTAssertNotNil(drawn[2])
    }

    /// Copy is the file's lines and nothing the page adds: no heading reaches
    /// the pasteboard, and every copied line still carries its own date.
    func testCopyCarriesNoHeading() {
        let lines = [line(local(29, 23)), line(local(30, 1))]
        let copied = LogView.pasteboardText(lines)
        let named = headings(lines).compactMap { $0 }
        // The subject first: two days, two headings on the page to keep out.
        XCTAssertEqual(named.count, 2, "the page drew no headings to leave out of the copy")
        for heading in named {
            XCTAssertFalse(copied.contains(heading), "copy carried «\(heading)»")
        }
        XCTAssertEqual(copied.split(separator: "\n").count, 2)
    }
    // MARK: - The page itself

    /// The pure function above is only half: the page has to draw what it
    /// answers. Two renders of the same thirteen lines, in a named appearance,
    /// differ only in the first line's day; the one that crosses midnight must
    /// draw exactly one more line of type — the second heading — and draw it
    /// between the first row and the second rather than anywhere else. The
    /// lines are one launch's card, whose header names the day it began, so
    /// the heading that is asserted is the one inside the card where the day
    /// turns; the page's own header strip above the card is not the subject
    /// and is read past (measured once: the same header read 7.5–41.5 in one of
    /// the two renders and 9.0–40.0 in the other; why was not traced).
    /// The header strip is 52 pt and ends in the band's own rule.
    private static let belowThePageHeader: CGFloat = 60

    @MainActor
    func testThePageDrawsTheSecondHeadingWhereTheDayTurns() throws {
        func bands(firstOn day: Int) throws -> [RenderedLines.Line] {
            let lines = [line(local(day, 0, 0), "first")]
                + (1..<13).map { line(local(30, 1, $0), "row \($0)") }
            let mount = MountedRender(LogView(source: { lines }, storedLog: { false }),
                                      width: 810, height: 700, appearance: .aqua)
            // The page reads its source in `onAppear`, a turn after the mount.
            let end = Date().addingTimeInterval(1.0)
            while Date() < end {
                mount.host.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            let read = try XCTUnwrap(RenderedLines.read(mount.host), "no reading of the page")
            return read.filter { $0.top > Self.belowThePageHeader }
        }
        let oneDay = try bands(firstOn: 30)
        let twoDays = try bands(firstOn: 29)
        // The subject first: thirteen rows and a heading are on the page.
        XCTAssertGreaterThanOrEqual(oneDay.count, 14, "the page drew no rows to head")
        XCTAssertEqual(twoDays.count, oneDay.count + 1,
                       "midnight inside the list drew \(twoDays.count - oneDay.count) extra lines")
        // Everything above the list is the same page; the first place the two
        // readings part is the new heading, and it sits below the first row.
        guard let parted = oneDay.indices.first(where: { oneDay[$0].top != twoDays[$0].top })
        else { return XCTFail("the two pages read alike") }
        XCTAssertGreaterThan(parted, 1)
        XCTAssertGreaterThan(twoDays[parted].top, twoDays[parted - 1].bottom)
        // Vertical extent only: the two renders' first rows read 181.5 and 182.0
        // at the right edge (measured), a half point of antialiasing on the same
        // glyphs, and what the heading above it would move is the row's height.
        XCTAssertEqual(twoDays[parted - 1].top, oneDay[parted - 1].top, accuracy: 0.01,
                       "the first row moved: the heading went above it")
        XCTAssertEqual(twoDays[parted - 1].bottom, oneDay[parted - 1].bottom, accuracy: 0.01,
                       "the first row moved: the heading went above it")
    }
}
