import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// What the Log page draws is derived from the lines themselves, in pure
/// functions (`LogSessions`, `LogRepeats`, `LogSearch`, `LogPresentation`) — so
/// the rules that decide where one launch ends and the next begins, what folds
/// and what a filter leaves are held here on fixtures, not on a mounted page.
///
/// The property under everything: **grouping never drops a line and never moves
/// one.** The page's promise is the file's own, and «Copy log» hands back the
/// lines expanded.
final class TheLogSplitsIntoLaunchesTests: XCTestCase {

    /// 14:13:20 UTC on 21 September 2026 — a fixed instant, so nothing here reads
    /// this Mac's clock or zone. (`date -u -r 1790000000`)
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
        let entry = line(0, .warn, "Hosts", "Résumé refused",
                         site: LogSite(file: "HostsEngine.swift", line: 88, function: "refuse(_:)"))
        XCTAssertTrue(LogSearch.matches(entry, "resume"))
        XCTAssertTrue(LogSearch.matches(entry, "REFUSED"))
        XCTAssertTrue(LogSearch.matches(entry, "hosts"))
        XCTAssertTrue(LogSearch.matches(entry, "HostsEngine.swift:88"))
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
}
