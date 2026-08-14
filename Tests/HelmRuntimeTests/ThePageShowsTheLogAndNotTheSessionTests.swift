import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// The page called Log showed this process's tail and nothing else.
///
/// Measured on the owner's own file on 2026-08-14: 5 306 lines over 107 sessions,
/// the last `started` line at 5 222 — so a page opened then drew 45 lines, 0.85 %
/// of the log, under a footer reading «45 of 45 lines». The event somebody came
/// for is almost never in the 45.
///
/// The tail is seeded from the file now, and **the seed is the one place a log
/// line is parsed back apart** — `write` still keeps the parts and hands them
/// over, which is the rule this seed is the stated exception to. Everything below
/// is about that parse: that it is the exact inverse of `LogLine.format`, that a
/// line it cannot read is kept rather than guessed at, and that a file which is
/// missing, empty, huge, half-written or refused are five different answers.
final class ThePageShowsTheLogAndNotTheSessionTests: XCTestCase {

    /// Fixed, so a machine in another zone reads these lines the same way. The
    /// file itself carries no offset, which is a limitation named on `LogSeed`.
    private let utc = TimeZone(identifier: "UTC")!
    private var stamps: LogSeed.Stamps { LogSeed.Stamps(timeZone: utc) }
    /// Whole seconds: the file spells milliseconds and a parse gives them back,
    /// but a round-trip assertion should fail for the reason it was written for
    /// rather than for the last bit of a `Double`.
    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    /// The line the file would carry for this entry — spelled by the app's own
    /// formatter, never by a second copy of the format written here.
    private func line(_ entry: LogEntry) -> String {
        LogLine.format(date: entry.date, level: entry.level, category: entry.category,
                       message: entry.message, site: entry.site, timeZone: utc)
    }

    // MARK: - The parse is the inverse of the format

    /// Both shapes the file holds: an `info` line, and a `warn`/`error` line with
    /// the source site `HelmLog.warn` appends.
    func testALineTheAppWroteParsesBackIntoTheEntryItWasSpelledFrom() {
        let plain = LogEntry(date: stamp, level: .info, category: "app",
                             message: "Helm 0.10.0-dev.6 started")
        let sited = LogEntry(date: stamp, level: .warn, category: "layout",
                             message: "no accessibility grant — not watching",
                             site: LogSite(file: "LayoutEngine.swift", line: 214,
                                           function: "startTap()"))
        assertRoundTrips(plain)
        assertRoundTrips(sited)
    }

    /// The flattened newline survives, because it is part of the message the file
    /// carries — a seeded line has to read as the line in the file.
    func testAFlattenedNewlineComesBackAsItStandsInTheFile() {
        let entry = LogEntry(date: stamp, level: .error, category: "engine",
                             message: "decode failed ⏎ second line")
        assertRoundTrips(entry)
    }

    /// A message that ends in brackets is a message, not a source site. The
    /// discriminator is the site's own shape — `File.swift:12 function()` — so
    /// `HelmFailure.describe`'s parenthesised codes stay where they were written.
    func testAMessageEndingInBracketsIsNotReadAsASourceSite() {
        let entry = LogEntry(date: stamp, level: .error, category: "brew",
                             message: "install refused (exit 2)")
        assertRoundTrips(entry)
        guard case .entry(let back) = LogSeed.parse(line(entry), using: stamps) else {
            return XCTFail("the line did not parse at all")
        }
        XCTAssertNil(back.site, "a bracketed message tail was read as a source site")
    }

    // MARK: - A line the parse cannot read

    /// Kept whole, and told apart from a line the app wrote by saying nothing it
    /// does not know: no category and no level above `info`.
    func testALineTheParseCannotReadIsKeptWholeAndClaimsNoPartsItDoesNotHave() {
        let written = LogEntry(date: stamp, level: .warn, category: "vpn",
                               message: "connect failed")
        let text = [line(written), "*** not a log line ***"].joined(separator: "\n")

        let out = LogSeed.entries(from: text, startedMidFile: false,
                                  dated: .distantPast, using: stamps)

        guard out.count == 2 else {
            return XCTFail("a line the parse could not read was dropped: \(out)")
        }
        XCTAssertEqual(out[1].message, "*** not a log line ***")
        XCTAssertEqual(out[1].category, "", "the seed invented a category for a line with none")
        XCTAssertEqual(out[1].level, .info, "the seed invented a level for a line with none")
        XCTAssertEqual(out[1].date, out[0].date,
                       "an unreadable line belongs where it sits in the file, beside the line "
                       + "above it")
    }

    /// And when it is the first thing in the file there is no line above it, so
    /// the caller's date stands in — the file's own, never now.
    func testAnUnreadableFirstLineTakesTheDateTheCallerGaveIt() {
        let fallback = Date(timeIntervalSince1970: 1_600_000_000)
        let out = LogSeed.entries(from: "half a line", startedMidFile: false,
                                  dated: fallback, using: stamps)

        XCTAssertEqual(out.map(\.message), ["half a line"])
        XCTAssertEqual(out.first?.date, fallback)
    }

    /// A read that began in the middle of the file starts with a fragment of a
    /// line nobody tore — that one is the reader's own doing, and it goes.
    func testAReadThatStartedMidFileDropsItsOwnFirstFragment() {
        let entry = LogEntry(date: stamp, level: .info, category: "app", message: "second")
        let text = ["ll grant — not watching", line(entry)].joined(separator: "\n")

        let whole = LogSeed.entries(from: text, startedMidFile: false,
                                    dated: .distantPast, using: stamps)
        let tail = LogSeed.entries(from: text, startedMidFile: true,
                                   dated: .distantPast, using: stamps)

        XCTAssertEqual(whole.count, 2, "nothing was read at all, so the comparison below is empty")
        XCTAssertEqual(tail.map(\.message), ["second"])
    }

    // MARK: - The file and this process are one list

    /// The file already holds every line this process wrote, so seeding from it
    /// would show each of them twice. What is taken is what came before.
    func testTheSeedStopsWhereThisProcesssOwnLinesBegin() {
        let old = entry("earlier session", at: 1_700_000_000)
        let mine = [entry("this session, first", at: 1_700_000_100),
                    entry("this session, second", at: 1_700_000_200)]
        let file = [old] + mine

        let seeded = LogSeed.seeded(file: file, live: mine, limit: 1000)

        XCTAssertEqual(seeded.map(\.message),
                       ["earlier session", "this session, first", "this session, second"],
                       "a line the process wrote was shown twice, or the file was not read")
    }

    /// Nothing written yet — a build with logging off — takes the whole file.
    func testWithNothingWrittenThisSessionTheWholeTailComesFromTheFile() {
        let file = (0..<3).map { entry("line \($0)", at: 1_700_000_000 + Double($0)) }

        XCTAssertEqual(LogSeed.seeded(file: file, live: [], limit: 1000).map(\.message),
                       ["line 0", "line 1", "line 2"])
    }

    /// The bound is the tail's, over both halves together: the window for finding
    /// memory bugs must not become one.
    func testTheSeededTailIsBoundedAndKeepsTheNewest() {
        let file = (0..<10).map { entry("old \($0)", at: 1_700_000_000 + Double($0)) }
        let live = [entry("new", at: 1_700_001_000)]

        let seeded = LogSeed.seeded(file: file, live: live, limit: 3)

        XCTAssertEqual(seeded.map(\.message), ["old 8", "old 9", "new"])
    }

    // MARK: - The five states a log file can be in

    func testAMissingFileSeedsNothingAndIsNotAnError() {
        let folder = scratchDirectory("log-seed-missing")
        XCTAssertEqual(LogSeed.read([folder.appendingPathComponent("helm.log")],
                                    atMost: 64 * 1024, limit: 1000, using: stamps).count, 0)
    }

    func testAnEmptyFileSeedsNothing() throws {
        let folder = scratchDirectory("log-seed-empty")
        let url = folder.appendingPathComponent("helm.log")
        try Data().write(to: url)

        XCTAssertEqual(LogSeed.read([url], atMost: 64 * 1024, limit: 1000, using: stamps).count, 0)
    }

    /// Bigger than the reader takes: the end is what a person wants, and the
    /// fragment the read starts on is not turned into a line.
    func testAFileBiggerThanTheReadGivesItsEndAndNoFragment() throws {
        let folder = scratchDirectory("log-seed-huge")
        let url = folder.appendingPathComponent("helm.log")
        let lines = (0..<400).map { line(entry("line \($0)", at: 1_700_000_000 + Double($0))) }
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: url)
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        XCTAssertGreaterThan(size, 4096, "the fixture is not bigger than the read below")

        let out = LogSeed.read([url], atMost: 4096, limit: 1000, using: stamps)

        XCTAssertFalse(out.isEmpty, "nothing was read, so the assertions below are about nothing")
        XCTAssertEqual(out.last?.message, "line 399", "the read gave the beginning, not the end")
        XCTAssertLessThan(out.count, 400,
                          "every line of a file larger than the read came back, so the byte "
                          + "bound is not bounding anything — the page reads the whole 2 MB")
        XCTAssertTrue(out.allSatisfy { !$0.category.isEmpty },
                      "the fragment the read started on became a line: \(out.prefix(1))")
    }

    /// The process died mid-write. The half line is somebody's evidence too.
    func testAHalfWrittenLastLineIsKeptRatherThanDiscarded() throws {
        let folder = scratchDirectory("log-seed-torn")
        let url = folder.appendingPathComponent("helm.log")
        let whole = line(entry("whole", at: 1_700_000_000))
        try (whole + "\n" + "2026-08-14 10:00:00.0").data(using: .utf8)!.write(to: url)

        let out = LogSeed.read([url], atMost: 64 * 1024, limit: 1000, using: stamps)

        XCTAssertEqual(out.map(\.message), ["whole", "2026-08-14 10:00:00.0"])
    }

    /// A refused read is not an empty log, and it is not a reason to lose the
    /// half that can be read.
    func testAFileThatCannotBeReadDoesNotTakeTheOtherOneWithIt() throws {
        let folder = scratchDirectory("log-seed-refused")
        let refused = folder.appendingPathComponent("helm.previous.log")
        let readable = folder.appendingPathComponent("helm.log")
        try (line(entry("older", at: 1_700_000_000)) + "\n").data(using: .utf8)!.write(to: refused)
        try (line(entry("newer", at: 1_700_000_100)) + "\n").data(using: .utf8)!.write(to: readable)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: refused.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: refused.path)
        }
        XCTAssertNil(try? String(contentsOf: refused, encoding: .utf8),
                     "this file can still be read, so the assertion below proves nothing")

        let out = LogSeed.read([refused, readable], atMost: 64 * 1024, limit: 1000, using: stamps)

        XCTAssertEqual(out.map(\.message), ["newer"])
    }

    /// Rollover first, then the file being written: the two halves are one list
    /// in the order they happened.
    func testTheRolledOverHalfComesBeforeTheOneBeingWritten() throws {
        let folder = scratchDirectory("log-seed-both")
        let previous = folder.appendingPathComponent("helm.previous.log")
        let current = folder.appendingPathComponent("helm.log")
        try (line(entry("older", at: 1_700_000_000)) + "\n").data(using: .utf8)!.write(to: previous)
        try (line(entry("newer", at: 1_700_000_100)) + "\n").data(using: .utf8)!.write(to: current)

        let out = LogSeed.read([previous, current], atMost: 64 * 1024, limit: 1000, using: stamps)

        XCTAssertEqual(out.map(\.message), ["older", "newer"])
    }

    // MARK: - The log itself

    /// **The page's own first read is what does it**, and nothing else calls the
    /// seed: a log that stopped reading the file at `recentEntries()` would draw
    /// its 45 lines again with every test here still green.
    ///
    /// The log is built with a file of its own because a test process resolves
    /// `seedSources` to nothing on purpose (below), and `shared` may have been
    /// read by an earlier test in this bundle — a first read happens once per
    /// object, so it takes an object of one's own to watch it happen at all.
    func testTheFirstReadShowsWhatWasInTheFileBeforeThisProcessStarted() throws {
        let folder = scratchDirectory("log-seed-live")
        let url = folder.appendingPathComponent("helm.log")
        let earlier = "a line from before this process \(UUID().uuidString)"
        try (line(entry(earlier, at: 1_700_000_000)) + "\n").data(using: .utf8)!.write(to: url)
        let mine = "this session \(UUID().uuidString)"
        let log = HelmLog(seedFiles: [url])
        addTeardownBlock { log.setEnabled(false) }

        log.setEnabled(true)
        log.info("app", mine)
        let entries = log.recentEntries()

        XCTAssertEqual(entries.filter { $0.message == mine }.count, 1,
                       "this session's own line is missing or drawn twice — and if it is "
                       + "missing, nothing below is a test of a seed")
        XCTAssertTrue(entries.contains { $0.message == earlier },
                      "the page is still this process's tail: \(entries.map(\.message))")
    }

    /// And it is a *first* read, not every read. The page asks once a second
    /// while it is open and the seed reads a quarter of a megabyte and parses a
    /// thousand lines on the main thread — 49–78 ms of `DateFormatter` alone
    /// without the minute cache — so a tick that read the file again would spend
    /// a good part of every second on lines it already has.
    ///
    /// Watched through the emptied tail, because that is where a second read
    /// shows: «Clear» empties it, and a page that seeded itself again on the
    /// next tick would put the log straight back on screen. A first read cannot
    /// be told from a second by its result — the merge keeps this session's own
    /// lines either way — so a test that only reads twice passes with the once
    /// deleted.
    func testAClearedPageIsNotFilledFromTheFileAgain() throws {
        let folder = scratchDirectory("log-seed-once")
        let url = folder.appendingPathComponent("helm.log")
        try (line(entry("first", at: 1_700_000_000)) + "\n").data(using: .utf8)!.write(to: url)
        let log = HelmLog(seedFiles: [url])

        XCTAssertEqual(log.recentEntries().map(\.message), ["first"],
                       "the first read did not seed, so the second one below proves nothing")
        log.clearTail()

        XCTAssertEqual(log.recentEntries().map(\.message), [],
                       "the file is read again on every tick — an emptied page fills itself "
                       + "back up from the log it was just cleared of")
    }

    /// **A test process reads no log file**, and the seed says so where the
    /// destination rule is written rather than by a check somewhere in the log.
    /// The test folder is one folder shared by every run, so seeding it would
    /// put the whole history of the suite into the tail of any test that reads
    /// one — measured at 46 copies of a line a KeepAwake test wanted once.
    func testATestProcessSeedsFromNothingAndAShippingOneFromBothHalves() {
        let files = [URL(fileURLWithPath: "/tmp/helm.previous.log"),
                     URL(fileURLWithPath: "/tmp/helm.log")]

        XCTAssertEqual(LogDestination.seedSources(files: files, underTest: false), files)
        XCTAssertEqual(LogDestination.seedSources(files: files, underTest: true), [])
        XCTAssertEqual(HelmLog.seedSources, [],
                       "this process is not resolved as a test run, so every tail in the suite "
                       + "carries the shared test log")
    }

    /// Everything the file line carries reaches the tail — the fifth part was
    /// the one it did not have.
    func testTheTailKeepsTheSourceSiteTheFileLineCarries() {
        addTeardownBlock {
            HelmLog.shared.setEnabled(false)
            HelmLog.shared.clearTail()
        }
        let marker = "site carried \(UUID().uuidString)"

        HelmLog.shared.setEnabled(true)
        HelmLog.shared.warn("engine", marker)
        let written = HelmLog.shared.recentEntries().first { $0.message == marker }

        XCTAssertNotNil(written, "nothing was logged, so the two assertions below are vacuous")
        XCTAssertEqual(written?.site?.file,
                       "ThePageShowsTheLogAndNotTheSessionTests.swift")
        XCTAssertEqual(written?.site?.function,
                       "testTheTailKeepsTheSourceSiteTheFileLineCarries()")
    }

    /// What the button puts on the pasteboard is the line the file carries —
    /// one format, not a second one written at the button.
    func testTheCopiedLineIsTheLineTheFileCarries() {
        let entry = LogEntry(date: stamp, level: .error, category: "vpn",
                             message: "connect failed",
                             site: LogSite(file: "VPNEngine.swift", line: 88,
                                           function: "connect()"))

        let copied = LogLine.line(entry, timeZone: utc)

        XCTAssertEqual(copied, line(entry))
        XCTAssertTrue(copied.contains("[error]"), "the level is not in the copied line: \(copied)")
        XCTAssertTrue(copied.contains("2023-11-14"), "the date is not in the copied line: \(copied)")
        XCTAssertTrue(copied.contains("VPNEngine.swift:88"),
                      "the source site is not in the copied line: \(copied)")
    }

    /// Turning the log off is an event in the log. A file that simply stops
    /// cannot be told from an app that died.
    func testSwitchingTheLogOffIsWrittenBeforeItStops() {
        addTeardownBlock { HelmLog.shared.clearTail() }
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.info("app", "before")
        XCTAssertTrue(HelmLog.shared.recentEntries().contains { $0.message == "before" },
                      "nothing was logged at all, so the line below is not proof of anything")

        HelmLog.shared.setEnabled(false)
        let after = HelmLog.shared.recentEntries()
        HelmLog.shared.info("app", "while off")

        XCTAssertEqual(after.last?.message, "logging disabled",
                       "the log stops without a word: \(after.suffix(3).map(\.message))")
        XCTAssertFalse(HelmLog.shared.recentEntries().contains { $0.message == "while off" },
                       "the switch wrote its own line and then went on logging")
    }

    /// The gate «Clear» is drawn from: a file on disk is a thing to clear even
    /// when this process has written nothing.
    func testAStoredLogCountsAsSomethingToClearWithAnEmptyTail() throws {
        let folder = scratchDirectory("log-clear-gate")
        let previous = folder.appendingPathComponent("helm.previous.log")

        XCTAssertFalse(HelmLog.anyFileExists(among: [previous]))
        try Data("x".utf8).write(to: previous)
        XCTAssertTrue(HelmLog.anyFileExists(among: [previous]),
                      "a rolled-over half on disk reads as nothing to clear")
    }

    // MARK: -

    private func entry(_ message: String, at seconds: TimeInterval) -> LogEntry {
        LogEntry(date: Date(timeIntervalSince1970: seconds), level: .info,
                 category: "app", message: message)
    }

    /// Field by field, with the date to the millisecond the file spells: an
    /// `XCTAssertEqual` on two `Date`s would fail on the last bit of a `Double`
    /// rather than on the thing this is about.
    private func assertRoundTrips(_ entry: LogEntry, file: StaticString = #filePath,
                                  line lineNumber: UInt = #line) {
        guard case .entry(let back) = LogSeed.parse(line(entry), using: stamps) else {
            return XCTFail("«\(line(entry))» did not parse back at all",
                           file: file, line: lineNumber)
        }
        XCTAssertEqual(back.date.timeIntervalSince1970, entry.date.timeIntervalSince1970,
                       accuracy: 0.0005, file: file, line: lineNumber)
        XCTAssertEqual(back.level, entry.level, file: file, line: lineNumber)
        XCTAssertEqual(back.category, entry.category, file: file, line: lineNumber)
        XCTAssertEqual(back.message, entry.message, file: file, line: lineNumber)
        XCTAssertEqual(back.site, entry.site, file: file, line: lineNumber)
    }
}
