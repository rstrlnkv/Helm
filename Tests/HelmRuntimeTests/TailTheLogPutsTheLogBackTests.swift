import XCTest
@testable import HelmRuntime

/// Guards `tailTheLog()`'s teardown: a test that switched the log on must leave it
/// off, or the next suite writes the user's log. A probe case runs to its end, then a
/// line written afterwards must not reach the tail.
final class TailTheLogPutsTheLogBackTests: XCTestCase {

    private final class Probe: XCTestCase {
        func switchTheLogOn() { tailTheLog() }
        func writeOneLine() {
            tailTheLog()
            HelmLog.shared.info("probe", "written inside the probe")
            _ = HelmLog.shared.recentEntries()      // the queue has taken it
        }
    }

    func testTheLogIsOffAfterTheTestThatSwitchedItOn() {
        Probe(selector: #selector(Probe.switchTheLogOn)).run()
        HelmLog.shared.clearTail()
        HelmLog.shared.info("probe", "written after the probe ended")
        let lines = loggedLines("probe")
        HelmLog.shared.clearTail()
        XCTAssertEqual(lines, [], "the log stayed on after the test that enabled it")
    }

    func testTheTailIsEmptiedWhenTheTestEnds() {
        Probe(selector: #selector(Probe.writeOneLine)).run()
        XCTAssertEqual(loggedLines("probe"), [],
                       "a line the probe wrote was still in the tail after it ended")
    }

    func testTheTailKeepsOnlyTheCategoryAskedFor() {
        tailTheLog()
        HelmLog.shared.info("probe", "kept for the next check")
        HelmLog.shared.info("other", "a different category")
        XCTAssertEqual(loggedLines("probe"), ["kept for the next check"])
        XCTAssertEqual(loggedLines("other"), ["a different category"])
    }

    func testAStaleLineIsGoneOnceTheLogIsSwitchedOn() {
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.info("probe", "stale")
        _ = HelmLog.shared.recentEntries()
        tailTheLog()
        XCTAssertEqual(loggedLines("probe"), [], "tailTheLog left an earlier line in the tail")
    }
}
