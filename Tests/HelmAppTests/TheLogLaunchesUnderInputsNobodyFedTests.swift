import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The launch cards of the Log page, fed the inputs their own tests did not
/// feed: a launch whose logging was switched on after it started, lines written
/// after a launch said it was terminating, a repeat that runs across midnight,
/// a line torn by a crash, a line nobody can read inside the start-up burst,
/// two starts in one millisecond, a tail rolling over under an open fold, and
/// the footer read beside the badges.
///
/// Each case holds a rule the cards must keep, and its assertion message says
/// what a person would see if the rule broke.
///
/// The sequences are the owner's own log's shapes, redacted and re-timed:
/// `helm.previous.log` line 961 is «[app] logging enabled» two minutes after
/// «[app] terminating», with no start line between them, and the owner's two
/// files hold 24 places where lines follow «terminating» before the next start.
final class TheLogLaunchesUnderInputsNobodyFedTests: XCTestCase {

    /// 14:13:20 UTC on 21 September 2026 — fixed, so nothing reads this Mac's
    /// clock or zone.
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func line(_ seconds: Double, _ level: LogLevel = .info, _ category: String = "vpn",
                      _ message: String = "network state changed; re-reading",
                      site: LogSite? = nil) -> LogEntry {
        LogEntry(date: base.addingTimeInterval(seconds), level: level, category: category,
                 message: message, site: site)
    }

    private func start(_ seconds: Double, _ version: String) -> LogEntry {
        line(seconds, .info, "app", "Helm \(version) started")
    }

    private func build(_ lines: [LogEntry], level: LogLevel = .info, categories: Set<String> = [],
                       query: String = "") -> LogPresentation {
        LogPresentation.build(lines, minimumLevel: level, categories: categories, query: query,
                              language: "en", calendar: utc)
    }

    private func ids(_ lines: [LogEntry]) -> [LogEntry.ID] { lines.map(\.id) }

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
        let stranger = line(700, .warn, "layout", "no accessibility grant — not watching", site: grant)
        let lines = [start(0, "0.11.1-dev.14"), line(0.1, .info, "host", "enable vpn"),
                     line(300), line(600, .info, "app", "terminating"),
                     line(610, .info, "memory", "sample: 88 MB (+65 MB) — no phases running"),
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
        let lines = [start(0, "0.11.1-dev.14"), line(0.1, .info, "host", "enable vpn"),
                     line(0.2, .info, "memory", "module.vpn.enable: +336 KB"), stray,
                     line(0.3, .info, "host", "enable keep-awake"), line(30)]

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
        let head = (0..<5).map { line(Double($0) - 100, .info, "memory", "sample \($0)") }
        let launch = [start(0, "0.11.1-dev.14")]
            + (1...6).map { line(Double($0) * 0.1, .info, "host", "enable \($0)") }
            + (0..<5).map { line(Double(60 + $0), .info, "vpn", "tick \($0)") }
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
        var all = [start(0, "0.11.0")]
        all += (1..<40).map { line(Double($0), .info, "host", "line \($0)") }
        all.append(line(40, .info, "app", "terminating"))
        all += (41..<50).map { line(Double($0), .info, "memory", "foreign \($0)") }
        all.append(line(50, .info, "app", "logging enabled"))
        all += (51..<60).map { line(Double($0), .warn, "layout", "declined \($0)") }
        all.append(start(60, "0.11.1"))
        all += (61..<120).map { line(Double($0), .info, "vpn", "tick \($0)") }
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

    // MARK: - Repeats

    /// **A repeat that runs across midnight does not hide the day it crossed
    /// into.** The run is one row, headed (if at all) by its first line's day;
    /// the row after it is compared with the run's *first* line, so a heading
    /// says the day changed — compared with its *last* line, which is already on
    /// the new day, none would, and the rows below would read as the day before.
    func testARepeatAcrossMidnightStillNamesTheNewDay() {
        // 1_790_000_000 is 14:13:20 UTC; +35 000 s is 23:56:40, +35 300 is 00:01:40.
        let lines = [start(0, "0.11.1-dev.14"), line(60),
                     line(35_000, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     line(35_100, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     line(35_300, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     line(35_400, .info, "memory", "sample: 123 MB (-20 MB) — no phases running")]
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
        let lines = [start(0, "0.11.1-dev.13"),
                     line(60, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     start(120, "0.11.1-dev.14"),
                     line(180, .warn, "layout", "no accessibility grant — not watching", site: grant)]
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
        let lines = [start(0, "0.11.1-dev.13"), start(0, "0.11.1-dev.14"), line(0), line(0.001)]

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
            XCTAssertEqual(LogSessions.version(of: start(0, version)), version, version)
        }
    }

    // MARK: - What the footer and the badges say

    /// **Under «Warnings» the footer counts the lines on the page.** Its shown
    /// count is not the copy set, which carries each drawn card's start line:
    /// one launch with thirteen warnings would read «13 warnings» on its card
    /// and «14 of … lines» under it, and nothing on the page is the fourteenth.
    func testUnderWarningsTheFooterCountsWhatTheBadgesCount() {
        var lines = [start(0, "0.11.1-dev.14"), line(0.1, .info, "host", "enable vpn")]
        for index in 0..<12 {
            lines.append(line(60 + Double(index), .warn, "layout",
                              "no accessibility grant — not watching", site: grant))
        }
        lines.append(line(90, .warn, "vpn", "never connected"))
        lines.append(line(95))
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

    // MARK: - Search

    /// **The version on a card is searchable.** The header shows
    /// «Helm 0.11.1-dev.14»; the start line alone is the header and never a
    /// row, so a search that matched only lines would say nothing matches while
    /// the words are on screen.
    func testSearchingForTheVersionOnACardFindsThatCard() {
        let lines = [start(0, "0.11.1-dev.13"), line(10),
                     start(100, "0.11.1-dev.14"), line(110)]

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
        let lines = [start(0, "0.11.1-dev.13"), line(10),
                     line(20, .info, "app", "terminating"),
                     line(7_200, .info, "memory", "sample: 88 MB (+65 MB) — no phases running")]
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
            let lines = [start(0, "0.11.1-dev.13"), line(10),
                         start(100, "0.11.1-dev.14"), line(110),
                         start(200, "0.11.1-dev.15"), line(210, .info, "vpn", "a Helm-shaped word")]
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
        let lines = [start(0, "0.11.1-dev.14"), line(0.1), line(600, .info, "app", "terminating"),
                     line(600.049, .info, "app", "terminating"),
                     start(900, "0.11.1-dev.15"), line(900.1)]
        let split = LogSessions.split(lines)
        XCTAssertEqual(split.map(\.lines.count), [4, 2], """
            two «terminating» lines in a row drew \(split.map(\.lines.count)) lines per card — a \
            card of one line, with no version, between two launches
            """)
        let orphan = [start(0, "0.11.1-dev.14"), line(600, .info, "app", "terminating"),
                      line(600.049, .info, "app", "terminating"), line(601, .info, "memory", "sample")]
        let orphanSplit = LogSessions.split(orphan)
        XCTAssertEqual(orphanSplit.map(\.lines.count), [3, 1],
                       "a line after the pair is no longer that launch's")
        XCTAssertEqual(orphanSplit.map { $0.version ?? "nil" }, ["0.11.1-dev.14", "nil"])
    }

    // MARK: - Round 3: what the third repair newly touches

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
        let lines = [start(0, "0.11.1-dev.14"), line(60),
                     line(35_000, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     line(35_100, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     line(35_300, .warn, "layout", "no accessibility grant — not watching", site: grant),
                     line(35_400, .info, "memory", "sample: 123 MB (-20 MB) — no phases running")]
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
    /// third repair put the version inside the message — «logging enabled
    /// (0.11.0)» — so the seed must read that line back byte for byte, and the
    /// split must cut a seeded file exactly where it cuts the live tail. Real
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
        let lines = [start(0, "0.11.0"), line(0.1, .info, "host", "enable vpn"),
                     line(60, .warn, "autopilot", "refused a file named \(quoted)",
                          site: LogSite(file: "AutopilotEngine.swift", line: 88, function: "run()")),
                     line(120, .warn, "layout", "no accessibility grant — not watching", site: grant)]
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
            let lines = [start(0, "0.11.0"), line(60, .info, "host", message),
                         line(120, .warn, "layout", "no accessibility grant — not watching", site: grant)]
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
    /// «logging enabled (0.12.0)» sits under that «logging disabled». The repair
    /// compares the named version with the run's *start line*, which this run
    /// does not have; the version the run itself named two lines up is not read,
    /// and the two launches share one card.
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
