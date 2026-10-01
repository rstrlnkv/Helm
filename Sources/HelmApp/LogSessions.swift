// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime
import HelmUI

// **What the Log page draws, derived from the lines and from nothing else.**
//
// The page shows one card per launch of the app. Nothing in the log file says
// "launch" except the line `HelmLog.start` writes first, so a launch is read
// out of the lines themselves — here, in pure functions, and not in the view:
// a view cannot be handed a fixture, and a rule about where one launch ends and
// the next begins is exactly what a fixture is for.
//
// **Nothing here drops a line or moves one.** Every function below takes the
// lines in the order they arrived and hands back the same lines in the same
// order, grouped. A line the grouping cannot make sense of stays where it was
// (an unreadable one is an ordinary `info` line with no category), because the
// page's promise is the file's own: what is drawn is what was written, folded
// but never edited. `TheLogSplitsIntoLaunchesTests` holds the round trip.

/// One launch of the app, as its own lines say it.
struct LogSession: Identifiable {
    /// Every line of the launch, in arrival order, the start line first when the
    /// launch has one. Never empty.
    let lines: [LogEntry]
    /// Whether `lines[0]` is a `Helm <version> started` line. False for a run
    /// with no start line of its own: the head of the tail, whose start scrolled
    /// out of it, and the lines after a «terminating» or after a «logging
    /// enabled» nothing answered (`title` says which).
    let opensWithLaunch: Bool
    /// How many lines follow the start line and belong to the start-up burst —
    /// `LogSessions.startupWindow` after it, all `info`.
    let startupCount: Int
    /// Whether this is the first launch of the tail and its start line is not in
    /// it: the launch the tail happens to begin in the middle of.
    let isTailHead: Bool

    init(lines: [LogEntry], opensWithLaunch: Bool, startupCount: Int, isTailHead: Bool = false) {
        self.lines = lines
        self.opensWithLaunch = opensWithLaunch
        self.startupCount = startupCount
        self.isTailHead = isTailHead
    }

    /// **The identity is the start line's — and one fixed identity for the
    /// tail's head.** A full tail drops its oldest line every second, so the
    /// first line of the head launch is a different line every second, and a
    /// card keyed on it is torn down and built whole on every tick: measured on
    /// a full tail that is one long launch, 70–92 ms of the main thread a tick
    /// against 37 ms with the identity held still. There is only ever one head,
    /// so one constant names it.
    var id: LogEntry.ID { isTailHead ? Self.tailHeadID : lines[0].id }
    private static let tailHeadID = UUID(uuidString: "5E9B6C5A-7A49-4E0B-9F4D-0C2B7D8E1A63")!
    var start: LogEntry? { opensWithLaunch ? lines[0] : nil }
    var version: String? { start.flatMap(LogSessions.version(of:)) }

    /// The start-up burst: what a launch says while it switches its modules on.
    var startup: ArraySlice<LogEntry> {
        opensWithLaunch ? lines[1..<(1 + startupCount)] : []
    }

    /// **A start line that is not an ordinary one is a row as well.** The header
    /// draws a day, a minute and a version and never the words of the line, so a
    /// start line that carries a warning or an error — a warning a crash tore
    /// and the next launch's first line glued on, or a warning with no site that
    /// quotes one — would be counted on the badge and shown nowhere. Such a line
    /// is the card's header *and* its first row.
    var startIsARow: Bool { opensWithLaunch && lines[0].level != .info }

    /// Everything after the start line and the burst — and the start line
    /// itself, first, when `startIsARow`.
    var rest: [LogEntry] {
        let after = Array(lines[(opensWithLaunch ? 1 + startupCount : 0)...])
        return startIsARow ? [lines[0]] + after : after
    }

    /// What the card's header calls the run, from what the file recorded of it.
    var title: LogCardTitle {
        if opensWithLaunch { return .launch(version: version) }
        return isTailHead ? .earlierLaunch : .noStartLine
    }

    func count(of level: LogLevel) -> Int { lines.filter { $0.level == level }.count }
}

/// **What a card's header calls the run** — three cases, because the file knows
/// three things about where a run began.
enum LogCardTitle: Equatable {
    /// Its own start line is the first line: the header is the time and the
    /// version the line names.
    case launch(version: String?)
    /// The first card of the tail, whose start line scrolled out of it: the run
    /// began *earlier* than anything the page holds, and the word says so.
    case earlierLaunch
    /// A run with no start line of its own that is not the tail's head — the
    /// lines after a «terminating», or after a «logging enabled» nothing
    /// answered. It began *later* than the card above it, so «earlier» would
    /// be false; what the file records is the time of its first line, and the
    /// header says that and nothing else.
    case noStartLine
}

enum LogSessions {

    /// **The one place a launch is recognised**, and the one place the words
    /// `HelmLog.start` writes are spelled a second time. The two sides are held
    /// together by `TheLogSplitsIntoLaunchesTests`, which has a real `HelmLog`
    /// write its start line and asks this to read it — a reworded start line
    /// otherwise turns every card into one long "earlier launch" and nothing
    /// says so.
    static let startCategory = "app"
    private static let startPrefix = "Helm "
    private static let startSuffix = " started"

    static func isStart(_ entry: LogEntry) -> Bool { version(of: entry) != nil }

    /// The version a start line names, or nil for any other line.
    ///
    /// **A start line a crash glued to a torn one is still a start.** A write cut
    /// short has no newline, so the next launch's first line is appended to it,
    /// and `LogSeed` — which keeps a line whole and claims nothing — reads the
    /// pair as one entry whose category is half a line plus the next stamp and
    /// whose message is the start line's own «[app] Helm … started». The launch
    /// after a crash is the one somebody opened the page for, so it is read here
    /// as the launch it is; the entry stays one line, in the place it was.
    static func version(of entry: LogEntry) -> String? {
        if entry.category == startCategory, let version = version(inMessage: entry.message) {
            return version
        }
        return versionOfGluedStart(entry)
    }

    /// The glued pair, whatever byte the tear fell on and whatever level the
    /// torn line had. `LogSeed` reads the pair as a stamp-level-category-message
    /// entry when it can and as one whole unreadable message when it cannot, so
    /// the two are put back into one string — category, «] », message — and the
    /// start line is looked for at the end of it: its own stamp, «[info] [app]
    /// Helm … started». A start line standing alone has category `app` and was
    /// answered before this is asked.
    ///
    /// **Not a line that carries a source site.** `HelmLog.warn` and `.error`
    /// write one on every line, and a glued start never has one — the start
    /// line is written without a site and is the end of the glued entry — so a
    /// warning or an error that merely quotes a start line (a copied log line, a
    /// file named like one) is not a launch. An `info` line has no site either,
    /// so the same quote at that level cannot be told from a tear by the entry
    /// alone.
    private static func versionOfGluedStart(_ entry: LogEntry) -> String? {
        guard entry.site == nil, entry.message.hasSuffix(startSuffix) else { return nil }
        let text = entry.category.isEmpty ? entry.message : entry.category + "] " + entry.message
        let marker = " [info] [\(startCategory)] \(startPrefix)"
        guard let found = text.range(of: marker, options: .backwards),
              text.distance(from: text.startIndex, to: found.lowerBound) >= 23,
              isStamp(text[text.index(found.lowerBound, offsetBy: -23)..<found.lowerBound])
        else { return nil }
        return version(inMessage: String(text[text.index(found.upperBound, offsetBy: -startPrefix.count)...]))
    }

    private static func version(inMessage message: String) -> String? {
        guard message.hasPrefix(startPrefix), message.hasSuffix(startSuffix),
              message.count > startPrefix.count + startSuffix.count
        else { return nil }
        return String(message.dropFirst(startPrefix.count).dropLast(startSuffix.count))
    }

    /// Exactly the 23 characters `LogLine.stampFormat` spells.
    private static func isStamp(_ text: Substring) -> Bool {
        let stamp = Array(text)
        guard stamp.count == 23 else { return false }
        return stamp.indices.allSatisfy { index in
            switch index {
            case 4, 7: return stamp[index] == "-"
            case 10: return stamp[index] == " "
            case 13, 16: return stamp[index] == ":"
            case 19: return stamp[index] == "."
            default: return stamp[index].isASCII && stamp[index].isNumber
            }
        }
    }

    static func isTerminating(_ entry: LogEntry) -> Bool {
        entry.category == startCategory && entry.message == "terminating"
    }

    /// **Lines that cannot belong to the launch above them.** A launch is not a
    /// process: two builds write one folder, and logging can be switched on in
    /// the middle of a run that wrote no start line. So a launch ends at the line
    /// where it says it is terminating — a process that has said so writes
    /// nothing more, and whatever follows is some other's — and a «logging
    /// enabled» that does not answer a «logging disabled» just above it is the
    /// first word of a run whose start this file never saw. Neither may be filed
    /// under the launch before it: the card would name a version for lines it
    /// cannot know the version of.
    private static func opensNewRun(_ entry: LogEntry, after run: [LogEntry]) -> Bool {
        guard let previous = run.last else { return false }
        // A «terminating» after a «terminating» has no launch of its own: two
        // builds that quit one after the other write it twice (49 ms apart in
        // the owner's log), and it belongs to the launch it ends. Anything else
        // after one is another run's.
        if isTerminating(previous) { return !isTerminating(entry) }
        guard entry.category == startCategory, let named = loggingEnabled(entry) else { return false }
        guard previous.category == startCategory && previous.message == "logging disabled" else { return true }
        // An answer — unless the on edge names a version and the launch above
        // knows its own, and they differ: then the off edge was another launch's.
        guard let enabledAs = named else { return false }
        // A run an older build opened with a bare «logging enabled» knows no
        // version, and a build that writes one is newer than any build that
        // wrote it bare: a version change is a relaunch, so this edge is
        // another launch's. A run with no first word of its own to go by (the
        // tail's head) is left whole, as before.
        guard let running = run.first.flatMap(versionOfRun(openedBy:)) else {
            return run.first.map(isBareLoggingEnabled) ?? false
        }
        return enabledAs != running
    }

    /// The version a run says it is: its start line's, or — for a run a stable
    /// build opened by switching logging on, which wrote no start line — the
    /// one on its own «logging enabled (version)».
    private static func versionOfRun(openedBy first: LogEntry) -> String? {
        if let version = version(of: first) { return version }
        guard first.category == startCategory, let named = loggingEnabled(first) else { return nil }
        return named
    }

    private static func isBareLoggingEnabled(_ entry: LogEntry) -> Bool {
        entry.category == startCategory && entry.message == "logging enabled"
    }

    /// `.some(nil)` for a bare «logging enabled» (older builds wrote no version),
    /// `.some(version)` for «logging enabled (version)», nil for any other line.
    private static func loggingEnabled(_ entry: LogEntry) -> String?? {
        let word = "logging enabled"
        if entry.message == word { return .some(nil) }
        guard entry.message.hasPrefix(word + " ("), entry.message.hasSuffix(")") else { return nil }
        return .some(String(entry.message.dropFirst(word.count + 2).dropLast()))
    }

    /// **How long after the start line a line still belongs to the burst.**
    /// Measured on a copy of the owner's log (`grep -c '^2026-09-30 13:04:11\.'`):
    /// the launch of 13:04:11 wrote 29 lines, its start line at .517 and the last
    /// at .660 of one second — every module's «enable», its memory reading, the
    /// list of modules, the permission probes — and the first line after it
    /// came at 13:04:19.075, 7.4 s after the last. Two seconds is that burst
    /// with room, and far from the next thing a launch says. The burst is only the
    /// **unbroken** run of `info` lines from the start line: a warning inside it
    /// ends it, so the fold can never hide one.
    static let startupWindow: TimeInterval = 2

    /// The lines cut into launches, in order.
    ///
    /// A launch begins at a start line and runs to the line before the next
    /// one, or to its own «terminating». Lines before the first start line — a
    /// tail that begins mid-launch — and lines that follow a «terminating» or an
    /// unanswered «logging enabled» are a run with no start line of its own, and
    /// so with no version.
    static func split(_ entries: [LogEntry]) -> [LogSession] {
        var sessions: [LogSession] = []
        var run: [LogEntry] = []
        func close() {
            guard !run.isEmpty else { return }
            let opens = isStart(run[0])
            sessions.append(LogSession(lines: run, opensWithLaunch: opens,
                                       startupCount: opens ? startupLength(of: run) : 0,
                                       isTailHead: sessions.isEmpty && !opens))
            run = []
        }
        for entry in entries {
            if isStart(entry) || opensNewRun(entry, after: run) { close() }
            run.append(entry)
        }
        close()
        return sessions
    }

    /// **The days a folded row stands for, written the way the language writes a
    /// span of days** — the system's own interval formatter, and not two days
    /// joined with a dash: the sign and its spacing are the language's (Japanese
    /// writes «～», and a day that shares its month or year with the other is
    /// written once). The long date style `HelmDates.day` uses, which makes a
    /// span and a heading one family in six of the eight languages; in Chinese
    /// and Japanese the interval formatter answers in numerals
    /// (`2026/9/22 – 2026/9/23`) beside a heading spelled `2026年9月22日`. That is
    /// a known gap, kept red-by-design in `testASpanIsSpelledWithTheWordsTheDayHeadingsUse`
    /// and skipped there until it is decided.
    ///
    /// The formatter is kept per language and zone, never in one constant: the
    /// app's language changes while it runs, and a formatter built per call is
    /// the cost the page reads a thousand rows to avoid.
    static func daySpan(from first: Date, to last: Date, language: String,
                        calendar: Calendar = .current) -> String {
        let spelled = spanFormatters.formatter(language: language, zone: calendar.timeZone)
            .string(from: first, to: last)
        // A formatter that answers nothing leaves the two days as `HelmDates`
        // writes them rather than an empty heading over a row.
        return spelled.isEmpty ? HelmDates.day(first, language: language) + " – "
            + HelmDates.day(last, language: language) : spelled
    }

    private static let spanFormatters = SpanFormatters()

    private final class SpanFormatters: @unchecked Sendable {
        private let lock = NSLock()
        private var made: [String: DateIntervalFormatter] = [:]

        func formatter(language: String, zone: TimeZone) -> DateIntervalFormatter {
            lock.lock()
            defer { lock.unlock() }
            let key = language + "|" + zone.identifier
            if let found = made[key] { return found }
            let formatter = DateIntervalFormatter()
            formatter.locale = Locale(identifier: language)
            formatter.timeZone = zone
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            made[key] = formatter
            return formatter
        }
    }

    /// How many lines after `run[0]` are the unbroken `info` burst.
    private static func startupLength(of run: [LogEntry]) -> Int {
        let opened = run[0].date
        var count = 0
        for entry in run.dropFirst() {
            // An unreadable line has no category and takes the `info` level of the
            // line above it, so it would fold away here; it is what a crash
            // leaves, and the one thing a fold must not hide besides a warning.
            guard entry.level == .info, !entry.category.isEmpty, entry.date.timeIntervalSince(opened) < startupWindow
            else { break }
            count += 1
        }
        return count
    }
}

/// Consecutive lines that say the same thing, folded to one.
enum LogRepeats {

    /// **The same line means the same in every part the file spells.** Level,
    /// category, message and site — the time is what differs, and a message with
    /// a number in it is a different message: masking digits would fold two
    /// memory readings into one, and the number is what the line is for. So
    /// what folds is exactly what the file repeats, never a guess at "similar".
    static func same(_ a: LogEntry, _ b: LogEntry) -> Bool {
        a.level == b.level && a.category == b.category && a.message == b.message && a.site == b.site
    }

    /// The runs, in order. Every run is non-empty and the runs joined are the
    /// input.
    static func collapse(_ lines: [LogEntry]) -> [[LogEntry]] {
        var runs: [[LogEntry]] = []
        for line in lines {
            if let last = runs.last?.last, same(last, line) {
                runs[runs.count - 1].append(line)
            } else {
                runs.append([line])
            }
        }
        return runs
    }
}

/// The text filter, one rule for the page and for its tests.
enum LogSearch {
    /// Case and accents ignored, over what a person can read on the row: the
    /// message, the module, and the place in the source. An empty query, or one
    /// of blanks, matches everything.
    static func matches(_ entry: LogEntry, _ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let haystacks = [entry.message, entry.category,
                         entry.site.map { "\($0.file):\($0.line) \($0.function)" } ?? ""]
        return haystacks.contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// What a card's header draws is searchable too: the version, and the
    /// launch's day and time. The start line alone matches «Helm 0.11.1 started»
    /// and is a header, never a row, so a search for the words on the card found
    /// nothing while they were on screen.
    ///
    /// **Whole words of the header, and nothing shorter.** «Helm» is on every
    /// card, «PM» on half of them and «0.11» on all, so a part of a header drew a
    /// card with no line in it for every launch of the tail (800 of 821 cards for
    /// «Helm» on the owner's log, all of them for «PM»). The query must be the
    /// version, «Helm <version>», or the day and minute as drawn, case and
    /// accents aside; a card whose lines match is drawn for its lines. The head of
    /// the tail also draws «Earlier launch», and no query finds a card by that
    /// word — a known gap, skipped in `testEveryWordAHeaderDrawsFindsItsCardInEveryLanguage`
    /// until it is decided.
    static func matches(header session: LogSession, _ query: String,
                        drawnTime: (Date) -> String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        // A card with no version still draws its day and time.
        let drawn = [session.version, session.version.map { "Helm \($0)" }, drawnTime(session.lines[0].date)]
        let typed = plainBlanks(needle)
        return drawn.compactMap { $0 }.contains {
            plainBlanks($0).compare(typed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// **Every blank is the one a keyboard types.** English draws «9/21/26,
    /// 7:13 PM» with a narrow no-break space (U+202F) before «PM», French draws
    /// one before a colon, and no key types either: compared as drawn, the time
    /// on a card could be read off the screen and never typed. Each blank is
    /// read as an ordinary space on both sides — one for one, so a doubled
    /// space inside is still not the drawn words.
    static func plainBlanks(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { $0.properties.isWhitespace ? " " : $0 }))
    }

    static func isActive(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Everything the page draws, computed once per read from the lines and the
/// three things a person chose: how bad, which module, and what word.
struct LogPresentation {

    /// A line, or a run of identical ones, as one row.
    struct Row: Identifiable {
        /// The lines the row stands for, in arrival order. One unless folded.
        let lines: [LogEntry]
        /// The day this row opens, when it is not the day of the row above it
        /// in the same card — a launch that crossed midnight.
        let heading: String?
        var id: LogEntry.ID { lines[0].id }
        var first: LogEntry { lines[0] }
        var last: LogEntry { lines[lines.count - 1] }
        var repeats: Int { lines.count }
    }

    struct Card: Identifiable {
        let session: LogSession
        /// The start-up burst's lines that passed the filters, folded like any
        /// other. Drawn only when the person opens the fold.
        let startup: [Row]
        let rows: [Row]
        /// The launch's own health, counted over **all** its lines and not over
        /// the ones the filters let through: a card that says «no warnings»
        /// because the Errors tab is open would be a sentence about the tab.
        /// Lines, not runs: a warning written a thousand times is a thousand.
        let warnings: Int
        let errors: Int
        var id: LogEntry.ID { session.id }

        /// The last row on the card — what Follow is following when this card is
        /// the newest.
        var newestID: LogEntry.ID { rows.last?.id ?? startup.last?.id ?? session.lines[0].id }
    }

    let cards: [Card]
    /// **What «Copy log» puts on the pasteboard:** the lines the cards stand for, expanded — every folded repeat and every
    /// start-up line that passed the filters, in the order they arrived, and the
    /// start line of every card drawn, because it is the card's own header and a
    /// pasted launch without its version is not a report.
    let lines: [LogEntry]
    /// Launches in the tail, drawn or not.
    let launchCount: Int
    /// **What the footer counts:** the lines on the page that passed the
    /// filters — the rows, the start-up fold, and a start line only where it
    /// passed them itself. Not `lines`: that is the copy set, which carries the
    /// header of every drawn card whether or not it passed, and under
    /// «Warnings» one more line per card than anything on the page. Not what the
    /// badges count either: a badge counts **all** of its launch's lines
    /// (`Card.warnings`), so with a filter on the two differ by design.
    let shown: Int

    var isEmpty: Bool { cards.isEmpty }
    var newestID: LogEntry.ID? { cards.last?.newestID }

    static func build(_ entries: [LogEntry], minimumLevel: LogLevel, categories: Set<String>,
                      query: String, language: String = AppLanguage.current.rawValue,
                      calendar: Calendar = .current) -> LogPresentation {
        let sessions = LogSessions.split(entries)
        let filtering = minimumLevel != .info || !categories.isEmpty || LogSearch.isActive(query)
        var cards: [Card] = []
        var copied: [LogEntry] = []
        var shown = 0
        for session in sessions {
            let passing = LogFilter.apply(session.lines, minimumLevel: minimumLevel,
                                          categories: categories)
                .filter { LogSearch.matches($0, query) }
            let passingIDs = Set(passing.map(\.id))
            let burst = session.startup.filter { passingIDs.contains($0.id) }
            let rest = session.rest.filter { passingIDs.contains($0.id) }
            // A launch with nothing to show under the filters is not drawn — the
            // start line alone never earns a card while a filter is on, since
            // it is the header and not a finding — unless the search names what
            // the header says: its version, its day. With no filter every launch
            // is drawn, even one that has only just said it started.
            let named = LogSearch.isActive(query)
                && LogSearch.matches(header: session, query, drawnTime: { HelmDates.dayAndMinute($0) })
            guard !filtering || !burst.isEmpty || !rest.isEmpty || named else { continue }

            var restRows: [Row] = []
            for run in LogRepeats.collapse(Array(rest)) {
                // The row above is judged by its **first** line: a repeat that ran
                // across midnight ends on the new day, and compared by its last
                // line it would swallow the heading of the row that follows it.
                let above = restRows.last?.first ?? session.lines[0]
                var heading = LogView.dayHeading(for: run[0], after: above, language: language,
                                                 calendar: calendar)
                // A repeat that ran across midnight is one row, and the day it
                // ended on would be named nowhere if nothing follows it: its
                // heading is the span, the days the row stands for.
                if let end = run.last, !calendar.isDate(run[0].date, inSameDayAs: end.date) {
                    heading = LogSessions.daySpan(from: run[0].date, to: end.date, language: language,
                                                  calendar: calendar)
                }
                restRows.append(Row(lines: run, heading: heading))
            }
            let burstRows = LogRepeats.collapse(Array(burst)).map { Row(lines: $0, heading: nil) }
            cards.append(Card(session: session, startup: burstRows, rows: restRows,
                              warnings: session.count(of: .warn), errors: session.count(of: .error)))

            let drawnIDs = Set(burst.map(\.id)).union(rest.map(\.id))
            // The start line counts where it passed the filters itself, and only
            // once: when it is also a row (`startIsARow`) it is in `drawnIDs`.
            let startCounts = session.opensWithLaunch && !session.startIsARow
                && passingIDs.contains(session.lines[0].id)
            shown += drawnIDs.count + (startCounts ? 1 : 0)
            copied += session.lines.enumerated().filter { index, line in
                (index == 0 && session.opensWithLaunch) || drawnIDs.contains(line.id)
            }.map(\.element)
        }
        return LogPresentation(cards: cards, lines: copied, launchCount: sessions.count, shown: shown)
    }
}
