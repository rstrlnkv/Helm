import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The Log page's split, folds and filters run over a real log. What it reads is
/// somebody's machine, so it skips unless `HELM_LOG_SAMPLE` names a folder
/// holding a *copy* of `helm.previous.log` and `helm.log` (never the live
/// folder: the app is writing to it).
///
/// `HELM_LOG_SAMPLE=/path/to/copies bash Scripts/test.sh --filter TheLogCardsHoldOnARealLogTests`
///
/// What it asserts holds for any log: the parse is the exact inverse of the
/// format, no line is lost or moved by the split or by the presentation, no
/// warning or error ever sits in a start-up fold, under «Warnings» every
/// warning and error is drawn once, no card keeps lines written after its
/// launch said it was terminating, and every day a launch runs into is named
/// on its card. The counts in the messages are the ones on the owner's log.
final class TheLogCardsHoldOnARealLogTests: XCTestCase {

    private func sample() throws -> [LogEntry] {
        guard let folder = ProcessInfo.processInfo.environment["HELM_LOG_SAMPLE"] else {
            throw XCTSkip("HELM_LOG_SAMPLE names no copy of a real log")
        }
        let urls = ["helm.previous.log", "helm.log"].map {
            URL(fileURLWithPath: folder).appendingPathComponent($0)
        }
        let stamps = LogSeed.Stamps()
        var out: [LogEntry] = []
        var raw: [String] = []
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            let text = try String(contentsOf: url, encoding: .utf8)
            raw += text.components(separatedBy: "\n").filter { !$0.isEmpty }
            out += LogSeed.entries(from: text, startedMidFile: false, dated: .distantPast, using: stamps)
        }
        XCTAssertGreaterThan(out.count, 1000, "the sample is too small to prove anything")
        XCTAssertEqual(out.count, raw.count, "the seed dropped or invented lines")
        // The seed is the inverse of the format: every readable line spells back
        // to the very bytes it was read from.
        let readable = zip(out, raw).filter { !$0.0.category.isEmpty }
        let spelled = LogLine.lines(readable.map(\.0)).components(separatedBy: "\n")
        XCTAssertEqual(spelled.count, readable.count)
        var differing = 0, first = ""
        for ((_, line), back) in zip(readable, spelled) where back != line {
            differing += 1
            if first.isEmpty { first = "\(line)\n→ \(back)" }
        }
        XCTAssertEqual(differing, 0, "\(differing) lines do not spell back; first:\n\(first)")
        return out
    }

    func testTheCardsLoseNothingAndFoldNoWarningOnARealLog() throws {
        let lines = try sample()
        let ids = lines.map(\.id)

        let sessions = LogSessions.split(lines)
        XCTAssertEqual(sessions.flatMap(\.lines).map(\.id), ids, "the split lost or moved a line")
        let starts = lines.filter(LogSessions.isStart).count
        XCTAssertEqual(sessions.filter(\.opensWithLaunch).count, starts)
        let folded = sessions.flatMap(\.startup).filter { $0.level != .info }
        XCTAssertTrue(folded.isEmpty, "\(folded.count) warnings or errors sit in a start-up fold")
        let bursts = sessions.map(\.startupCount)

        let all = LogPresentation.build(lines, minimumLevel: .info, categories: [], query: "",
                                        language: "en")
        XCTAssertEqual(all.lines.map(\.id), ids, "«Copy log» under «All» is not the file")
        for card in all.cards {
            let drawn = (card.session.start.map { [$0] } ?? [])
                + card.startup.flatMap(\.lines) + card.rows.flatMap(\.lines)
            XCTAssertEqual(drawn.map(\.id), card.session.lines.map(\.id),
                           "a card does not draw its launch's lines in order")
        }

        let problems = lines.filter { $0.level != .info }
        let warned = LogPresentation.build(lines, minimumLevel: .warn, categories: [], query: "",
                                           language: "en")
        let drawnProblems = warned.cards.flatMap { $0.startup + $0.rows }.flatMap(\.lines)
        XCTAssertEqual(drawnProblems.map(\.id), problems.map(\.id),
                       "under «Warnings» a warning or error is missing, doubled or moved")
        let widest = warned.cards.flatMap(\.rows).max { $0.repeats < $1.repeats }

        print("""
            real log: \(lines.count) lines, \(sessions.count) launches (\(starts) start lines), \
            \(lines.filter { $0.category.isEmpty }.count) unreadable; burst lines max \
            \(bursts.max() ?? 0), median \(bursts.isEmpty ? 0 : bursts.sorted()[bursts.count / 2]); under Warnings \
            \(warned.cards.count) cards, \(drawnProblems.count) lines in \
            \(warned.cards.flatMap(\.rows).count) rows, widest ×\(widest?.repeats ?? 0) from \
            \(widest.map { HelmDates.dayAndMinute($0.first.date) } ?? "-") to \
            \(widest.map { HelmDates.dayAndMinute($0.last.date) } ?? "-")
            """)
    }

    /// Lines after «[app] terminating» and before the next start are some other
    /// process's — two builds share the folder — and a card that keeps them
    /// names a version for lines it cannot know the version of. The one thing
    /// a card may keep after its «terminating» is another «terminating»: two
    /// builds that quit one after the other write it twice, and the second has
    /// no launch of its own to be a card of.
    func testNoCardKeepsLinesWrittenAfterItsLaunchSaidItWasTerminating() throws {
        let lines = try sample()
        let sessions = LogSessions.split(lines)
        // A split that answered nothing keeps nothing after a «terminating».
        XCTAssertEqual(sessions.flatMap(\.lines).count, lines.count, "the split lost lines: nothing was judged")
        func terminating(_ line: LogEntry) -> Bool { line.category == "app" && line.message == "terminating" }
        func strangers(in session: LogSession) -> Int {
            guard let end = session.lines.firstIndex(where: terminating) else { return 0 }
            return session.lines[(end + 1)...].filter { !terminating($0) }.count
        }
        let merged = sessions.filter { strangers(in: $0) > 0 }
        let example = merged.first.map { session -> String in
            let end = session.lines.firstIndex(where: terminating)!
            return "«Helm \(session.version ?? "?")» from \(HelmDates.dayAndMinute(session.lines[0].date)) "
                + "keeps \(strangers(in: session)) lines after its «terminating» at "
                + HelmDates.dayAndMinute(session.lines[end].date)
        } ?? ""
        XCTAssertEqual(merged.count, 0, "\(merged.count) of \(sessions.count) cards: \(example)")
    }

    /// A search for a word every header carries draws the cards whose lines
    /// say it, and no card that holds no line: measured on the owner's log
    /// before the rule, «Helm» drew 800 empty cards of 821 and «PM» every card
    /// there was.
    func testASearchForAPartOfAHeaderDrawsNoCardWithNoLineInIt() throws {
        let lines = try sample()
        var drawn: [String: Int] = [:]
        for word in ["Helm", "0.11", "PM", "2"] {
            let page = LogPresentation.build(lines, minimumLevel: .info, categories: [], query: word)
            drawn[word] = page.cards.count
            let empty = page.cards.filter { $0.rows.isEmpty && $0.startup.isEmpty }.count
            XCTAssertEqual(empty, 0, "«\(word)» drew \(empty) of \(page.cards.count) cards with no line in them")
        }
        XCTAssertGreaterThan(drawn["Helm"] ?? 0, 0, "no line of the log says «Helm»: the absence above proves nothing")
        XCTAssertLessThan(drawn["Helm"] ?? 0, LogSessions.split(lines).count / 2,
                          "«Helm» still draws most of the tail: \(drawn)")
    }

    /// Every day a launch's lines run into is named inside its card — the card
    /// header names the day of its first line, and a row's heading names the day
    /// it opens, or, for a ×N row that ran across midnight, every day of its
    /// span («13.08 – 15.08» names the 14th too).
    ///
    /// Compared as sets of days, never as counts: a heading that names one day
    /// twice must not pay for a day that is named nowhere.
    func testEveryDayALaunchRunsIntoIsNamedOnItsCard() throws {
        let lines = try sample()
        let calendar = Calendar.current
        func days(from first: Date, to last: Date) -> Set<Date> {
            var out: Set<Date> = []
            var day = calendar.startOfDay(for: first)
            let end = calendar.startOfDay(for: last)
            while day <= end {
                out.insert(day)
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            return out
        }
        for level in [LogLevel.info, .warn] {
            let page = LogPresentation.build(lines, minimumLevel: level, categories: [], query: "",
                                             language: "en")
            // No cards leaves no day unnamed: the zero below has to be a zero somebody read.
            XCTAssertFalse(page.cards.isEmpty, "\(level): no card was drawn, so no day was judged")
            var silent = 0, headed = 0, spans = 0, example = ""
            for card in page.cards {
                let drawn = (card.session.start.map { [$0] } ?? [])
                    + card.startup.flatMap(\.lines) + card.rows.flatMap(\.lines)
                let lived = Set(drawn.map { calendar.startOfDay(for: $0.date) })
                var named: Set<Date> = [calendar.startOfDay(for: card.session.lines[0].date)]
                for row in card.rows where row.heading != nil {
                    headed += 1
                    if !calendar.isDate(row.first.date, inSameDayAs: row.last.date) { spans += 1 }
                    named.formUnion(days(from: row.first.date, to: row.last.date))
                }
                let unnamed = lived.subtracting(named)
                silent += unnamed.count
                if !unnamed.isEmpty, example.isEmpty {
                    example = "card from \(HelmDates.dayAndMinute(card.session.lines[0].date)) "
                        + "runs over \(lived.count) days and leaves "
                        + unnamed.sorted().map { HelmDates.day($0, language: "en") }.joined(separator: ", ")
                        + " unnamed"
                }
            }
            print("\(level): \(page.cards.count) cards, \(headed) headings, \(spans) of them spans, "
                  + "\(silent) days unnamed")
            XCTAssertEqual(silent, 0, "\(level): \(silent) days never named; \(example)")
        }
    }
}
