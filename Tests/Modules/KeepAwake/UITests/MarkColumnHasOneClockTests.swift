import XCTest
import HelmTestSupport

/// Every row of the automation card is indented by the mark column — the two
/// that can carry a tick and the three that never will — so all five have to
/// move on one clock.
///
/// They did not. When the marked rows moved to a drawn value written inside
/// `withAnimation`, the three unmarked ones went on reading `marksArePossible`
/// straight, and a value handed over outside a transaction lands in one frame.
/// The result was worse than no animation at all: on every press the row that
/// gains a tick slid while the three beside it jumped, and the card came apart
/// down the middle. Reported as «the one with the icon animates faster».
///
/// A source check, because there is nothing to assert against at runtime: both
/// spellings compile, both draw the same card at rest, and the difference is
/// visible only in the frames between two states. What can be checked is that
/// the live value has exactly one reader.
final class MarkColumnHasOneClockTests: XCTestCase {

    private func page() throws -> String {
        let url = RepoSource.root
            .appendingPathComponent("Sources/Modules/KeepAwake/UI/KeepAwakeSettingsPage.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// No row reads the live value.
    ///
    /// Counted as the exact call rather than as mentions of the name: a count
    /// of mentions is broken by the next sentence anybody writes about it, and
    /// a guard that fails for a comment is a guard people delete.
    func testNoRowReadsTheLiveValue() throws {
        let source = try page()
        let direct = source.components(separatedBy: "inCardWithMarks: marksArePossible").count - 1
        XCTAssertEqual(direct, 0,
                       "\(direct) row(s) read `marksArePossible` straight. A value handed "
                       + "over outside a transaction lands in one frame, so that row jumps "
                       + "while the rest of the card ramps — use `shownMarksPossible`.")
    }

    /// And the live value still reaches the drawn one, so «nobody reads it» is
    /// not satisfied by nobody animating anything.
    func testTheLiveValueStillFeedsTheDrawnOne() throws {
        let source = try page()
        XCTAssertTrue(source.contains("onChange(of: marksArePossible)"),
                      "nothing watches the live value, so the column never moves at all")
        XCTAssertTrue(source.contains("withAnimation(HelmMotion.disclosure) { shownMarksPossible"),
                      "the drawn value is written outside a transaction, which is the same "
                      + "one frame by another route")
    }

    /// …and every row that draws the column reads the drawn value, so the count
    /// above cannot be satisfied by a card that has stopped drawing marks.
    func testEveryRowInTheCardReadsTheDrawnValue() throws {
        let source = try page()
        let drawn = source.components(separatedBy: "inCardWithMarks: shownMarksPossible").count - 1
        XCTAssertEqual(drawn, 4,
                       "four call sites hold the mark column — three spacer rows and the "
                       + "`ruleRow` the two rules share — and \(drawn) of them read the "
                       + "drawn value")
    }

    /// The control. Both assertions above are counts of a string, and a count
    /// of a string in a file that was never read is zero for a reason nobody
    /// would notice.
    func testTheFileWasReallyRead() throws {
        let source = try page()
        XCTAssertGreaterThan(source.count, 5000, "the settings page was not read at all")
        XCTAssertTrue(source.contains("shownMarksPossible"),
                      "no drawn value in the file, so the checks above cannot fail")
    }
}
