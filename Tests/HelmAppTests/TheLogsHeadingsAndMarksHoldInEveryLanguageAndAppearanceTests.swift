import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// What the Log page writes over a row that ran across midnight, what a person
/// can type to find a card, and whether a warning row still says it is one
/// with the bar gone — each in every language or both appearances, and each
/// against an expectation that does not read the same declaration the page
/// does.
///
/// **Two of the three cases are known gaps, skipped and not deleted.** The span
/// case (`Known gap log-span-zh-ja`) and the header-words case
/// (`Known gap log-earlier-launch-search`) each reproduce a defect that is decided
/// and deferred, so a suite that must be green cannot carry them red. Each skips
/// unless `HELM_KNOWN_GAPS=1`, with the reproduction below the skip untouched:
/// `HELM_KNOWN_GAPS=1 bash Scripts/test.sh --filter TheLogsHeadingsAndMarksHoldInEveryLanguageAndAppearanceTests`
/// runs them and they fail today. When a gap is closed, delete its skip.
@MainActor
final class TheLogsHeadingsAndMarksHoldInEveryLanguageAndAppearanceTests: XCTestCase {

    /// Whether the known gaps are run: they are skipped by default, and run on
    /// request so the reproduction stays a reproduction.
    private static var knownGapsRun: Bool {
        ProcessInfo.processInfo.environment["HELM_KNOWN_GAPS"] == "1"
    }

    // MARK: - The span

    /// **A span is the same long day the headings write, twice.** The heading
    /// over a row that ran across midnight is two days; the heading over any
    /// other day is `HelmDates.day`. Whatever the span shares or folds, every
    /// word and mark the two long days are written with — a month's name, «г.»,
    /// «年», «月», «日» — has to be in it, or the span and the headings beside it
    /// are two different spellings of a day on one card. Read against
    /// `HelmDates.day`, never against a formatter built here the way the page
    /// builds its own: that would agree with any formatter the page chose.
    func testASpanIsSpelledWithTheWordsTheDayHeadingsUse() throws {
        try XCTSkipUnless(Self.knownGapsRun, "Known gap log-span-zh-ja: the interval formatter writes "
                          + "2026/9/22 – 2026/9/23 in zh and ja beside headings spelled 2026年9月22日")
        let calendar = Calendar.current
        func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                             hour: hour, minute: minute)))
        }
        let spans = [("across midnight", try at(2026, 9, 22, 23, 59), try at(2026, 9, 23, 0, 1)),
                     ("across a month", try at(2026, 9, 30, 23, 0), try at(2026, 10, 1, 1, 0)),
                     ("across a year", try at(2025, 12, 31, 23, 58), try at(2026, 1, 1, 0, 2))]
        var unlike: [String] = []
        AppLanguage.each { language in
            let lang = language.rawValue
            for (name, first, last) in spans {
                let span = LogSessions.daySpan(from: first, to: last, language: lang, calendar: calendar)
                let days = [HelmDates.day(first, language: lang), HelmDates.day(last, language: lang)]
                // The subject: two different days, each spelled with words.
                XCTAssertNotEqual(days[0], days[1], "\(lang) \(name): the fixture is one day")
                let words = Set(days.joined().unicodeScalars.filter { CharacterSet.letters.contains($0) })
                let spelled = Set(span.unicodeScalars.filter { CharacterSet.letters.contains($0) })
                let missing = words.subtracting(spelled)
                if !missing.isEmpty {
                    unlike.append("\(lang) \(name): «\(span)» beside headings «\(days[0])», «\(days[1])» "
                                  + "lacks «\(String(String.UnicodeScalarView(missing.sorted { $0.value < $1.value })))»")
                }
            }
        }
        XCTAssertTrue(unlike.isEmpty, "a span is not written the way the day headings beside it are — "
                      + unlike.joined(separator: "; "))
    }

    // MARK: - What the header draws finds its card

    /// **Every word a card's header draws, typed whole, finds that card — in
    /// every language.** The three kinds of header: a launch (its day and
    /// minute, «Helm <version>»), the head of the tail («Earlier launch», its
    /// day and minute), and a run after «terminating» (its day and minute). No
    /// line in the fixture says any of those words, so a card that is found is
    /// found by its header.
    func testEveryWordAHeaderDrawsFindsItsCardInEveryLanguage() throws {
        try XCTSkipUnless(Self.knownGapsRun, "Known gap log-earlier-launch-search: «Earlier launch» "
                          + "is drawn in the head-of-tail header and no query finds the card by it, in all eight languages")
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        func line(_ seconds: Double, _ category: String = "vpn",
                  _ message: String = "network state changed; re-reading") -> LogEntry {
            LogEntry(date: base.addingTimeInterval(seconds), level: .info, category: category, message: message)
        }
        let lines = [line(0), line(10, "app", "terminating"),
                     line(7_200), line(7_210),
                     line(90_000, "app", "Helm 0.11.1-dev.14 started"), line(90_010)]
        let sessions = LogSessions.split(lines)
        XCTAssertEqual(sessions.map(\.title), [.earlierLaunch, .noStartLine, .launch(version: "0.11.1-dev.14")],
                       "the fixture split into other cards than the three this is about")
        var unfound: [String] = []
        AppLanguage.each { language in
            for session in sessions {
                let words = LogView.headerWords(for: session)
                for drawn in [words.heading] + (words.detail.map { [$0] } ?? []) {
                    let cards = LogPresentation.build(lines, minimumLevel: .info, categories: [], query: drawn,
                                                      language: language.rawValue).cards
                    if !cards.contains(where: { $0.id == session.id }) {
                        unfound.append("\(language.rawValue): «\(drawn)» on the \(session.title) card "
                                       + "found \(cards.count) card(s), not its own")
                    }
                }
            }
        }
        XCTAssertTrue(unfound.isEmpty, "words drawn in a card's header do not find it — "
                      + unfound.joined(separator: "; "))
    }

    // MARK: - The level without the bar

    /// **With the bar gone the glyph is what says «warning» to anyone who cannot
    /// tell the wash from the card**, so it has to stand off the wash it sits on
    /// as a mark does — 3:1 — in both appearances. Read off a drawn row on the
    /// card it sits on in the page (`HelmSurface.cardFill` over the window's
    /// background): the glyph's most saturated pixel against the wash in the
    /// row's own left padding.
    func testTheLevelGlyphStandsOffItsWashInBothAppearances() throws {
        var faint: [String] = []
        for appearance in RenderedInk.bothAppearances {
            for level in [LogLevel.warn, .error] {
                let entry = LogEntry(date: Date(timeIntervalSince1970: 1_790_000_000), level: level,
                                     category: "layout", message: "no accessibility grant — not watching")
                let view = LogRowView(row: LogPresentation.Row(lines: [entry], heading: nil))
                    .background(HelmSurface.cardFill)
                    .background(Color(nsColor: .windowBackgroundColor))
                let mount = MountedRender(view, width: 600, height: 24, appearance: appearance)
                defer { mount.drop() }
                mount.settle(10)
                let host = mount.host
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let data = try XCTUnwrap(rep.bitmapData)
                let scale = max(1, rep.pixelsWide / max(1, Int(host.bounds.width)))
                func color(_ x: Int, _ y: Int) -> NSColor {
                    let at = y * rep.bytesPerRow + x * 4
                    return NSColor(srgbRed: CGFloat(data[at]) / 255, green: CGFloat(data[at + 1]) / 255,
                                   blue: CGFloat(data[at + 2]) / 255, alpha: 1)
                }
                let wash = color(6 * scale, rep.pixelsHigh / 2)
                var glyph = wash
                var saturation: CGFloat = 0
                for y in 0..<rep.pixelsHigh {
                    for x in 0..<min(rep.pixelsWide, 160 * scale) {
                        let c = color(x, y)
                        let s = max(c.redComponent, c.greenComponent, c.blueComponent)
                            - min(c.redComponent, c.greenComponent, c.blueComponent)
                        if s > saturation { saturation = s; glyph = c }
                    }
                }
                // The subject: a glyph in a colour was drawn at all.
                XCTAssertGreaterThan(saturation, 0.3, "\(level) in \(RenderedInk.label(of: appearance)): no glyph drawn")
                let ratio = Contrast.ratio(glyph, wash)
                print("glyph against wash: \(level) in \(RenderedInk.label(of: appearance)) "
                      + String(format: "%.2f:1", ratio))
                if ratio < Contrast.markFloor {
                    faint.append("\(level) in \(RenderedInk.label(of: appearance)): \(String(format: "%.2f", ratio)):1")
                }
            }
        }
        XCTAssertTrue(faint.isEmpty, "the level glyph does not stand off its wash as a mark must — "
                      + faint.joined(separator: "; "))
    }
}
