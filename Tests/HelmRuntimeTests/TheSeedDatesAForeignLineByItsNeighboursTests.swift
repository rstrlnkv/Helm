import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// Where a line the seed cannot read gets its date, now that one above every
/// readable line no longer takes the file's modification time.
///
/// The Log page heads each run of lines with its day, so an unreadable line's
/// date is a visible claim: dated by the file's modification time it opened a
/// day none of the file's lines was written on. The repair holds such lines
/// back and dates them by the first readable line below. What it must not do on
/// the way is reorder, drop or re-spell anything — `LogSeed` is obliged to be the
/// exact inverse of `LogLine.format`, and a held-back line is exactly the kind of
/// thing that comes out in the wrong place.
final class TheSeedDatesAForeignLineByItsNeighboursTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    private var stamps: LogSeed.Stamps { LogSeed.Stamps(timeZone: utc) }
    /// Newer than every line below, as a file's modification time is.
    private let modified = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ message: String, at seconds: TimeInterval,
                       level: LogLevel = .info) -> LogEntry {
        LogEntry(date: Date(timeIntervalSince1970: 1_700_000_000 + seconds), level: level,
                 category: "app", message: message)
    }

    private func line(_ entry: LogEntry) -> String {
        LogLine.format(date: entry.date, level: entry.level, category: entry.category,
                       message: entry.message, site: entry.site, timeZone: utc)
    }

    /// Foreign lines at the head, in the middle and at the end of a file the app
    /// otherwise wrote: every line comes back once, in file order, the app's own
    /// lines exactly as they were spelled, the foreign ones whole — and each
    /// foreign line carries a date from a readable neighbour, never the file's.
    func testForeignLinesAnywhereComeBackInPlaceDatedByANeighbour() {
        let one = entry("one", at: 0, level: .warn)
        let two = entry("two", at: 60)
        let three = entry("three", at: 7200, level: .error)
        let text = [
            "Helm log, older format",
            "=======================",
            line(one),
            "a torn continuation",
            line(two),
            line(three),
            "half a line the crash left",
            "",
        ].joined(separator: "\n")

        let out = LogSeed.entries(from: text, startedMidFile: false, dated: modified,
                                  using: stamps)

        XCTAssertEqual(out.map(\.message), [
            "Helm log, older format", "=======================", "one",
            "a torn continuation", "two", "three", "half a line the crash left",
        ], "the seed dropped, doubled or reordered a line")
        XCTAssertEqual(out.map(\.date), [
            one.date, one.date, one.date, one.date, two.date, three.date, three.date,
        ], "a foreign line was dated by something other than its readable neighbour")
        XCTAssertFalse(out.contains { $0.date == modified },
                       "a line in a file with readable lines took the file's modification time")
        // The app's own lines are the inverse of their spelling, level and all.
        let own = out.filter { !$0.category.isEmpty }
        XCTAssertEqual(own.map(\.level), [.warn, .info, .error])
        XCTAssertEqual(own.map(\.message), ["one", "two", "three"])
        XCTAssertTrue(out.filter { $0.category.isEmpty }.allSatisfy { $0.level == .info },
                      "a foreign line was given a level it does not carry")
    }

    /// A file with no readable line at all has nothing to borrow from: every
    /// line keeps the caller's date, in order, and none is lost to being held.
    func testAFileWithNothingReadableKeepsEveryLineOnTheCallersDate() {
        let text = "first foreign\nsecond foreign\n\nthird foreign\n"

        let out = LogSeed.entries(from: text, startedMidFile: false, dated: modified,
                                  using: stamps)

        XCTAssertEqual(out.map(\.message), ["first foreign", "second foreign", "third foreign"],
                       "lines held back for a readable line that never came were lost")
        XCTAssertEqual(Set(out.map(\.date)), [modified])
    }

    /// The limit is taken off the top before the parse, so the first line kept
    /// can be the middle of something foreign. It still takes the day of the
    /// readable line under it.
    func testALimitThatCutsIntoForeignLinesDatesWhatIsLeftByTheLineBelow() {
        let kept = entry("kept", at: 3600)
        let text = ["foreign 1", "foreign 2", "foreign 3", line(kept)].joined(separator: "\n")

        let out = LogSeed.entries(from: text, startedMidFile: false, dated: modified,
                                  keepingLast: 3, using: stamps)

        XCTAssertEqual(out.map(\.message), ["foreign 2", "foreign 3", "kept"])
        XCTAssertEqual(Set(out.map(\.date)), [kept.date])
    }

    /// The two halves of the log read as one list: the one being written opens
    /// with a foreign line and must not head itself with its own modification
    /// time; and a seed that stops where this process's own lines begin keeps
    /// the file's lines — dated by the file's time, a foreign first line was
    /// newer than the process's first line and `seeded` stopped before it,
    /// taking every line of the file with it.
    func testTheFileBeingWrittenOpensWithAForeignLineAndStillSeeds() throws {
        let root = scratchDirectory("seed-foreign-head")
        let previous = root.appendingPathComponent("helm.1.log")
        let current = root.appendingPathComponent("helm.log")
        let old = entry("old", at: 0)
        let recent = entry("recent", at: 60)
        try (line(old) + "\n").write(to: previous, atomically: true, encoding: .utf8)
        try ("foreign head\n" + line(recent) + "\n").write(to: current, atomically: true,
                                                            encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified],
                                              ofItemAtPath: current.path)

        let file = LogSeed.read([previous, current], atMost: 64 * 1024, limit: 1000,
                                using: stamps)
        XCTAssertEqual(file.map(\.message), ["old", "foreign head", "recent"])
        XCTAssertEqual(file.map(\.date), [old.date, recent.date, recent.date])

        let mine = [entry("this process started", at: 600)]
        let seeded = LogSeed.seeded(file: file, live: mine, limit: 1000)
        XCTAssertEqual(seeded.map(\.message),
                       ["old", "foreign head", "recent", "this process started"],
                       "the file's lines were cut off at a foreign line dated after this process began")
    }
}
