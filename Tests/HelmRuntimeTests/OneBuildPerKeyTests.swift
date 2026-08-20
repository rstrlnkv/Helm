import XCTest
@testable import HelmRuntime

/// **`LockedMemo` builds once per key, and remembers nothing about a build that
/// found nothing.**
///
/// Four hand-written boxes of one lock and one dictionary were folded into it,
/// and they had already diverged on exactly the first of those two points: three
/// held the lock across the build, and the Layout keyboard-table copy took the
/// lock, missed, *unlocked*, built, and locked again to store — so two threads
/// asking for the same layout both walked fifty keys through Carbon. Benign for
/// an idempotent table, and it is the difference nobody could see by reading one
/// copy, which is why the tally below is a test rather than a sentence.
///
/// The second point is not benign anywhere. A build that comes back empty is a
/// port answering «not now» — a keyboard layout the system has not published
/// yet — and a memo that stored that would answer «absent» for the life of the
/// process, with no channel to say otherwise (CLAUDE.md § Anything that can stop
/// being true on its own).
final class OneBuildPerKeyTests: XCTestCase {

    /// How many times a build ran. `ProgressBox` next door records a *last*
    /// value, which is the other question.
    private final class Builds: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func ran() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    /// The one that catches the divergence: a second caller arriving **while**
    /// the first build is still running gets the first one's answer, rather than
    /// building its own copy.
    ///
    /// Not a sleep race in either direction. The second call is made only after
    /// the build has signalled that it is inside itself, so a memo that released
    /// the lock to build hands the second caller an empty table and it builds —
    /// deterministically two. A memo that holds the lock blocks the second
    /// caller until there is something to find — deterministically one.
    func testASecondCallerDuringABuildDoesNotBuildAgain() {
        let memo = LockedMemo<String, String>()
        let builds = Builds()
        let inside = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = memo.value(for: "layout") {
                inside.signal()
                Thread.sleep(forTimeInterval: 0.2)
                builds.ran()
                return "table"
            }
            done.signal()
        }
        inside.wait()

        XCTAssertEqual(memo.value(for: "layout") { builds.ran(); return "table" }, "table")
        done.wait()

        XCTAssertEqual(builds.value, 1, """
            the build ran \(builds.value) times for one key: the memo let go of its lock to \
            build, so a second caller arriving mid-build found nothing and built its own copy.
            """)
    }

    /// Two keys are two entries — the shape that keeps a compound key honest.
    /// `HelmDates` keys its relative formatters by the language **and** the
    /// style for this reason: dropping the style made a `.full` call answer in
    /// whatever style that language was first asked for.
    func testTwoKeysAreTwoEntries() {
        let memo = LockedMemo<String, String>()

        XCTAssertEqual(memo.value(for: "ru|full") { "полная" }, "полная")
        XCTAssertEqual(memo.value(for: "ru|short") { "короткая" }, "короткая")
        XCTAssertEqual(memo.value(for: "ru|full") { "неверно" }, "полная")
    }

    /// A build that finds nothing is not an entry: the next caller asks the
    /// port again.
    func testNothingBuiltIsNotRemembered() {
        let memo = LockedMemo<String, String>()
        let builds = Builds()

        XCTAssertNil(memo.valueOrNothing(for: "layout") { builds.ran(); return nil })
        XCTAssertNil(memo.valueOrNothing(for: "layout") { builds.ran(); return nil })
        XCTAssertEqual(builds.value, 2, """
            the second call did not reach the build, so the memo has stored «nothing» under \
            this key — and the port that would answer differently in a moment is never asked \
            again.
            """)

        XCTAssertEqual(memo.valueOrNothing(for: "layout") { builds.ran(); return "table" }, "table")
        XCTAssertEqual(memo.valueOrNothing(for: "layout") { builds.ran(); return "other" }, "table")
        XCTAssertEqual(builds.value, 3, "a success is remembered, or the memo caches nothing at all")
    }
}
