// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime
import HelmUI
import HelmAppStrings

// **What the Log page draws, derived from the lines and from nothing else.**
//
// Nothing in the log file says "launch" except the line `HelmLog.start` writes
// first, so a launch is read out of the lines themselves, in pure functions and
// not in the view: a view cannot be handed a fixture.
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

    /// **The identity is the start line's, and one fixed identity for the
    /// tail's head.** A full tail drops its oldest line every second, so a card
    /// keyed on the head's first line would be torn down and built whole on
    /// every tick. There is only ever one head, so one constant names it.
    var id: LogEntry.ID { isTailHead ? Self.tailHeadID : lines[0].id }
    private static let tailHeadID = UUID(uuidString: "5E9B6C5A-7A49-4E0B-9F4D-0C2B7D8E1A63")!
    var start: LogEntry? { opensWithLaunch ? lines[0] : nil }
    var version: String? { start.flatMap(LogSeed.version(of:)) }

    /// The start-up burst: what a launch says while it switches its modules on.
    var startup: ArraySlice<LogEntry> {
        opensWithLaunch ? lines[1..<(1 + startupCount)] : []
    }

    /// **A start line that is not an ordinary one is a row as well.** The header
    /// never draws the words of the line, so a start line that carries a warning
    /// or an error (a crash-torn line glued to the next launch's first) would be
    /// counted on the badge and shown nowhere. Such a line is the card's header
    /// *and* its first row.
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
    /// A run with no start line of its own that is not the tail's head: the
    /// lines after a «terminating», or after a «logging enabled» nothing
    /// answered. It began later than the card above it, so «earlier» would be
    /// false; the header says the time of its first line and nothing else.
    case noStartLine
}

enum LogSessions {

    static func isStart(_ entry: LogEntry) -> Bool { LogSeed.version(of: entry) != nil }

    /// **Lines that cannot belong to the launch above them.** A launch is not a
    /// process: files from two builds can interleave, and logging can be
    /// switched on in the middle of a run that wrote no start line. So a launch
    /// ends at the line where it says it is terminating (a process that has
    /// said so writes nothing more), and a «logging enabled» that does not
    /// answer a «logging disabled» just above it is the first word of a run
    /// whose start this file never saw. Neither may be filed under the launch
    /// before it: the card would name a version it cannot know.
    private static func opensNewRun(_ entry: LogEntry, after run: [LogEntry]) -> Bool {
        guard let previous = run.last else { return false }
        // A «terminating» after a «terminating» has no launch of its own: two
        // builds that quit one after the other write it twice, and it belongs
        // to the launch it ends. Anything else after one is another run's.
        if LogSeed.isTerminating(previous) { return !LogSeed.isTerminating(entry) }
        guard let named = LogSeed.loggingEnabled(entry) else { return false }
        guard LogSeed.isLoggingDisabled(previous) else { return true }
        // An answer — unless the on edge names a version and the launch above
        // knows its own, and they differ: then the off edge was another launch's.
        guard let enabledAs = named else { return false }
        // A run an older build opened with a bare «logging enabled» knows no
        // version, and a build that writes one is newer than any build that
        // wrote it bare: a version change is a relaunch, so this edge is
        // another launch's. A run with no first word of its own to go by (the
        // tail's head) is left whole.
        guard let running = run.first.flatMap(versionOfRun(openedBy:)) else {
            return run.first.map(LogSeed.isBareLoggingEnabled) ?? false
        }
        return enabledAs != running
    }

    /// The version a run says it is: its start line's, or — for a run a stable
    /// build opened by switching logging on, which wrote no start line — the
    /// one on its own «logging enabled (version)».
    private static func versionOfRun(openedBy first: LogEntry) -> String? {
        if let version = LogSeed.version(of: first) { return version }
        return LogSeed.loggingEnabled(first) ?? nil
    }

    /// **How long after the start line a line still belongs to the burst.** A
    /// launch's enables, memory reading and permission probes land within a
    /// fraction of a second, and the next thing it says comes seconds later;
    /// two seconds is the burst with room. The burst is only the **unbroken**
    /// run of `info` lines from the start line: a warning inside it ends it, so
    /// the fold can never hide one.
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
    /// launch's day and time. The start line is a header, never a row, so a
    /// search must find the words the card shows.
    ///
    /// **Whole words of the header, and nothing shorter.** «Helm», «PM» or a
    /// version prefix is on most cards, so a part of a header would draw an
    /// empty card for nearly every launch. The query must be the version,
    /// «Helm <version>», or the day and minute as drawn, case and accents aside;
    /// a card whose lines match is drawn for its lines. The head of the tail
    /// also draws «Earlier launch», in the page's language, and a part of those
    /// words finds that card (`LogCardTitle.earlierLaunch`): it is the one card
    /// that draws them, so a short query cannot draw every card.
    static func matches(header session: LogSession, _ query: String,
                        drawnTime: (Date) -> String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        // A card with no version still draws its day and time.
        let drawn = [session.version, session.version.map { "Helm \($0)" }, drawnTime(session.lines[0].date)]
        let typed = plainBlanks(needle)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if session.title == .earlierLaunch,
           plainBlanks(AppStr.logEarlierLaunch).range(of: typed, options: options) != nil {
            return true
        }
        return drawn.compactMap { $0 }.contains {
            plainBlanks($0).compare(typed, options: options) == .orderedSame
        }
    }

    /// **Every blank is the one a keyboard types.** English draws «9/21/26,
    /// 7:13 PM» with a narrow no-break space (U+202F) before «PM», French draws
    /// one before a colon, and no key types either. Each blank is read as an
    /// ordinary space on both sides, one for one, so a doubled space inside is
    /// still not the drawn words.
    static func plainBlanks(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { $0.properties.isWhitespace ? " " : $0 }))
    }

    static func isActive(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Everything the page has to draw, computed once per read from the lines and the
/// three things a person chose: how bad, which module, and what word. The page
/// draws the newest launches of it and the earlier ones on request
/// (`drawn(rowsBefore:)`); the copy, the footer and the count of launches are
/// over all of it.
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

    /// The day a run of lines belongs to, written when it changes.
    ///
    /// **A heading and not a column.** A date beside every row's time would
    /// cost a large share of the message width, for a day that changes a few
    /// times in a log. Inside a card it is written where a launch crosses
    /// midnight; the card's own header names the day it began.
    ///
    /// The spelling is `HelmDates.day` — the app's language, a formatter cached
    /// per language — and the comparison is the reader's calendar day, the same
    /// clock the row's time is drawn in. Nil for a line on the same day as the
    /// one above it in what is *shown*, never in what exists.
    static func dayHeading(for entry: LogEntry, after previous: LogEntry?,
                           language: String, calendar: Calendar) -> String? {
        if let previous, calendar.isDate(entry.date, inSameDayAs: previous.date) { return nil }
        return HelmDates.day(entry.date, language: language)
    }

    let cards: [Card]
    /// **What «Copy log» puts on the pasteboard:** the lines the cards stand for, expanded — every folded repeat and every
    /// start-up line that passed the filters, in the order they arrived, and the
    /// start line of every card in `cards`, drawn yet or not, because it is the
    /// card's own header and a pasted launch without its version is not a report.
    let lines: [LogEntry]
    /// Launches in the tail, drawn or not.
    let launchCount: Int
    /// **What the footer counts:** the lines of every card in `cards`, drawn yet
    /// or not, that passed the filters: the rows, the start-up fold, and a start
    /// line only where it passed them itself. Not `lines`, which carries every
    /// card's header whether or not it passed, and not the badges, which count
    /// all of a launch's lines (`Card.warnings`): with a filter on, they differ
    /// by design.
    let shown: Int

    var isEmpty: Bool { cards.isEmpty }
    var newestID: LogEntry.ID? { cards.last?.newestID }

    /// **The launches the page draws: the newest, whole, and before it the
    /// nearest older ones, whole, until those older ones hold at least
    /// `rowsBefore` rows between them** (a card counts its rows and its start-up
    /// rows). Every card when they hold fewer, and only the newest when
    /// `rowsBefore` is 0 or below. A card is never split, which would put a
    /// header and its fold over rows that begin mid-launch.
    ///
    /// **The newest card is outside the count** because it is the only one that
    /// grows: counted from the end, the cut would move as lines arrive and take
    /// a card away from under a reader standing in it. The rest is
    /// Architecture/DiagnosticsLog.md § The log pane.
    func drawn(rowsBefore: Int) -> ArraySlice<Card> {
        guard !cards.isEmpty else { return cards[...] }
        var first = cards.count - 1
        var held = 0
        while first > 0, held < rowsBefore {
            first -= 1
            held += cards[first].rows.count + cards[first].startup.count
        }
        return cards[first...]
    }

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
            // A launch with nothing to show under the filters gets no card (the
            // start line is the header, not a finding) unless the search names
            // what the header says. With no filter every launch gets a card.
            let named = LogSearch.isActive(query)
                && LogSearch.matches(header: session, query, drawnTime: { HelmDates.dayAndMinute($0) })
            guard !filtering || !burst.isEmpty || !rest.isEmpty || named else { continue }

            var restRows: [Row] = []
            for run in LogRepeats.collapse(Array(rest)) {
                // The row above is judged by its **first** line: a repeat that ran
                // across midnight ends on the new day, and compared by its last
                // line it would swallow the heading of the row that follows it.
                let above = restRows.last?.first ?? session.lines[0]
                var heading = LogPresentation.dayHeading(for: run[0], after: above, language: language,
                                                         calendar: calendar)
                // A repeat that ran across midnight is one row, and the day it
                // ended on would be named nowhere if nothing follows it: its
                // heading is the span, the days the row stands for.
                if let end = run.last, !calendar.isDate(run[0].date, inSameDayAs: end.date) {
                    heading = HelmDates.daySpan(from: run[0].date, to: end.date, language: language,
                                                  zone: calendar.timeZone)
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
