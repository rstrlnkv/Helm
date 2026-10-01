import AppKit
import XCTest
import HelmTestSupport

/// Two roads to a lit Follow that could leave the page away from its newest
/// line, and the rule that closes both: the page's follow key.
///
/// A rule that moved to the newest line on two occasions only — the list's
/// scroll view appearing, and the newest line's identity changing — never fired
/// when Follow was switched back on in a quiet log, or when a filter was widened
/// while the newest line stayed the same one, so the control said "following"
/// over a view of the middle of the log. The key the page watches now holds
/// Follow itself, the first and last shown line and the count, and both roads
/// end on the newest line.
final class TheLogFollowsWithoutANewLineTests: XCTestCase {

    /// Lit again with no new line arriving, Follow says the newest line is in
    /// view; the page has to go there on the press, not on the next line —
    /// which in a quiet log never comes.
    @MainActor
    func testFollowSwitchedBackOnGoesToTheNewestLine() throws {
        let page = LogPageUnderHand(LogPageUnderHand.log())
        defer { page.close() }
        page.pump(1.5)
        try page.pressFollow()
        try page.scrollNearTop()
        XCTAssertGreaterThan(try page.gap(), 1000, "the reader never left the end")

        try page.pressFollow()
        page.pump(1.0)
        let gap = try page.gap()
        XCTAssertLessThan(gap, 24, "Follow is lit and the page sits \(gap) pt above its newest line")
    }

    /// Narrowed to Warnings and widened back, the newest line is a warning both
    /// times, so its identity never changes and nothing tells the list to move;
    /// the list grows under a scroll offset measured from its top.
    @MainActor
    func testAFilterWidenedWithFollowOnStaysOnTheNewestLine() throws {
        let page = LogPageUnderHand(LogPageUnderHand.log())
        defer { page.close() }
        page.pump(1.5)
        XCTAssertLessThan(try page.gap(), 24, "the page did not open on its newest line")
        try page.level(1)
        XCTAssertLessThan(try page.gap(), 24, "narrowed to Warnings, the page left its newest line")
        try page.level(0)
        let gap = try page.gap()
        XCTAssertLessThan(gap, 24, "widened back to All with Follow lit, the page sits \(gap) pt "
                          + "above its newest line")
    }
}
