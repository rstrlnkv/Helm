import XCTest
@testable import HelmRuntime

/// The log, readable while it is being written.
///
/// The file has always been the record; reading it meant leaving the app,
/// finding `~/Library/Logs/Helm`, and looking at what had already happened. The
/// tail is the same lines kept in memory so a dev build can watch them arrive —
/// and it is deliberately *not* a second log: one `write`, one formatter, one
/// truth, with the tail as a window onto it.
final class LogTailTests: XCTestCase {

    private func entry(_ level: LogLevel, _ category: String, _ message: String,
                       at seconds: TimeInterval = 0) -> LogEntry {
        LogEntry(date: Date(timeIntervalSince1970: seconds), level: level,
                 category: category, message: message)
    }

    // MARK: - The buffer

    /// Bounded, because a diagnostics window must not become the memory bug it
    /// exists to help find. The oldest line goes; the newest is always there.
    func testTheTailIsBoundedAndKeepsTheNewest() {
        var tail = LogTail(limit: 3)
        for line in 1...5 { tail.append(entry(.info, "disk", "line \(line)", at: TimeInterval(line))) }
        XCTAssertEqual(tail.entries.map(\.message), ["line 3", "line 4", "line 5"])
    }

    func testAnEmptyTailIsEmpty() {
        XCTAssertTrue(LogTail(limit: 10).entries.isEmpty)
    }

    /// The seed hands over a whole buffer at once, and the bound is the type's
    /// rather than the caller's: a list arriving by the door `append` does not
    /// use is still a list this must not grow past.
    func testAWholeBufferHandedOverIsBoundedToo() {
        var tail = LogTail(limit: 3)
        tail.replace(with: (1...5).map { entry(.info, "app", "line \($0)", at: TimeInterval($0)) })
        XCTAssertEqual(tail.entries.map(\.message), ["line 3", "line 4", "line 5"])
    }

    // MARK: - Filtering

    private var sample: [LogEntry] {
        [entry(.info, "disk", "scanned", at: 1),
         entry(.warn, "uninstaller", "refused a path", at: 2),
         entry(.error, "vpn", "could not connect", at: 3),
         entry(.info, "uninstaller", "listApps returned 38", at: 4)]
    }

    func testNoFilterShowsEverything() {
        XCTAssertEqual(LogFilter.apply(sample, minimumLevel: .info, categories: []).count, 4)
    }

    /// The question somebody actually opens this for: what went wrong. Warnings
    /// come with it, because a refusal is the warning that precedes the error
    /// somebody is hunting.
    func testWarningsAndAboveDropTheChatter() {
        let kept = LogFilter.apply(sample, minimumLevel: .warn, categories: [])
        XCTAssertEqual(kept.map(\.message), ["refused a path", "could not connect"])
    }

    func testErrorsOnly() {
        XCTAssertEqual(LogFilter.apply(sample, minimumLevel: .error, categories: []).map(\.category),
                       ["vpn"])
    }

    /// One module at a time is how a person reads this: they are watching Disk,
    /// and everything else is noise arriving on top of what they are watching.
    func testOneCategory() {
        let kept = LogFilter.apply(sample, minimumLevel: .info, categories: ["uninstaller"])
        XCTAssertEqual(kept.count, 2)
    }

    func testSeveralCategoriesAtOnce() {
        let kept = LogFilter.apply(sample, minimumLevel: .info, categories: ["disk", "vpn"])
        XCTAssertEqual(kept.map(\.category), ["disk", "vpn"])
    }

    /// Both filters are ANDed: a chosen module still hides its own chatter when
    /// the level says warnings only.
    func testLevelAndCategoryTogether() {
        let kept = LogFilter.apply(sample, minimumLevel: .warn, categories: ["uninstaller"])
        XCTAssertEqual(kept.map(\.message), ["refused a path"])
    }

    /// The category list is built from what has actually arrived, so it names
    /// the modules that spoke rather than the nine that exist — and it is sorted
    /// so the menu does not reshuffle itself as lines come in.
    func testTheCategoriesOfferedAreTheOnesSeen() {
        XCTAssertEqual(LogFilter.categories(in: sample), ["disk", "uninstaller", "vpn"])
    }

    func testTheOrderOfArrivalIsKept() {
        XCTAssertEqual(LogFilter.apply(sample, minimumLevel: .info, categories: []).map(\.message),
                       ["scanned", "refused a path", "could not connect", "listApps returned 38"])
    }
}
