import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp
import HelmAppStrings

/// What the Log page draws is derived from the lines themselves, in pure
/// functions (`LogSessions`, `LogRepeats`, `LogSearch`, `LogPresentation`) — so
/// the rules that decide where one launch ends and the next begins, what folds
/// and what a filter leaves are held here on fixtures, not on a mounted page.
///
/// The property under everything: **grouping never drops a line and never moves
/// one.** The page's promise is the file's own, and «Copy log» hands back the
/// lines expanded.
final class TheLogSplitsIntoLaunchesTests: XCTestCase {

    /// 14:13:20 UTC on 21 September 2026 — a fixed instant, so the lines of the
    /// fixtures do not move with this Mac's clock. The spelling of a day or a
    /// minute (`HelmDates`) is in this Mac's zone, and one test reads the clock
    /// itself (`Date()`, for yesterday's launch). (`date -u -r 1790000000`)
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func line(_ seconds: Double, _ level: LogLevel = .info, _ category: String = "host",
                      _ message: String = "enable vpn", site: LogSite? = nil) -> LogEntry {
        LogEntry(date: base.addingTimeInterval(seconds), level: level, category: category,
                 message: message, site: site)
    }

    private func start(_ seconds: Double, _ version: String = "0.11.1-dev.14") -> LogEntry {
        line(seconds, .info, "app", "Helm \(version) started")
    }

    private func ids(_ lines: [LogEntry]) -> [LogEntry.ID] { lines.map(\.id) }

    // MARK: - Where a launch begins

    func testEveryStartLineOpensACardAndLinesBeforeTheFirstFormOneOfTheirOwn() {
        let lines = [line(0), line(1),
                     start(10, "0.11.1-dev.13"), line(10.1), line(60),
                     start(500, "0.11.1-dev.14"), line(500.1)]

        let sessions = LogSessions.split(lines)

        XCTAssertEqual(sessions.count, 3)
        guard sessions.count == 3 else { return }
        XCTAssertFalse(sessions[0].opensWithLaunch, "the lines before the first start are no launch's start")
        XCTAssertNil(sessions[0].version)
        XCTAssertEqual(sessions[0].lines.count, 2)
        XCTAssertEqual(sessions.map(\.version), [nil, "0.11.1-dev.13", "0.11.1-dev.14"])
        XCTAssertEqual(sessions[1].lines.count, 3)
        XCTAssertEqual(sessions[2].start?.id, lines[5].id)
    }

    func testAnEmptyTailIsNoLaunches() {
        XCTAssertEqual(LogSessions.split([]).count, 0)
    }

    /// Only the line `HelmLog.start` writes opens a card: the same words from
    /// another module, or without a version, are ordinary lines.
    func testOnlyTheAppsOwnStartLineIsAStart() {
        XCTAssertTrue(LogSessions.isStart(start(0)))
        XCTAssertFalse(LogSessions.isStart(line(0, .info, "host", "Helm 1.0 started")),
                       "another module's line with the same words opened a launch")
        XCTAssertFalse(LogSessions.isStart(line(0, .info, "app", "Helm started")),
                       "a start line with no version opened a launch")
        XCTAssertFalse(LogSessions.isStart(line(0, .info, "app", "Helm  started")))
        XCTAssertFalse(LogSessions.isStart(line(0, .info, "app", "terminating")))
    }

    /// **The contract with the writer, held from both sides.** The words are
    /// `HelmLog.start`'s; this has a real log write its start line and asks the
    /// reader to recognise it, so rewording either side turns this red instead
    /// of turning every card into one long earlier launch.
    func testTheLineHelmLogWritesAtLaunchIsTheOneThePageReads() {
        let log = HelmLog(seedFiles: [])
        log.start(version: "9.9.9-dev.1", override: true)

        let written = log.recentEntries()

        XCTAssertEqual(written.count, 1, "start wrote \(written.count) lines, not one")
        XCTAssertEqual(written.first.flatMap(LogSessions.version(of:)), "9.9.9-dev.1",
                       "the page cannot read the line HelmLog writes at launch: "
                       + "\(written.first?.category ?? "?") \(written.first?.message ?? "?")")
    }

    // MARK: - Nothing dropped, nothing moved

    /// Fixtures prove the rules; this proves the property, over lines nobody
    /// chose: two hundred and fifty pseudo-random lines, starts scattered
    /// through them, dates going backwards where they like. The split has to
    /// hand back exactly the same ids in exactly the same order.
    func testTheSplitDropsAndReordersNothingWhateverTheLinesAre() {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(seed >> 33)
        }
        let categories = ["app", "host", "memory", "vpn", ""]
        let levels: [LogLevel] = [.info, .info, .info, .warn, .error]
        let lines = (0..<250).map { index -> LogEntry in
            if next() % 9 == 0 { return start(Double(next() % 500) - 250, "v\(index)") }
            return line(Double(next() % 500) - 250, levels[next() % levels.count],
                        categories[next() % categories.count], "message \(next() % 5)")
        }

        let sessions = LogSessions.split(lines)

        XCTAssertGreaterThan(sessions.count, 5, "the fixture drew too few starts to prove anything")
        XCTAssertEqual(ids(sessions.flatMap(\.lines)), ids(lines))
        for session in sessions {
            XCTAssertFalse(session.lines.isEmpty)
            XCTAssertEqual(ids(Array(session.startup) + Array(session.rest)),
                           ids(Array(session.lines.dropFirst(session.opensWithLaunch ? 1 : 0))),
                           "the burst and the rest are not the launch's lines after its start")
        }
    }

    func testAnUnreadableLineStaysWhereItWasAndBelongsToItsNeighbours() {
        let stray = LogEntry(date: base.addingTimeInterval(20), level: .info, category: "",
                             message: "Helm-OLD-FORMAT half-written line")
        let lines = [start(0), line(30), stray, line(40), start(100)]

        let sessions = LogSessions.split(lines)

        XCTAssertEqual(sessions.count, 2)
        guard sessions.count == 2 else { return }
        XCTAssertEqual(ids(sessions[0].lines), ids(Array(lines[0..<4])))
        XCTAssertTrue(sessions[0].lines.contains { $0.id == stray.id })
    }

    // MARK: - The start-up burst

    func testTheBurstIsTheUnbrokenInfoRunInsideTheWindow() {
        let lines = [start(0), line(0.05), line(0.10), line(0.15), line(0.20),
                     line(1.99), line(2.0, .info, "vpn", "at the window's edge"), line(7)]

        guard let session = LogSessions.split(lines).first else { return XCTFail("the split drew no launch") }

        XCTAssertEqual(session.startupCount, 5, "the burst is the lines before the window closes")
        XCTAssertEqual(ids(Array(session.rest)), ids(Array(lines[6...])),
                       "a line at the window's edge or after it is not part of the burst")
    }

    /// The fold can never hide a warning: the burst ends at the first line that
    /// is not information, and what follows is drawn.
    func testAWarningEndsTheBurstAndIsNeverFolded() {
        let warning = line(0.12, .warn, "layout", "no accessibility grant")
        let lines = [start(0), line(0.05), line(0.10), warning, line(0.13)]

        guard let session = LogSessions.split(lines).first else { return XCTFail("the split drew no launch") }

        XCTAssertEqual(session.startupCount, 2)
        XCTAssertEqual(ids(Array(session.rest)), ids([warning, lines[4]]))
    }

    func testALaunchWithNoStartHasNoBurst() {
        guard let session = LogSessions.split([line(0), line(0.1), line(0.2)]).first else {
            return XCTFail("the split drew no launch")
        }
        XCTAssertFalse(session.opensWithLaunch)
        XCTAssertEqual(session.startupCount, 0)
        XCTAssertTrue(session.startup.isEmpty)
        XCTAssertEqual(session.rest.count, 3)
    }

    // MARK: - Repeats

    func testConsecutiveIdenticalLinesFoldToOneRunAndTheRunsJoinBackToTheInput() {
        let warn = { (t: Double) in self.line(t, .warn, "layout", "no accessibility grant") }
        let lines = [warn(0), warn(1), warn(2), line(3), warn(4), warn(5)]

        let runs = LogRepeats.collapse(lines)

        XCTAssertEqual(runs.map(\.count), [3, 1, 2])
        XCTAssertEqual(ids(runs.flatMap { $0 }), ids(lines))
    }

    /// The numbers are what a memory reading is for. Two readings that differ
    /// in a figure are two lines, however alike.
    func testALineWithADifferentNumberIsADifferentLine() {
        let lines = [line(0, .info, "memory", "sample: 143 MB"),
                     line(1, .info, "memory", "sample: 123 MB")]
        XCTAssertEqual(LogRepeats.collapse(lines).count, 2)
    }

    func testLevelCategoryAndSiteEachKeepLinesApart() {
        let site = LogSite(file: "A.swift", line: 1, function: "f()")
        let other = LogSite(file: "A.swift", line: 2, function: "f()")
        let a = line(0, .warn, "vpn", "same", site: site)
        XCTAssertEqual(LogRepeats.collapse([a, line(1, .warn, "vpn", "same", site: site)]).count, 1)
        XCTAssertEqual(LogRepeats.collapse([a, line(1, .error, "vpn", "same", site: site)]).count, 2, "level")
        XCTAssertEqual(LogRepeats.collapse([a, line(1, .warn, "host", "same", site: site)]).count, 2, "category")
        XCTAssertEqual(LogRepeats.collapse([a, line(1, .warn, "vpn", "same", site: other)]).count, 2, "site")
        XCTAssertEqual(LogRepeats.collapse([a, line(1, .warn, "vpn", "same")]).count, 2, "no site")
    }

    // MARK: - Search

    func testSearchIgnoresCaseAndAccentsAndReadsTheModuleAndTheSite() {
        let entry = line(0, .warn, "Layout", "Résumé refused",
                         site: LogSite(file: "LayoutEngine.swift", line: 88, function: "refuse(_:)"))
        XCTAssertTrue(LogSearch.matches(entry, "resume"))
        XCTAssertTrue(LogSearch.matches(entry, "REFUSED"))
        XCTAssertTrue(LogSearch.matches(entry, "layout"))
        XCTAssertTrue(LogSearch.matches(entry, "LayoutEngine.swift:88"))
        XCTAssertTrue(LogSearch.matches(entry, "refuse(_:)"))
        XCTAssertFalse(LogSearch.matches(entry, "vpn"))
    }

    func testABlankQueryMatchesEverythingAndIsNotActive() {
        XCTAssertTrue(LogSearch.matches(line(0), ""))
        XCTAssertTrue(LogSearch.matches(line(0), "   "))
        XCTAssertFalse(LogSearch.isActive(" \n"))
        XCTAssertTrue(LogSearch.isActive(" a "))
    }

    // MARK: - What the page draws

    /// Two launches across midnight, the first with a burst and a repeated
    /// warning, the second with an error.
    private func tail() -> [LogEntry] {
        let warn = { (t: Double) in self.line(t, .warn, "layout", "no accessibility grant") }
        return [start(0, "0.11.1-dev.13"),
                line(0.1), line(0.2, .info, "memory", "module.vpn.enable: +336 KB"),
                line(30, .info, "vpn", "network state changed"),
                warn(40), warn(41), warn(42),
                line(43_000, .info, "memory", "sample: 143 MB"),         // the next day
                start(50_000, "0.11.1-dev.14"),
                line(50_000.1),
                line(50_100, .error, "uninstaller", "trash refused",
                     site: LogSite(file: "HelmTrash.swift", line: 140, function: "remove()"))]
    }

    private func build(_ lines: [LogEntry], level: LogLevel = .info, categories: Set<String> = [],
                       query: String = "") -> LogPresentation {
        LogPresentation.build(lines, minimumLevel: level, categories: categories, query: query,
                              language: "en", calendar: utc)
    }

    func testWithNoFilterEveryLaunchIsACardAndTheLinesAreTheTail() {
        let lines = tail()
        let page = build(lines)

        XCTAssertEqual(page.cards.count, 2)
        XCTAssertEqual(page.launchCount, 2)
        XCTAssertEqual(ids(page.lines), ids(lines), "Copy must hand back the file's lines, expanded")
        guard page.cards.count == 2 else { return }
        XCTAssertEqual(page.cards[0].startup.reduce(0) { $0 + $1.repeats }, 2)
        XCTAssertEqual(page.cards[0].rows.map(\.repeats), [1, 3, 1],
                       "the three warnings in a row are one row with a count")
        XCTAssertEqual(page.newestID, page.cards[1].rows.last?.id)
    }

    func testACardCountsItsWholeLaunchWhateverTheFiltersLeave() {
        let page = build(tail(), level: .error)

        XCTAssertEqual(page.cards.count, 1, "the launch with no error is not drawn under Errors")
        XCTAssertEqual(page.launchCount, 2)
        guard page.cards.count == 1, let first = build(tail(), level: .warn).cards.first else {
            return XCTFail("the filters drew \(page.cards.count) card(s) under Errors and none under Warnings")
        }
        XCTAssertEqual(first.warnings, 3, "lines, not runs: three warnings written are three")
        XCTAssertEqual(first.errors, 0)
        XCTAssertEqual(page.cards[0].errors, 1)
    }

    /// Warnings means warnings and worse, so the error's launch is drawn too; each
    /// card's own start line rides along in the copy because it names the version.
    func testAFilterKeepsTheHeaderInTheCopyAndTheBurstOutOfIt() {
        let lines = tail()
        let page = build(lines, level: .warn)

        XCTAssertEqual(page.cards.count, 2)
        XCTAssertEqual(ids(page.lines), ids([lines[0], lines[4], lines[5], lines[6], lines[8], lines[10]]),
                       "the warnings and the error, and the start line of each launch they are in")
        guard page.cards.count == 2 else { return }
        XCTAssertTrue(page.cards[0].startup.isEmpty, "information is not warnings, burst or no")
    }

    func testALaunchWithNothingUnderTheFilterIsNotDrawnAndNoStartLineIsCopied() {
        let page = build(tail(), categories: ["uninstaller"])

        XCTAssertEqual(page.cards.count, 1)
        guard page.cards.count == 1 else { return }
        XCTAssertEqual(page.cards[0].session.version, "0.11.1-dev.14")
        XCTAssertEqual(page.lines.map(\.message), ["Helm 0.11.1-dev.14 started", "trash refused"])
    }

    func testTheBurstIsSearchableAndTheStartLineIsNotAFinding() {
        let page = build(tail(), query: "336")

        XCTAssertEqual(page.cards.count, 1)
        guard page.cards.count == 1 else { return }
        XCTAssertEqual(page.cards[0].startup.map(\.first.message), ["module.vpn.enable: +336 KB"])
        XCTAssertTrue(page.cards[0].rows.isEmpty)
        XCTAssertEqual(page.lines.count, 2, "the start line and the one line that matched")
    }

    /// A line this app did not write is drawn whole, as its own row, in the
    /// place it was written — never merged with its neighbour, never cut.
    func testAnUnreadableLineIsARowOfItsOwnAndWhole() {
        let text = "Helm-OLD-FORMAT half-written line without a stamp or level (kept whole)"
        let stray = LogEntry(date: base.addingTimeInterval(31), level: .info, category: "", message: text)
        let lines = [start(0), line(30, .info, "vpn", "a"), stray, line(32, .info, "vpn", "a")]

        guard let rows = build(lines).cards.first?.rows else { return XCTFail("the page drew no card") }

        XCTAssertEqual(rows.map(\.repeats), [1, 1, 1], "the unreadable line folded into a neighbour")
        guard rows.count == 3 else { return }
        XCTAssertEqual(rows[1].first.message, text)
        XCTAssertEqual(rows[1].first.category, "")
    }

    func testAFreshLaunchWithOnlyItsStartLineIsDrawnUnfilteredAndNotUnderAFilter() {
        let fresh = [start(0)]
        XCTAssertEqual(build(fresh).cards.count, 1)
        XCTAssertEqual(build(fresh).lines.count, 1)
        XCTAssertEqual(build(fresh, level: .warn).cards.count, 0)
    }

    /// A launch that runs across midnight says so where it happens, and the
    /// first row of a card never opens with a heading of its own: the card's
    /// header names the day it began.
    func testADayHeadingAppearsInsideACardWhereTheLaunchCrossesMidnight() {
        let lines = [start(0), line(30, .info, "vpn", "a"),
                     line(43_000, .info, "vpn", "b"),      // more than 11 h later: the next day in UTC
                     line(43_010, .info, "vpn", "c")]
        // 1_790_000_000 is 14:13:20 UTC, so +43 000 s is 02:10:00 the next day.
        guard let card = build(lines).cards.first else { return XCTFail("the page drew no card") }

        XCTAssertEqual(card.rows.map { $0.heading == nil }, [true, false, true],
                       "headings: \(card.rows.map { $0.heading ?? "-" })")
        guard card.rows.count == 3 else { return }
        XCTAssertEqual(card.rows[1].heading, HelmDates.day(lines[2].date, language: "en"))
    }

    // MARK: - Words

    func testTheFooterSaysHowManyAndWhereTheTailBeginsInEveryLanguage() {
        let lines = tail()
        let page = build(lines)
        AppLanguage.each { language in
            let text = LogView.footerCounts(page, entries: lines, storedLog: false)
            XCTAssertTrue(text.contains(HelmDates.dayAndMinute(lines[0].date)),
                          "\(language): the footer does not date the tail's start: \(text)")
            XCTAssertTrue(text.contains("\(lines.count)"), "\(language): no line count in \(text)")
            XCTAssertFalse(text.contains(AppStr.logOlderInFile),
                           "\(language): a short log claims older lines in the file")
        }
    }

    func testOlderLinesAreClaimedOnlyOfAFullTailWithAFileBehindIt() {
        XCTAssertFalse(LogView.olderLinesExist(entryCount: HelmLog.tailLimit - 1, storedLog: true))
        XCTAssertFalse(LogView.olderLinesExist(entryCount: HelmLog.tailLimit, storedLog: false))
        XCTAssertTrue(LogView.olderLinesExist(entryCount: HelmLog.tailLimit, storedLog: true))
        let full = (0..<HelmLog.tailLimit).map { line(Double($0)) }
        AppLanguage.each { language in
            let text = LogView.footerCounts(build(full), entries: full, storedLog: true)
            XCTAssertTrue(text.hasSuffix(AppStr.logOlderInFile), "\(language): \(text)")
        }
    }

    func testAnEmptyTailHasNoCounts() {
        XCTAssertEqual(LogView.footerCounts(build([]), entries: [], storedLog: true), "")
    }

    func testTheCountedWordsTakeTheirNumberAndTheirFormInEveryLanguage() {
        AppLanguage.each { language in
            for n in [1, 2, 5, 11, 21, 1024] {
                for text in [AppStr.logStartup(n), AppStr.logErrorCount(n), AppStr.logWarningCount(n),
                             AppStr.logLaunches(n, n + 3)] {
                    XCTAssertTrue(text.contains(Count(n)), "\(language) \(n): \(text)")
                    XCTAssertFalse(text.contains("%"), "\(language) \(n): \(text)")
                }
            }
        }
        // English keeps one and many apart; the languages that have a form for
        // it keep it apart too, so «1 warnings» is nowhere.
        AppLanguage.only(.en) {
            XCTAssertEqual(AppStr.logWarningCount(1), "1 warning")
            XCTAssertEqual(AppStr.logWarningCount(2), "2 warnings")
            XCTAssertEqual(AppStr.logErrorCount(1), "1 error")
            XCTAssertEqual(AppStr.logStartup(1), "Starting modules · 1 line")
            XCTAssertEqual(AppStr.logStartup(8), "Starting modules · 8 lines")
            XCTAssertEqual(AppStr.logLaunches(1, 1), "1 of 1 launch")
            XCTAssertEqual(AppStr.logLaunches(2, 12), "2 of 12 launches")
        }
        // Russian has three forms, and the count in front of them picks one.
        AppLanguage.only(.ru) {
            XCTAssertEqual(AppStr.logWarningCount(1), "1 предупреждение")
            XCTAssertEqual(AppStr.logWarningCount(2), "2 предупреждения")
            XCTAssertEqual(AppStr.logWarningCount(5), "5 предупреждений")
            XCTAssertEqual(AppStr.logWarningCount(11), "11 предупреждений")
            XCTAssertEqual(AppStr.logWarningCount(21), "21 предупреждение")
            XCTAssertEqual(AppStr.logErrorCount(2), "2 ошибки")
            XCTAssertEqual(AppStr.logErrorCount(5), "5 ошибок")
            XCTAssertEqual(AppStr.logStartup(8), "Старт модулей · строк: 8")
        }
    }

    func testTheNewWordsExistInEveryLanguageAndAreNotEnglishOutsideEnglish() {
        var english: [String] = []
        AppLanguage.only(.en) {
            english = [AppStr.logSearch, AppStr.logEarlierLaunch, AppStr.logOlderInFile]
        }
        XCTAssertEqual(english, ["Search the log", "Earlier launch", "older lines are in the file"])
        AppLanguage.each { language in
            let words = [AppStr.logSearch, AppStr.logEarlierLaunch, AppStr.logOlderInFile]
            for (word, plain) in zip(words, english) {
                XCTAssertFalse(word.isEmpty, "\(language)")
                if language != .en { XCTAssertNotEqual(word, plain, "\(language): \(word)") }
            }
        }
    }

    // MARK: - A launch card keeps its identity and its words
    //
    // What the repair of the launch cards has to hold that the findings' own tests
    // do not say: the head of a rolling tail keeps one identity, a run that starts
    // on an unanswered «logging enabled» is not a launch of the version above it,
    // a repeat across midnight names its day in its tooltip.

    private func networkLine(_ seconds: Double, _ level: LogLevel = .info, _ category: String = "vpn",
                             _ message: String = "network state changed; re-reading") -> LogEntry {
        LogEntry(date: base.addingTimeInterval(seconds), level: level, category: category,
                 message: message)
    }

    private func buildAtDefaults(_ lines: [LogEntry]) -> LogPresentation {
        LogPresentation.build(lines, minimumLevel: .info, categories: [], query: "",
                              language: "en", calendar: utc)
    }

    /// A full tail that is one long launch: each tick the oldest line goes and
    /// one arrives, and the card must be the same card — a new identity is a card
    /// torn down and built whole every second.
    func testTheHeadOfARollingTailIsOneCard() {
        let all = (0..<300).map { networkLine(Double($0)) }
        let ids = (0..<50).map { dropped in
            buildAtDefaults(Array(all[dropped..<(dropped + 200)])).cards.map(\.id)
        }
        XCTAssertEqual(Set(ids.map { $0.count }), [1])
        XCTAssertEqual(Set(ids.flatMap { $0 }).count, 1, "the head card changed identity as the tail rolled")
    }

    /// The constant names the head and only the head: a later run that has no
    /// start line keeps its own first line's identity, so two cards never share.
    func testOnlyTheHeadSharesTheFixedIdentity() {
        let lines = [networkLine(0), networkLine(1, .info, "app", "terminating"), networkLine(2), networkLine(3)]
        let cards = buildAtDefaults(lines).cards
        XCTAssertEqual(cards.count, 2)
        guard cards.count == 2 else { return }
        XCTAssertEqual(Set(cards.map(\.id)).count, 2)
        XCTAssertEqual(cards[1].id, lines[2].id)
    }

    func testAnUnansweredLoggingEnabledOpensARunWithNoVersion() {
        let lines = [networkLine(0, .info, "app", "Helm 0.10.0 started"), networkLine(1), networkLine(2),
                     networkLine(3, .info, "app", "logging enabled"), networkLine(4, .warn, "layout", "declined")]
        let sessions = LogSessions.split(lines)
        XCTAssertEqual(sessions.count, 2, "the split changed: \(sessions.map(\.version))")
        guard sessions.count == 2 else { return }
        XCTAssertEqual(sessions.map(\.version), ["0.10.0", nil])
        XCTAssertEqual(sessions[1].lines.count, 2)
        XCTAssertEqual(sessions.flatMap(\.lines).map(\.id), lines.map(\.id))
    }

    func testAnAnsweredLoggingEnabledStaysInItsLaunch() {
        let lines = [networkLine(0, .info, "app", "Helm 0.10.0 started"),
                     networkLine(1, .info, "app", "logging disabled"),
                     networkLine(2, .info, "app", "logging enabled"), networkLine(3)]
        XCTAssertEqual(LogSessions.split(lines).map(\.version), ["0.10.0"])
    }

    func testTheTooltipNamesTheDayOnlyWhenTheRunCrossedIt() {
        let same = LogPresentation.Row(lines: [networkLine(0), networkLine(60)], heading: nil)
        let across = LogPresentation.Row(lines: [networkLine(35_000), networkLine(35_300)], heading: nil)
        XCTAssertFalse(utc.isDate(across.first.date, inSameDayAs: across.last.date))
        XCTAssertEqual(LogRowView.repeatedUntil(same, calendar: utc), HelmDates.logTime(same.last.date))
        XCTAssertEqual(LogRowView.repeatedUntil(across, calendar: utc),
                       HelmDates.dayAndMinute(across.last.date))
    }

    func testTheFooterCountsEveryLineWhenNothingIsFiltered() {
        let lines = [networkLine(0, .info, "app", "Helm 0.11.0 started"), networkLine(1), networkLine(2, .warn),
                     networkLine(100, .info, "app", "Helm 0.11.1 started"), networkLine(101)]
        let page = buildAtDefaults(lines)
        XCTAssertEqual(page.shown, lines.count)
        XCTAssertEqual(page.lines.count, lines.count)
    }

    // MARK: - The header search under every language
    //
    // The Log page's search as it reads a card's header: the header rule in
    // every language, a query typed the way a keyboard types it, a query in
    // another case or with blanks around it, a query that names one card's
    // header and another card's line; and the split, fed three «terminating»
    // lines in a row and a run an older build opened with a bare «logging
    // enabled».
    //
    // The rule under test (`LogSearch.matches(header:_:drawnTime:)`): a header
    // finds its card only by what it says whole — the version, «Helm <version>»,
    // or the day and minute as drawn.
    //
    // Each case holds a rule, and its assertion message says what a person would
    // see if the rule broke.

    private func networkStart(_ seconds: Double, _ version: String) -> LogEntry {
        networkLine(seconds, .info, "app", "Helm \(version) started")
    }

    private func buildInLanguage(_ lines: [LogEntry], query: String, language: AppLanguage) -> LogPresentation {
        LogPresentation.build(lines, minimumLevel: .info, categories: [], query: query,
                              language: language.rawValue, calendar: utc)
    }

    /// What a keyboard produces for a drawn string: every blank a plain space.
    /// Foundation's short time style puts a narrow no-break space (U+202F)
    /// before «PM» in English, and no key on a Mac keyboard types one.
    private func typed(_ drawn: String) -> String {
        String(String.UnicodeScalarView(drawn.unicodeScalars.map {
            $0.properties.isWhitespace ? " " : $0
        }))
    }

    // MARK: - The header rule in every language

    /// **The day and minute as a person types them find the card, in every
    /// language.** The rule is «the day and minute as drawn, whole»; the tests
    /// that hold it build the query from `HelmDates.dayAndMinute` itself, so
    /// both sides read one declaration. A person reads the header and types it:
    /// in English the drawn string is «9/21/26, 2:13 PM» with a narrow no-break
    /// space before «PM», and the keyboard types an ordinary one — so the
    /// comparison reads every blank as a plain space (`LogSearch.plainBlanks`).
    /// The header is not selectable, so it cannot be copied instead.
    ///
    /// A card with no version is the case the time search exists for (it has
    /// no version to search by), so the fixture's card is the run after
    /// «terminating». The control: the drawn string itself finds the card.
    func testTheDayAndMinuteAsAKeyboardTypesThemFindTheirCardInEveryLanguage() {
        let lines = [networkStart(0, "0.11.1-dev.13"), networkLine(10),
                     networkLine(20, .info, "app", "terminating"),
                     networkLine(7_200, .info, "memory", "sample: 88 MB (+65 MB) — no phases running")]
        let split = LogSessions.split(lines)
        guard split.count == 2, let headless = split.last else {
            return XCTFail("the fixture split into \(split.count) card(s), not 2")
        }
        XCTAssertNil(headless.version, "the fixture's second card has a version")
        var unreachable: [String] = []
        AppLanguage.each { language in
            let drawn = HelmDates.dayAndMinute(headless.lines[0].date)
            XCTAssertEqual(buildInLanguage(lines, query: drawn, language: language).cards.map(\.id), [headless.id],
                           "\(language.rawValue): the control — the drawn «\(drawn)» did not find its card")
            let keyboard = typed(drawn)
            let found = buildInLanguage(lines, query: keyboard, language: language).cards.map(\.id)
            if found != [headless.id] {
                let odd = drawn.unicodeScalars.filter { $0.properties.isWhitespace && $0 != " " }
                    .map { String(format: "U+%04X", $0.value) }
                unreachable.append("\(language.rawValue): «\(keyboard)» found \(found.count) card(s); "
                                   + "the header draws \(odd) where the keyboard types a space")
            }
        }
        XCTAssertTrue(unreachable.isEmpty, """
            the day and minute typed as a person reads them off the header find no card — \
            \(unreachable.joined(separator: "; "))
            """)
    }

    /// **Case and blanks around a whole header do not change what it finds, in
    /// every language.** The version in capitals, «helm» in lower case, a query
    /// with a space or a tab around it — each is the whole header and finds the
    /// one card; a doubled space inside is not the drawn words and finds none.
    func testAWholeHeaderInAnotherCaseOrWithBlanksAroundItFindsItsCardInEveryLanguage() {
        let lines = [networkStart(0, "0.11.1-dev.13"), networkLine(10),
                     networkStart(100, "0.11.1-dev.14"), networkLine(110)]
        AppLanguage.each { language in
            let lang = language.rawValue
            for query in ["0.11.1-DEV.14", "helm 0.11.1-dev.14", "HELM 0.11.1-Dev.14",
                          "  Helm 0.11.1-dev.14 ", "\tHelm 0.11.1-dev.14\n"] {
                XCTAssertEqual(buildInLanguage(lines, query: query, language: language).cards.map(\.session.version),
                               ["0.11.1-dev.14"], "\(lang): «\(query)» did not find the one card it names")
            }
            let drawn = HelmDates.dayAndMinute(lines[0].date)
            for query in [drawn.uppercased(), drawn.lowercased(), " \(drawn)  "] {
                XCTAssertEqual(buildInLanguage(lines, query: query, language: language).cards.map(\.session.version),
                               ["0.11.1-dev.13"], "\(lang): «\(query)» did not find the card drawn «\(drawn)»")
            }
            // Not the drawn words: nothing is found, and nothing header-only is drawn.
            let page = buildInLanguage(lines, query: "Helm  0.11.1-dev.14", language: language)
            XCTAssertTrue(page.cards.isEmpty, "\(lang): a doubled space inside matched \(page.cards.count) card(s)")
        }
    }

    /// **A query that is one card's header and another card's line draws
    /// both, each for what it matched.** «0.11.0» is the version of the first
    /// card and a word in a line of the second: the first is drawn with no row
    /// (its header matched), the second with that line and no other; the copy
    /// carries both start lines and the one line; the footer counts the first
    /// card's start line (it says «0.11.0» itself) and the line — two.
    func testAQueryThatIsOneCardsHeaderAndAnotherCardsLineDrawsBoth() {
        let lines = [networkStart(0, "0.11.0"), networkLine(10),
                     networkStart(100, "0.12.0"), networkLine(110),
                     networkLine(120, .warn, "updates", "skipped 0.11.0: already installed"),
                     networkLine(130)]
        AppLanguage.each { language in
            let lang = language.rawValue
            let page = buildInLanguage(lines, query: "0.11.0", language: language)
            XCTAssertEqual(page.cards.map(\.session.version), ["0.11.0", "0.12.0"],
                           "\(lang): the header match and the line match did not both draw")
            guard page.cards.count == 2 else { return }
            XCTAssertTrue(page.cards[0].rows.isEmpty && page.cards[0].startup.isEmpty,
                          "\(lang): the card found by its header drew a line that does not say «0.11.0»")
            XCTAssertEqual(page.cards[1].rows.flatMap(\.lines).map(\.message) + page.cards[1].startup.flatMap(\.lines).map(\.message),
                           ["skipped 0.11.0: already installed"], "\(lang)")
            XCTAssertEqual(page.lines.map(\.message),
                           ["Helm 0.11.0 started", "Helm 0.12.0 started", "skipped 0.11.0: already installed"],
                           "\(lang): the copy")
            XCTAssertEqual(page.shown, 2, "\(lang): the footer")
        }
    }

    // MARK: - The split

    /// **Three «terminating» in a row stay with the launch they end**, and the
    /// first other line after them opens a run of its own; a «terminating»
    /// that follows some other line is not a pair and stays where it is.
    func testThreeTerminatingLinesInARowStayWithTheLaunchTheyEnd() {
        let quit = { (at: Double) in self.networkLine(at, .info, "app", "terminating") }
        let three = [networkStart(0, "0.11.1-dev.14"), networkLine(0.1), quit(600), quit(600.049), quit(600.1),
                     networkStart(900, "0.11.1-dev.15"), networkLine(900.1)]
        XCTAssertEqual(LogSessions.split(three).map(\.lines.count), [5, 2],
                       "three «terminating» lines drew a card of their own")
        let orphan = [networkStart(0, "0.11.1-dev.14"), quit(600), quit(600.049), quit(600.1),
                      networkLine(601, .info, "memory", "sample")]
        XCTAssertEqual(LogSessions.split(orphan).map(\.lines.count), [4, 1])
        let apart = [networkStart(0, "0.11.1-dev.14"), quit(600), networkLine(601, .info, "memory", "sample"), quit(700)]
        XCTAssertEqual(LogSessions.split(apart).map(\.lines.count), [2, 2],
                       "a «terminating» after another run's line left that run")
        // A tail that begins on the pair: its head card holds all three.
        let head = [quit(600), quit(600.049), quit(600.1), networkStart(900, "0.11.1-dev.15")]
        XCTAssertEqual(LogSessions.split(head).map(\.lines.count), [3, 1])
    }

    /// **A run an older build opened with a bare «logging enabled» is not
    /// joined by a newer build's «logging enabled (version)».** Builds before
    /// the version was written spelled the on edge bare; a build that writes
    /// «logging enabled (0.12.0)» is newer than any build that wrote a bare
    /// one, and a version change is a relaunch. So a versioned on edge
    /// answering a «logging disabled» in a run a bare line opened is another
    /// launch's — decidable from the file, unlike a bare on edge after a
    /// versioned run, which is left whole (`LogSessions.opensNewRun`). This is
    /// the shape of one file that straddles the update on a stable Mac that had
    /// logging switched on by hand: the old build's run, then today's.
    func testARunABareLoggingEnabledOpenedIsNotJoinedByAVersionedOne() {
        let lines = [networkStart(0, "0.10.0"), networkLine(10), networkLine(20, .info, "app", "terminating"),
                     networkLine(3_600, .info, "app", "logging enabled"),
                     networkLine(3_610, .warn, "vpn", "yesterday's warning"),
                     networkLine(3_620, .info, "app", "logging disabled"),
                     networkLine(90_000, .info, "app", "logging enabled (0.12.0)"),
                     networkLine(90_010, .warn, "vpn", "today's warning")]
        let split = LogSessions.split(lines)
        let holding = split.first { $0.lines.contains { $0.message == "today's warning" } }
        XCTAssertFalse(holding?.lines.contains { $0.message == "yesterday's warning" } ?? true, """
            today's warning, written by 0.12.0, shares a card with the run an older build opened \
            with a bare «logging enabled» a day earlier: the card holds \
            \(holding?.lines.map(\.message) ?? []) and its badge counts \
            \(holding?.count(of: .warn) ?? 0) warnings for one launch
            """)
    }

    // MARK: - Another language's clock, an exact build, an older warning

    /// **The day and minute as another language draws them find no card.** The
    /// header draws its time in the app's language, and the rule is «as
    /// drawn»: under German «21.09.26, 19:13» is on the card and «9/21/26, 7:13 PM»
    /// is not, so a query copied from a report written in another language
    /// must draw no header-only card, while the page's own spelling finds it.
    /// Both sides are spelled with the language named outright, and the page is
    /// built the way `LogView` builds it — the language and calendar defaulted.
    /// The subject is asserted first: at least one pair of languages spells the
    /// same moment differently, or the negative half proves nothing.
    func testTheDayAndMinuteAsAnotherLanguageDrawsThemFindNoCard() {
        let lines = [networkStart(0, "0.11.1-dev.13"), networkLine(10),
                     networkLine(20, .info, "app", "terminating"),
                     networkLine(7_200, .info, "memory", "sample: 88 MB (+65 MB) — no phases running")]
        let split = LogSessions.split(lines)
        guard split.count == 2, let headless = split.last, let launch = split.first else {
            return XCTFail("the fixture split into \(split.count) card(s), not 2")
        }
        var differing = 0
        var wrong: [String] = []
        AppLanguage.each { language in
            for session in [launch, headless] {
                let moment = session.lines[0].date
                let own = HelmDates.dayAndMinute(moment, language: language.rawValue)
                let page = LogPresentation.build(lines, minimumLevel: .info, categories: [], query: own)
                if page.cards.map(\.id) != [session.id] {
                    wrong.append("\(language.rawValue): its own «\(own)» found \(page.cards.count) card(s)")
                }
                for other in AppLanguage.allCases where other != language {
                    let foreign = HelmDates.dayAndMinute(moment, language: other.rawValue)
                    guard foreign.compare(own, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
                    else { continue }
                    differing += 1
                    let found = LogPresentation.build(lines, minimumLevel: .info, categories: [],
                                                      query: foreign).cards.count
                    if found != 0 {
                        wrong.append("\(language.rawValue): «\(foreign)» (as \(other.rawValue) draws it) "
                                     + "found \(found) card(s) over a header that draws «\(own)»")
                    }
                }
            }
        }
        XCTAssertGreaterThan(differing, 0, "no two languages spell the moment differently — nothing was tried")
        XCTAssertTrue(wrong.isEmpty, wrong.joined(separator: "; "))
    }

    /// **An exact build with a `-dev` suffix is found whole, and its
    /// neighbours by prefix are not.** «0.11.1-dev.1» is a prefix of
    /// «0.11.1-dev.14» and «0.11.1» of both; each names exactly one card. A
    /// part that is no card's whole version finds none, and the version still
    /// draws its header-only card under a level filter, which the start line
    /// alone never earns.
    func testAnExactDevVersionFindsItsCardAndNotTheCardsItPrefixes() {
        let versions = ["0.11.1", "0.11.1-dev.1", "0.11.1-dev.14", "0.11.1-dev.140"]
        var lines: [LogEntry] = []
        for (index, version) in versions.enumerated() {
            lines += [networkStart(Double(index) * 100, version), networkLine(Double(index) * 100 + 10)]
        }
        XCTAssertEqual(LogSessions.split(lines).map(\.version), versions, "the fixture's split changed")
        AppLanguage.each { language in
            let lang = language.rawValue
            for version in versions {
                for query in [version, "Helm \(version)", version.uppercased()] {
                    XCTAssertEqual(buildInLanguage(lines, query: query, language: language).cards.map(\.session.version),
                                   [version], "\(lang): «\(query)»")
                }
            }
            for query in ["0.11.1-dev", "-dev.14", "dev.14", "0.11.1-dev.14.", "Helm0.11.1-dev.14",
                          "v0.11.1-dev.14"] {
                let page = buildInLanguage(lines, query: query, language: language)
                XCTAssertTrue(page.cards.isEmpty, """
                    \(lang): «\(query)» drew \(page.cards.map { $0.session.version ?? "nil" }) — no card's \
                    header says it whole and no line holds it as a row
                    """)
            }
            let filtered = LogPresentation.build(lines, minimumLevel: .warn, categories: [],
                                                  query: "0.11.1-dev.14", language: lang, calendar: utc)
            XCTAssertEqual(filtered.cards.map(\.session.version), ["0.11.1-dev.14"],
                           "\(lang): under «Warnings» the named build drew no card")
            XCTAssertEqual(filtered.shown, 0, "\(lang): under «Warnings» the footer counts a line nobody sees")
        }
    }

    /// **A warning with no site that quotes a start line is drawn, not hidden in
    /// a header.** Builds before `v0.7.2-dev.1` wrote a warning with no source
    /// site (`git tag --contains f008e352`, the commit that added it), and a
    /// crash that tears a warning cuts its site off: either way the entry has
    /// no site, so the reading that tells a glued start from a quote cannot tell
    /// them apart (it can for `warn` and `error` lines that carry one). Such an
    /// entry is read as a launch, and its header draws a day, a minute and a
    /// version, never the warning's words — so a start line that carries a
    /// warning is the card's first row as well (`LogSession.startIsARow`). Held:
    /// the card's badge counts no warning that no row on it shows, and under
    /// «Warnings» every warning of the tail is on a row.
    ///
    /// Two shapes, both site-less: an older build's warning quoting a copied
    /// start line, and a warning a crash tore, glued to the next launch's
    /// start (read through `LogSeed`, as the page reads it).
    func testAWarningWithNoSiteGluedToOrQuotingAStartLineIsStillDrawn() {
        let zone = TimeZone(identifier: "UTC")!
        let quoted = "2026-09-21 14:25:00.000 [info] [app] Helm 9.9.9 started"
        let older = [networkStart(0, "0.9.0"), networkLine(10),
                     networkLine(60, .warn, "autopilot", "refused a file named \(quoted)"),
                     networkLine(120)]
        let torn = "2026-09-21 14:13:20.000 [info] [app] Helm 0.11.1-dev.13 started\n"
            + "2026-09-21 14:20:00.000 [warn] [vpn] never connected after 30 s  (VPNEngi"   // the crash
            + "2026-09-21 14:25:00.000 [info] [app] Helm 0.11.1-dev.14 started\n"
            + "2026-09-21 14:25:00.100 [info] [host] enable vpn\n"
            + "2026-09-21 14:30:00.000 [info] [vpn] network state changed; re-reading\n"
        let seeded = LogSeed.entries(from: torn, startedMidFile: false, dated: base,
                                     using: LogSeed.Stamps(timeZone: zone))
        XCTAssertEqual(seeded.count, 4, "the parse itself changed: \(seeded.map(\.message))")
        var hidden: [String] = []
        for (shape, lines) in [("an older build's quoting warning", older), ("a torn warning", seeded)] {
            let warnings = lines.filter { $0.level == .warn }
            XCTAssertEqual(warnings.count, 1, "\(shape): the fixture holds \(warnings.count) warnings")
            XCTAssertTrue(warnings.allSatisfy { $0.site == nil }, "\(shape): the warning has a site")
            let page = buildInLanguage(lines, query: "", language: .en)
            for card in page.cards {
                let drawn = (card.startup + card.rows).flatMap(\.lines).filter { $0.level == .warn }.count
                if card.warnings != drawn {
                    hidden.append("\(shape): the card «Helm \(card.session.version ?? "nil")» says "
                                  + "\(card.warnings) warning(s) and draws \(drawn)")
                }
            }
            let underWarnings = LogPresentation.build(lines, minimumLevel: .warn, categories: [], query: "",
                                                      language: "en", calendar: utc)
            let rows = Set(underWarnings.cards.flatMap { ($0.startup + $0.rows).flatMap(\.lines) }.map(\.id))
            for warning in warnings where !rows.contains(warning.id) {
                hidden.append("\(shape): under «Warnings» «\(warning.message.prefix(40))…» is on no row "
                              + "(\(underWarnings.cards.count) card(s) drawn)")
            }
        }
        XCTAssertTrue(hidden.isEmpty, """
            a warning read as a launch's header is counted and not shown — \(hidden.joined(separator: "; "))
            """)
    }

    // MARK: - Launches under inputs nobody fed
    //
    // The launch cards of the Log page, at the edges of these inputs: a launch
    // whose logging was switched on after it started, lines written after a
    // launch said it was terminating, a repeat that runs across midnight, a line
    // torn by a crash, a line nobody can read inside the start-up burst, two
    // starts in one millisecond, a tail rolling over under an open fold, and the
    // footer read beside the badges.
    //
    // Each case holds a rule the cards must keep, and its assertion message says
    // what a person would see if the rule broke.
    //
    // The sequences are the owner's own log's shapes, redacted and re-timed:
    // `helm.previous.log` line 961 is «[app] logging enabled» two minutes after
    // «[app] terminating», with no start line between them, and the owner's two
    // files hold 24 places where lines follow «terminating» before the next start.

    private func launchLine(_ seconds: Double, _ level: LogLevel = .info, _ category: String = "vpn",
                            _ message: String = "network state changed; re-reading",
                            site: LogSite? = nil) -> LogEntry {
        LogEntry(date: base.addingTimeInterval(seconds), level: level, category: category,
                 message: message, site: site)
    }

    private func launchStart(_ seconds: Double, _ version: String) -> LogEntry {
        launchLine(seconds, .info, "app", "Helm \(version) started")
    }

    /// The card a line is drawn in, by the line's id.
    private func card(holding entry: LogEntry, in page: LogPresentation) -> LogPresentation.Card? {
        page.cards.first { $0.session.lines.contains { $0.id == entry.id } }
    }

    private let grant = LogSite(file: "LayoutEngine.swift", line: 214, function: "startTap()")

    // MARK: - A launch is not a process

    /// **A stable build with logging off at launch writes no start line.** The
    /// person follows the page's own advice — turn it on before reporting a
    /// problem — and `setEnabled(true)` writes «logging enabled» and nothing
    /// that names the launch. Everything they then reproduce is filed under the
    /// last launch that *did* log: another version, another day, and the copy
    /// they paste into the report carries that launch's start line as its
    /// header.
    ///
    /// A real `HelmLog`, seeded from a file holding yesterday's launch of an
    /// older version — the shape of `helm.previous.log:926–961` on the owner's
    /// Mac, where a 0.9.0 session's two hours sit under «Helm 0.9.0-dev.14».
    ///
    /// Twice: yesterday's launch said «terminating», and yesterday's launch
    /// crashed and said nothing — two rules in the split, one shape each.
    func testALaunchWhoseLoggingWasSwitchedOnLaterIsNotFiledUnderAnotherVersion() throws {
        for ended in ["terminating", "crashed"] {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("helm-T6-tester-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let yesterday = Date().addingTimeInterval(-86_400)
            let file = folder.appendingPathComponent("helm.log")
            var earlier = [
                LogEntry(date: yesterday, level: .info, category: "app", message: "Helm 0.10.0 started"),
                LogEntry(date: yesterday.addingTimeInterval(0.1), level: .info, category: "host",
                         message: "enable vpn"),
                LogEntry(date: yesterday.addingTimeInterval(300), level: .info, category: "memory",
                         message: "sample: 88 MB (+65 MB) — no phases running"),
            ]
            if ended == "terminating" {
                earlier.append(LogEntry(date: yesterday.addingTimeInterval(600), level: .info,
                                        category: "app", message: "terminating"))
            }
            try (LogLine.lines(earlier) + "\n").write(to: file, atomically: true, encoding: .utf8)

            let log = HelmLog(seedFiles: [file])
            log.start(version: "0.11.0", override: false)   // stable, logging off: no start line
            log.setEnabled(true)                              // «More actions → Write a log file», pressed today
            log.warn("layout", "gesture declined: the layouts have no shared reading")

            let entries = log.recentEntries()
            let today = try XCTUnwrap(entries.last, "\(ended): the log handed back nothing")
            XCTAssertEqual(today.message, "gesture declined: the layouts have no shared reading",
                           "\(ended): the fixture did not reach the tail: \(entries.map(\.message))")

            let page = build(entries)
            let holder = try XCTUnwrap(card(holding: today, in: page))
            XCTAssertNotEqual(holder.session.version, "0.10.0", """
                \(ended): today's warning, written by a 0.11.0 whose logging was switched on after \
                launch, is drawn under yesterday's card «Helm 0.10.0» — the card's badge counts it \
                as that launch's warning, and «Copy log» pastes «Helm 0.10.0 started» above it
                """)
            XCTAssertFalse(holder.session.lines.contains { $0.id == earlier.first?.id }, """
                \(ended): the lines of today's session share a card with yesterday's start line
                """)
            // What «Copy log» takes under «Warnings»: the drawn cards' own start
            // lines and today's warning — never yesterday's start line above it.
            let copied = build(entries, level: .warn).lines
            XCTAssertTrue(copied.contains { $0.id == today.id }, "\(ended): today's warning is not in the copy")
            XCTAssertFalse(copied.contains { $0.message == "Helm 0.10.0 started" }, """
                \(ended): «Copy log» under «Warnings» pastes «Helm 0.10.0 started» above a warning \
                0.11.0 wrote: \(copied.map(\.message))
                """)
        }
    }

    /// **«Logging disabled» is not answered by another process's «logging
    /// enabled».** The ordinary way a stable build comes to have logging off:
    /// the person switches it off in a launch that was writing, which writes
    /// «logging disabled» and nothing after it — «terminating» is not written
    /// either, because the log is off by then. The next launch, maybe days
    /// later, writes no start line; switching logging back on writes «logging
    /// enabled», and the line directly above it in the file is the earlier
    /// launch's «logging disabled». The rule that keeps an off-and-on inside one
    /// launch together reads that pair as one launch too.
    ///
    /// Both launches are real `HelmLog`s; the earlier one's lines are moved a
    /// day back and handed to the later one as its file.
    func testLoggingSwitchedOffInOneLaunchAndOnInTheNextIsTwoLaunches() throws {
        let earlierLog = HelmLog(seedFiles: [])
        earlierLog.start(version: "0.10.0", override: true)
        earlierLog.info("host", "enable vpn")
        earlierLog.setEnabled(false)                     // «More actions → Write a log file», switched off
        earlierLog.info("host", "written by nobody: logging is off")
        let written = earlierLog.recentEntries()
        XCTAssertEqual(written.map(\.message), ["Helm 0.10.0 started", "enable vpn", "logging disabled"],
                       "the earlier launch did not write the shape this test is about")
        let earlier = written.map {
            LogEntry(date: $0.date.addingTimeInterval(-86_400), level: $0.level,
                     category: $0.category, message: $0.message, site: $0.site)
        }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-T6-tester-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("helm.log")
        try (LogLine.lines(earlier) + "\n").write(to: file, atomically: true, encoding: .utf8)

        let log = HelmLog(seedFiles: [file])
        log.start(version: "0.11.0", override: false)   // the saved «off»: no start line
        log.setEnabled(true)                              // switched back on, today
        log.warn("layout", "gesture declined: the layouts have no shared reading")

        let entries = log.recentEntries()
        let today = try XCTUnwrap(entries.last)
        XCTAssertEqual(today.message, "gesture declined: the layouts have no shared reading",
                       "the fixture did not reach the tail: \(entries.map(\.message))")

        let holder = try XCTUnwrap(card(holding: today, in: build(entries)))
        XCTAssertNotEqual(holder.session.version, "0.10.0", """
            today's warning, written by a 0.11.0 that switched logging back on, is drawn under \
            yesterday's card «Helm 0.10.0»: «logging enabled» sat directly under the earlier \
            launch's «logging disabled» and was read as its answer — the badge counts it for \
            0.10.0 and «Copy log» pastes «Helm 0.10.0 started» above it
            """)
    }

    /// **Lines after «terminating» are not the terminated launch's.** Two
    /// builds share one folder (`HelmLog.directory` does not read the bundle
    /// id), so Helm and Helm Dev running side by side interleave — and a
    /// process that has said it is terminating writes nothing more. What
    /// follows it before the next start line belongs to some other process.
    /// The owner's log has 24 of these, e.g. `helm.log` at 2026-09-30
    /// 16:25:50 «terminating» followed ten seconds later by a memory sample.
    func testLinesAfterALaunchSaidItWasTerminatingAreNotThatLaunchs() throws {
        let stranger = launchLine(700, .warn, "layout", "no accessibility grant — not watching", site: grant)
        let lines = [launchStart(0, "0.11.1-dev.14"), launchLine(0.1, .info, "host", "enable vpn"),
                     launchLine(300), launchLine(600, .info, "app", "terminating"),
                     launchLine(610, .info, "memory", "sample: 88 MB (+65 MB) — no phases running"),
                     stranger]

        let page = build(lines)
        let holder = try XCTUnwrap(card(holding: stranger, in: page))

        XCTAssertNotEqual(holder.session.version, "0.11.1-dev.14", """
            a warning written ten seconds after «Helm 0.11.1-dev.14» said it was terminating is \
            drawn inside that launch's card and counted in its badge (\(holder.warnings) \
            warning(s)): the page names a version for a line it has no way to know the version of
            """)
    }

    /// **A crash that tears the last line does not swallow the next launch.** A write
    /// cut short has no newline, so the next launch's start line is appended
    /// to the same line of the file; the seed reads that as one line — here
    /// with a module name that is half a stamp — and no start line survives,
    /// so — unless the glued pair is read as the launch it is — the launch after
    /// the crash, the one somebody opened the page for, is drawn inside the card
    /// of the launch that crashed.
    func testALineTornByACrashDoesNotSwallowTheNextLaunch() {
        let torn = "2026-09-21 14:13:20.000 [info] [app] Helm 0.11.1-dev.13 started\n"
            + "2026-09-21 14:13:20.100 [info] [host] enable vpn\n"
            + "2026-09-21 14:20:00.000 [info] [ho"                          // the crash
            + "2026-09-21 14:25:00.000 [info] [app] Helm 0.11.1-dev.14 started\n"
            + "2026-09-21 14:25:00.100 [info] [host] enable vpn\n"
            + "2026-09-21 14:26:00.000 [warn] [vpn] never connected  (VPNEngine.swift:512 poll())\n"
        let entries = LogSeed.entries(from: torn, startedMidFile: false, dated: base,
                                      using: LogSeed.Stamps(timeZone: TimeZone(identifier: "UTC")!))
        XCTAssertEqual(entries.count, 5, "the parse itself changed: \(entries.map(\.message))")

        let versions = LogSessions.split(entries).map(\.version)

        XCTAssertEqual(versions, ["0.11.1-dev.13", "0.11.1-dev.14"], """
            the launch after a torn line is not a card of its own: \(versions.map { $0 ?? "nil" }) — \
            its warning is drawn under dev.13, and the joined line reads as module \
            «\(entries.count > 2 ? entries[2].category : "?")»
            """)
    }

    /// **A tear can fall anywhere in the line, and on any line.** The repair
    /// reads a start line glued to an `info` line torn inside its `[category]`;
    /// a write cut short stops at whatever byte it reached, the message is most
    /// of a line, and the line before a crash is as likely a warning as not.
    /// Every cut point of an ordinary line and of a warning is tried, and the
    /// launch after the crash must be a card of its own at each.
    func testALaunchAfterALineTornAtAnyByteIsACardOfItsOwn() {
        let next = "2026-09-21 14:25:00.000 [info] [app] Helm 0.11.1-dev.14 started"
        let stamps = LogSeed.Stamps(timeZone: TimeZone(identifier: "UTC")!)
        var report: [String] = []
        var lostAll = 0
        for victim in [
            "2026-09-21 14:20:00.000 [info] [memory] sample: 88 MB (+65 MB) — no phases running",
            "2026-09-21 14:20:00.000 [warn] [vpn] never connected after 30 s  (VPNEngine.swift:512 poll())",
        ] {
            var lost: [String] = []
            for cut in 1..<victim.count {
                let torn = "2026-09-21 14:13:20.000 [info] [app] Helm 0.11.1-dev.13 started\n"
                    + String(victim.prefix(cut)) + next + "\n"
                    + "2026-09-21 14:26:00.000 [warn] [vpn] never connected  (VPNEngine.swift:512 poll())\n"
                let entries = LogSeed.entries(from: torn, startedMidFile: false, dated: base, using: stamps)
                XCTAssertEqual(entries.count, 3, "cut \(cut): the parse itself changed")
                let versions = LogSessions.split(entries).map(\.version)
                if versions != ["0.11.1-dev.13", "0.11.1-dev.14"] {
                    lost.append("…\(victim.prefix(cut).suffix(6))|")
                }
            }
            lostAll += lost.count
            report.append("\(lost.count) of \(victim.count - 1) cuts of «\(victim.dropFirst(24).prefix(14))…» "
                          + "(first \(lost.prefix(2)), last \(lost.suffix(1)))")
        }
        XCTAssertEqual(lostAll, 0, """
            the launch after a torn line is drawn inside the crashed launch's card: \
            \(report.joined(separator: "; "))
            """)
    }

    // MARK: - The fold

    /// **An unreadable line inside the start-up burst is not folded away.** A line
    /// this app did not write takes the date of the line above it, and its
    /// level is `info`, so one written during start-up is inside the burst's
    /// two seconds and folds under «Starting modules» — shut by default. The
    /// burst already ends at a warning so the fold cannot hide one; the line a
    /// crash left behind is the other thing it must not hide.
    func testAnUnreadableLineEndsTheBurstLikeAWarningDoes() throws {
        let stray = LogEntry(date: base.addingTimeInterval(0.2), level: .info, category: "",
                             message: "Helm-OLD-FORMAT half-written line without a stamp or level")
        let lines = [launchStart(0, "0.11.1-dev.14"), launchLine(0.1, .info, "host", "enable vpn"),
                     launchLine(0.2, .info, "memory", "module.vpn.enable: +336 KB"), stray,
                     launchLine(0.3, .info, "host", "enable keep-awake"), launchLine(30)]

        let card = try XCTUnwrap(build(lines).cards.first)

        XCTAssertFalse(card.startup.contains { $0.lines.contains { $0.id == stray.id } }, """
            the unreadable line is inside the shut start-up fold of \
            \(card.startup.reduce(0) { $0 + $1.repeats }) lines: the page shows it only to \
            somebody who opens the fold
            """)
        XCTAssertTrue(card.rows.contains { $0.lines.contains { $0.id == stray.id } },
                      "the unreadable line is not a row of the card")
    }

    /// Open fold, then the tail rolls over: the fold stays open while the start
    /// line is in the tail, because the card is its start line's id.
    func testARollingTailKeepsAnOpenFoldOpenUntilItsStartLineLeaves() {
        let head = (0..<5).map { launchLine(Double($0) - 100, .info, "memory", "sample \($0)") }
        let launch = [launchStart(0, "0.11.1-dev.14")]
            + (1...6).map { launchLine(Double($0) * 0.1, .info, "host", "enable \($0)") }
            + (0..<5).map { launchLine(Double(60 + $0), .info, "vpn", "tick \($0)") }
        let all = head + launch
        let opened: Set<LogEntry.ID> = [launch[0].id]

        for dropped in 0...head.count {
            let page = build(Array(all.dropFirst(dropped)))
            guard let card = page.cards.last else {
                XCTFail("dropped \(dropped): no card at all"); continue
            }
            XCTAssertEqual(card.id, launch[0].id, "dropped \(dropped): the launch's card changed identity")
            XCTAssertTrue(LogView.startupIsOpen(card.id, opened: opened, query: ""),
                          "dropped \(dropped): the fold the person opened shut by itself")
            XCTAssertEqual(card.startup.reduce(0) { $0 + $1.repeats }, 6, "dropped \(dropped)")
        }
        // The start line itself rolls out: the launch is an earlier one now,
        // and its burst lines are ordinary rows — none lost.
        let rolled = Array(all.dropFirst(head.count + 1))
        let page = build(rolled)
        XCTAssertEqual(page.cards.count, 1)
        XCTAssertFalse(page.cards.first?.session.opensWithLaunch ?? true)
        XCTAssertEqual(ids(page.lines), ids(rolled))
    }

    /// **The head card changes identity once, when its start line rolls out,
    /// and no two cards ever share one.** A window rolls one line at a time over
    /// a launch that ends in «terminating», a run of somebody else's lines after
    /// it, an unanswered «logging enabled» and a second launch. The card holding
    /// any one line may be named by its launch's start line and then, once that
    /// has rolled out and the card is the tail's head, by the one fixed identity
    /// — two names over its whole life, never a new one per tick; and at every
    /// step every card on the page has a name of its own, because two cards
    /// under one identity are one view to `ForEach`.
    func testTheHeadCardChangesIdentityOnceAsTheTailRollsPastItsStart() {
        var all = [launchStart(0, "0.11.0")]
        all += (1..<40).map { launchLine(Double($0), .info, "host", "line \($0)") }
        all.append(launchLine(40, .info, "app", "terminating"))
        all += (41..<50).map { launchLine(Double($0), .info, "memory", "foreign \($0)") }
        all.append(launchLine(50, .info, "app", "logging enabled"))
        all += (51..<60).map { launchLine(Double($0), .warn, "layout", "declined \($0)") }
        all.append(launchStart(60, "0.11.1"))
        all += (61..<120).map { launchLine(Double($0), .info, "vpn", "tick \($0)") }
        let width = 30

        var names: [LogEntry.ID: [LogEntry.ID]] = [:]   // line → the card ids it was drawn under
        var shared: [String] = []
        for offset in 0...(all.count - width) {
            let page = build(Array(all[offset..<(offset + width)]))
            let cardIDs = page.cards.map(\.id)
            if Set(cardIDs).count != cardIDs.count { shared.append("offset \(offset): \(page.cards.count) cards") }
            for card in page.cards {
                for entry in card.session.lines where names[entry.id]?.last != card.id {
                    names[entry.id, default: []].append(card.id)
                }
            }
        }
        XCTAssertEqual(shared, [], "two cards shared one identity")
        let renamed = all.enumerated().filter { (names[$0.element.id]?.count ?? 0) > 2 }
        XCTAssertEqual(renamed.map(\.offset), [], """
            a card holding these lines was renamed more than twice as the tail rolled — a new card \
            per tick: \(renamed.prefix(3).map { names[$0.element.id]!.count })
            """)
        // The subject happened: the first launch's lines were drawn under their
        // start line's name and then under the head's.
        XCTAssertEqual(names[all[20].id]?.first, all[0].id)
        XCTAssertEqual(names[all[20].id]?.count, 2, "the first launch's card never became the tail's head")
    }

    // MARK: - A repeat across midnight, and never across a launch

    /// **A repeat that runs across midnight does not hide the day it crossed
    /// into.** The run is one row, headed (if at all) by its first line's day;
    /// the row after it is compared with the run's *first* line, so a heading
    /// says the day changed — compared with its *last* line, which is already on
    /// the new day, none would, and the rows below would read as the day before.
    func testARepeatAcrossMidnightStillNamesTheNewDay() {
        // 1_790_000_000 is 14:13:20 UTC; +35 000 s is 23:56:40, +35 300 is 00:01:40.
        let lines = [launchStart(0, "0.11.1-dev.14"), launchLine(60),
                     launchLine(35_000, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     launchLine(35_100, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     launchLine(35_300, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     launchLine(35_400, .info, "memory", "sample: 123 MB (-20 MB) — no phases running")]
        XCTAssertFalse(utc.isDate(lines[3].date, inSameDayAs: lines[4].date),
                       "the fixture does not cross midnight")

        let rows = build(lines).cards.first?.rows ?? []

        // Which row carries it is the fix's to choose; that one does is not.
        // Presence, not the spelling: the heading is spelled in this Mac's zone
        // and decided here in UTC.
        XCTAssertEqual(rows.map(\.repeats), [1, 3, 1], "the fixture's fold changed")
        XCTAssertTrue(rows.contains { $0.heading != nil }, """
            the launch ran into the next day through a ×3 run (23:56:40 → 00:01:40 UTC), and no \
            row inside its card says the day changed: headings \(rows.map { $0.heading ?? "-" })
            """)
    }

    /// Two launches whose last and first lines say the same thing are two
    /// rows, never one ×2 — under «All» and under «Warnings», where the fold
    /// runs over what is shown.
    func testARepeatNeverFoldsAcrossALaunch() {
        let lines = [launchStart(0, "0.11.1-dev.13"),
                     launchLine(60, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     launchStart(120, "0.11.1-dev.14"),
                     launchLine(180, .warn, "layout", "no accessibility grant — not watching", site: grant)]
        for level in [LogLevel.info, .warn] {
            let page = build(lines, level: level)
            XCTAssertEqual(page.cards.count, 2, "\(level)")
            XCTAssertEqual(page.cards.flatMap(\.rows).map(\.repeats), [1, 1],
                           "\(level): a repeat folded across a launch")
        }
    }

    // MARK: - Starts

    /// Two starts in one millisecond — a launch that failed at once and was
    /// relaunched, or two builds started together — are two cards, each its own.
    func testTwoStartsInOneMillisecondAreTwoLaunches() {
        let lines = [launchStart(0, "0.11.1-dev.13"), launchStart(0, "0.11.1-dev.14"), launchLine(0), launchLine(0.001)]

        let sessions = LogSessions.split(lines)

        XCTAssertEqual(sessions.map(\.version), ["0.11.1-dev.13", "0.11.1-dev.14"])
        guard sessions.count == 2 else { return }
        XCTAssertEqual(sessions[0].lines.count, 1)
        XCTAssertEqual(sessions[1].startupCount, 2)
        XCTAssertEqual(ids(build(lines).lines), ids(lines))
        XCTAssertEqual(Set(build(lines).cards.map(\.id)).count, 2, "two cards share an identity")
    }

    /// The version is whatever the bundle said, and the page does not judge it:
    /// an older release's form, a bundle that would not say (`AppDelegate`
    /// writes «0»), a suffix nobody planned.
    func testAStartLineInAnyVersionFormIsAStart() {
        for version in ["0.9.0", "0.9.0-dev.11", "0", "1.0 (beta)", "0.11.1-dev.14+local",
                        "０.１１"] {
            XCTAssertEqual(LogSessions.version(of: launchStart(0, version)), version, version)
        }
    }

    // MARK: - What the footer and the badges say

    /// **Under «Warnings» the footer counts the lines on the page.** Its shown
    /// count is not the copy set, which carries each drawn card's start line:
    /// one launch with thirteen warnings would read «13 warnings» on its card
    /// and «14 of … lines» under it, and nothing on the page is the fourteenth.
    func testUnderWarningsTheFooterCountsWhatTheBadgesCount() {
        var lines = [launchStart(0, "0.11.1-dev.14"), launchLine(0.1, .info, "host", "enable vpn")]
        for index in 0..<12 {
            lines.append(launchLine(60 + Double(index), .warn, "layout",
                              "no accessibility grant — not watching", site: grant))
        }
        lines.append(launchLine(90, .warn, "vpn", "never connected"))
        lines.append(launchLine(95))
        let page = build(lines, level: .warn)
        let badged = page.cards.reduce(0) { $0 + $1.warnings + $1.errors }
        XCTAssertEqual(badged, 13)

        AppLanguage.only(.en) {
            let footer = LogView.footerCounts(page, entries: lines, storedLog: false)
            XCTAssertTrue(footer.contains(AppStr.logCount(badged, lines.count)), """
                the card says «\(AppStr.logWarningCount(badged))» and the footer says «\(footer)»
                """)
        }
    }

    // MARK: - Finding a card by its header, and a second «terminating» line

    /// **The version on a card is searchable.** The header shows
    /// «Helm 0.11.1-dev.14»; the start line alone is the header and never a
    /// row, so a search that matched only lines would say nothing matches while
    /// the words are on screen.
    func testSearchingForTheVersionOnACardFindsThatCard() {
        let lines = [launchStart(0, "0.11.1-dev.13"), launchLine(10),
                     launchStart(100, "0.11.1-dev.14"), launchLine(110)]

        let page = build(lines, query: "0.11.1-dev.14")

        XCTAssertEqual(page.cards.map(\.session.version), ["0.11.1-dev.14"], """
            a search for the version drawn on a card found \(page.cards.count) card(s) — the page \
            says nothing matches
            """)
    }

    /// **The time drawn on a card with no version is searchable.** A search
    /// finds a card by what its header draws — the version, and the day and
    /// minute — and not only on a card that has a version: a card with no start
    /// line (the tail's head, the run after «terminating», the run after an
    /// unanswered «logging enabled») draws the day and minute of its first line
    /// too, and a search for exactly those words finds it.
    func testSearchingForTheTimeOnACardWithNoVersionFindsThatCard() {
        let lines = [launchStart(0, "0.11.1-dev.13"), launchLine(10),
                     launchLine(20, .info, "app", "terminating"),
                     launchLine(7_200, .info, "memory", "sample: 88 MB (+65 MB) — no phases running")]
        guard let headless = build(lines).cards.last else { return XCTFail("the fixture drew no card") }
        XCTAssertNil(headless.session.version, "the fixture's split changed")
        AppLanguage.only(.en) {
            let opened = HelmDates.dayAndMinute(lines[0].date)
            XCTAssertEqual(build(lines, query: opened).cards.map(\.session.version), ["0.11.1-dev.13"],
                           "the control: a search for the time on the card with a version did not find it")
            let drawn = HelmDates.dayAndMinute(headless.session.lines[0].date)
            XCTAssertFalse(lines.contains { LogSearch.matches($0, drawn) }, "a line itself says «\(drawn)»")
            let page = build(lines, query: drawn)
            XCTAssertEqual(page.cards.map(\.id), [headless.id], """
                a search for «\(drawn)», the time drawn on the card after «terminating», found \
                \(page.cards.count) card(s) — the same search finds a card that has a version
                """)
        }
    }

    /// **A part of a header is not a finding.** The header of a card is found
    /// by what it says *whole* — the version, «Helm <version>», the day and
    /// minute as drawn — and by nothing shorter: «Helm» is on every card, «PM»
    /// on half of them and «0.11» on all, so a part of a header drew every
    /// launch of the tail as a card with no line in it (measured on the owner's
    /// log: «Helm» → 800 empty cards of 821). A card whose *lines* match is
    /// drawn for its lines, whatever the word.
    func testAPartOfAHeaderDoesNotDrawAHeaderOnlyCardForEveryLaunch() {
        AppLanguage.only(.en) {
            let lines = [launchStart(0, "0.11.1-dev.13"), launchLine(10),
                         launchStart(100, "0.11.1-dev.14"), launchLine(110),
                         launchStart(200, "0.11.1-dev.15"), launchLine(210, .info, "vpn", "a Helm-shaped word")]
            let time = HelmDates.dayAndMinute(lines[0].date)
            for part in ["Helm", "0.11", "dev", String(time.suffix(2)), "0.11.1-dev.1"] {
                let page = build(lines, query: part)
                let headerOnly = page.cards.filter { $0.rows.isEmpty && $0.startup.isEmpty }
                XCTAssertTrue(headerOnly.isEmpty, """
                    a search for «\(part)», a part of what the headers draw, drew \(headerOnly.count) \
                    card(s) that hold no line
                    """)
            }
            XCTAssertEqual(build(lines, query: "Helm").cards.count, 1,
                           "the one line that says «Helm» is drawn in its own card")
            // The whole of a header still finds its card.
            XCTAssertEqual(build(lines, query: "Helm 0.11.1-dev.14").cards.map(\.session.version),
                           ["0.11.1-dev.14"])
            XCTAssertEqual(build(lines, query: "0.11.1-DEV.14").cards.map(\.session.version),
                           ["0.11.1-dev.14"], "the whole version, in another case, is still the version")
            XCTAssertEqual(build(lines, query: time).cards.map(\.session.version), ["0.11.1-dev.13"],
                           "the day and minute as drawn, whole, found a different set of cards")
        }
    }

    /// **Two «terminating» lines in a row are one launch's end.** Two builds
    /// that quit one after the other write «terminating» twice, 49 ms apart in
    /// the owner's own log; the second line has no launch of its own, and a
    /// card of one line headed «Earlier launch» sat between two real launches.
    /// A «terminating» that follows a «terminating» stays with the launch it
    /// ends; the first line after them still opens a run of its own.
    func testASecondTerminatingLineStaysWithTheLaunchItEnds() {
        let lines = [launchStart(0, "0.11.1-dev.14"), launchLine(0.1), launchLine(600, .info, "app", "terminating"),
                     launchLine(600.049, .info, "app", "terminating"),
                     launchStart(900, "0.11.1-dev.15"), launchLine(900.1)]
        let split = LogSessions.split(lines)
        XCTAssertEqual(split.map(\.lines.count), [4, 2], """
            two «terminating» lines in a row drew \(split.map(\.lines.count)) lines per card — a \
            card of one line, with no version, between two launches
            """)
        let orphan = [launchStart(0, "0.11.1-dev.14"), launchLine(600, .info, "app", "terminating"),
                      launchLine(600.049, .info, "app", "terminating"), launchLine(601, .info, "memory", "sample")]
        let orphanSplit = LogSessions.split(orphan)
        XCTAssertEqual(orphanSplit.map(\.lines.count), [3, 1],
                       "a line after the pair is no longer that launch's")
        XCTAssertEqual(orphanSplit.map { $0.version ?? "nil" }, ["0.11.1-dev.14", "nil"])
    }

    // MARK: - The row after a repeat, the on edge, and lines that only look like a start

    /// **The row after a repeat that ran across midnight names its own day.**
    /// The span row «21 Sep – 22 Sep» names the day it ended on; the row after
    /// it is judged against the span's *first* line (`LogPresentation.build`),
    /// so it opens with the new day's heading as well. Held here because the
    /// other leg of the midnight repair — the span — names the new day by
    /// itself, and a comparison moved back to the span's last line passed every
    /// other test in the tree. If a second naming of that day is not wanted,
    /// this test is the one to change, deliberately.
    func testTheRowAfterARepeatAcrossMidnightOpensWithItsOwnDay() {
        // +35 000 s is 23:56:40 UTC, +35 300 is 00:01:40, +35 400 is 00:03:20.
        let lines = [launchStart(0, "0.11.1-dev.14"), launchLine(60),
                     launchLine(35_000, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     launchLine(35_100, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     launchLine(35_300, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     launchLine(35_400, .info, "memory", "sample: 123 MB (-20 MB) — no phases running")]
        XCTAssertTrue(utc.isDate(lines[4].date, inSameDayAs: lines[5].date)
                      && !utc.isDate(lines[2].date, inSameDayAs: lines[5].date),
                      "the fixture's row after the span is not on the span's last day")

        let rows = build(lines).cards.first?.rows ?? []

        XCTAssertEqual(rows.map(\.repeats), [1, 3, 1], "the fixture's fold changed")
        guard rows.count == 3 else { return }
        XCTAssertNotNil(rows[1].heading, "the span row itself lost its heading")
        XCTAssertEqual(rows[2].heading, HelmDates.day(lines[5].date, language: "en"), """
            the row written at 00:03:20 UTC, after a ×3 run that began at 23:56:40 the day \
            before, carries no heading of its own: headings \(rows.map { $0.heading ?? "-" }) — \
            the row above was judged by its last line, not its first
            """)
    }

    /// **The on edge that names a version spells back through the file.** The
    /// version is inside the message — «logging enabled (0.11.0)» — so the seed
    /// must read that line back byte for byte, and the split must cut a seeded
    /// file exactly where it cuts the live tail. Real
    /// `HelmLog`s write both launches; versions with a bracket, a space and two
    /// spaces before a bracket (the site's own opening) are tried. Stable
    /// versions only: a `-dev` build logs from its start line on and its
    /// switch is greyed, so it never writes this line under a «logging
    /// disabled».
    func testLoggingEnabledWithAVersionReadsBackFromTheFileAsItWasWritten() throws {
        let zone = TimeZone(identifier: "UTC")!
        for version in ["0.11.0", "1.0 (beta)", "1.0 beta", "0.11.1+local", "1.0  (5)", "2.0)"] {
            let earlierLog = HelmLog(seedFiles: [])
            earlierLog.start(version: "0.10.0", override: true)
            earlierLog.setEnabled(false)
            let log = HelmLog(seedFiles: [])
            log.start(version: version, override: false)
            log.setEnabled(true)
            log.warn("layout", "gesture declined")
            let live = earlierLog.recentEntries() + log.recentEntries()
            XCTAssertEqual(live.map(\.message), ["Helm 0.10.0 started", "logging disabled",
                                                 "logging enabled (\(version))", "gesture declined"],
                           "\(version): the logs did not write the shape this test is about")

            let text = LogLine.lines(live, timeZone: zone) + "\n"
            let seeded = LogSeed.entries(from: text, startedMidFile: false, dated: base,
                                         using: LogSeed.Stamps(timeZone: zone))
            XCTAssertEqual(seeded.map(\.message), live.map(\.message), "\(version): the seed changed a message")
            XCTAssertEqual(seeded.map { $0.site?.description }, live.map { $0.site?.description },
                           "\(version): the seed moved a site")
            XCTAssertEqual(LogLine.lines(seeded, timeZone: zone) + "\n", text,
                           "\(version): the seeded lines do not spell back to the file")
            XCTAssertEqual(LogSessions.split(seeded).map(\.lines.count), LogSessions.split(live).map(\.lines.count),
                           "\(version): the file is cut where the live tail is not")
            XCTAssertEqual(LogSessions.split(seeded).count, 2, """
                \(version): «logging enabled (\(version))» under 0.10.0's «logging disabled», read \
                back from the file, is filed under 0.10.0: \(LogSessions.split(seeded).map(\.version))
                """)
        }
    }

    /// **A line that quotes a start line is not a launch.** The repair reads a
    /// start line glued onto a torn one wherever the tear fell, which it
    /// recognises as «<stamp> [info] [app] Helm … started» at the end of an
    /// entry. A warning whose message merely ends with those words — a copied
    /// log line, a file named like one — carries a source site, because
    /// `HelmLog.warn` and `HelmLog.error` write one, and a glued start never
    /// can: the start line is written without one and is the end of the glued
    /// entry. (An `info` line has no site, so the same quote there cannot be
    /// told from a tear by the entry alone; that case is not asserted.) Read
    /// through the file, as a seed reads it.
    func testALineThatQuotesAStartLineIsNotALaunch() {
        let zone = TimeZone(identifier: "UTC")!
        let quoted = "2026-09-21 14:25:00.000 [info] [app] Helm 9.9.9 started"
        let lines = [launchStart(0, "0.11.0"), launchLine(0.1, .info, "host", "enable vpn"),
                     launchLine(60, .warn, "autopilot", "refused a file named \(quoted)",
                          site: LogSite(file: "AutopilotEngine.swift", line: 88, function: "run()")),
                     launchLine(120, .warn, "layout", "no accessibility grant — not watching", site: grant)]
        let seeded = LogSeed.entries(from: LogLine.lines(lines, timeZone: zone) + "\n", startedMidFile: false,
                                     dated: base, using: LogSeed.Stamps(timeZone: zone))
        XCTAssertEqual(seeded.map(\.message), lines.map(\.message), "the parse itself changed")
        guard seeded.count == lines.count else { return }
        XCTAssertNotNil(seeded[2].site, "the quoting line lost its site in the parse")

        let versions = LogSessions.split(seeded).map { $0.version ?? "nil" }

        XCTAssertEqual(versions, ["0.11.0"], """
            a line whose message quotes a start line opens a card of its own: \(versions) — the \
            warning after it is drawn under «Helm 9.9.9», a version that never ran, and «Copy log» \
            pastes the quoting warning as that card's header
            """)
    }

    /// **Words that end like a start line without its stamp are not a start.**
    /// The glued start is recognised by the start line's own 23-character
    /// stamp in front of «[info] [app] Helm … started»; an `info` line — which
    /// carries no site to tell it apart — whose message only ends with the
    /// words, as a line about the log itself might, must stay a line of the
    /// launch it was written in. Guarded because moving that stamp test out of
    /// the reading passed every other test in the tree.
    func testAMessageEndingInTheStartWordsWithoutAStampIsNotALaunch() {
        for message in ["copied: [info] [app] Helm 9.9.9 started",
                        "x 2026-09-21 14:25 [info] [app] Helm 9.9.9 started",
                        "[info] [app] Helm 9.9.9 started"] {
            let lines = [launchStart(0, "0.11.0"), launchLine(60, .info, "host", message),
                         launchLine(120, .warn, "layout", "no accessibility grant — not watching", site: grant)]
            let versions = LogSessions.split(lines).map { $0.version ?? "nil" }
            XCTAssertEqual(versions, ["0.11.0"], """
                «\(message)», a line with no stamp before the start words, opens a card: \(versions)
                """)
        }
    }

    /// **A run that its own «logging enabled (version)» opened is that
    /// version's.** A stable build with logging off at launch writes no start
    /// line; switched on, it writes «logging enabled (0.11.0)», which opens a
    /// run of its own. Switched off again, it writes «logging disabled». The
    /// next launch — an update, 0.12.0 — switches it back on, and its
    /// «logging enabled (0.12.0)» sits under that «logging disabled». Compared
    /// with the run's *start line*, which this run does not have, the named
    /// version would find nothing and the two launches would share one card; so
    /// the version the run itself named earlier is the one read.
    func testARunOpenedByItsOwnLoggingEnabledIsNotJoinedByTheNextVersion() throws {
        let first = HelmLog(seedFiles: [])
        first.start(version: "0.11.0", override: false)   // stable, saved «off»: no start line
        first.setEnabled(true)
        first.warn("vpn", "never connected")
        first.setEnabled(false)
        let yesterday = first.recentEntries().map {
            LogEntry(date: $0.date.addingTimeInterval(-86_400), level: $0.level,
                     category: $0.category, message: $0.message, site: $0.site)
        }
        XCTAssertEqual(yesterday.map(\.message),
                       ["logging enabled (0.11.0)", "never connected", "logging disabled"],
                       "the first launch did not write the shape this test is about")

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-T6-tester-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("helm.log")
        try (LogLine.lines(yesterday) + "\n").write(to: file, atomically: true, encoding: .utf8)

        let log = HelmLog(seedFiles: [file])
        log.start(version: "0.12.0", override: false)
        log.setEnabled(true)
        log.warn("layout", "gesture declined: the layouts have no shared reading")

        let entries = log.recentEntries()
        let today = try XCTUnwrap(entries.last)
        XCTAssertEqual(today.message, "gesture declined: the layouts have no shared reading",
                       "the fixture did not reach the tail: \(entries.map(\.message))")
        let holder = try XCTUnwrap(card(holding: today, in: build(entries)))
        XCTAssertFalse(holder.session.lines.contains { $0.message == "logging enabled (0.11.0)" }, """
            today's warning, written by 0.12.0, shares a card with yesterday's 0.11.0 run: the \
            card holds \(holder.session.lines.map(\.message)) and its badge counts \
            \(holder.warnings) warnings for one launch
            """)
    }
}
