import XCTest
@testable import Module_Duplicates_Engine

/// Which copy stays is the one decision in this module that costs something to
/// get wrong: the rest are baskets in one click.
///
/// It used to be the alphabetically first path, which is not a belief about
/// anything — it just happened to be how the list was sorted for display. So
/// `~/Desktop/photo.jpg` beat `~/Documents/Archive/2019/photo.jpg`, because D
/// sorts before A, and Helm offered to delete the filed copy and keep the
/// clutter. The page said so plainly, which only moved the work onto the reader.
///
/// **What the policy owns and what this file owns.** `KeepPolicyTests` covers
/// the two ladders and the tier they rest on; these are the rungs each policy
/// shares, exercised through `.standard`, plus the promises the ordering makes
/// whatever the policy is — every copy comes back, none is invented, and the
/// answer does not depend on the order the walk found them in.
final class SurvivingCopyTests: XCTestCase {

    private func file(_ path: String, added: Date? = nil, bytes: Int = 1_000) -> FileFacts {
        FileFacts(path: path, bytes: bytes, fileID: UInt64(abs(path.hashValue)), added: added)
    }
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }
    private let rule = KeepRule(.standard)

    private func order(_ files: [FileFacts]) -> [String] {
        SurvivingCopy.order(files, by: rule).map(\.path)
    }

    // MARK: - The older copy wins

    func testTheOldestCopyStaysEvenWhenItsPathSortsLast() {
        let ordered = order([
            file("/Users/r/Pictures/photo.jpg", added: day(500)),
            file("/Users/r/Documents/Archive/2019/photo.jpg", added: day(10)),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/Documents/Archive/2019/photo.jpg",
                       "the filed original stays; the later copy is the extra")
    }

    func testTheRestFollowInTheSameOrderSoTheListIsStable() {
        let ordered = order([
            file("/b.jpg", added: day(30)),
            file("/a.jpg", added: day(10)),
            file("/c.jpg", added: day(20)),
        ])
        XCTAssertEqual(ordered, ["/a.jpg", "/c.jpg", "/b.jpg"])
    }

    // MARK: - Then the shallower path

    /// Same day, or a filesystem that reports the same second for a batch that
    /// arrived together. Depth is the next thing that means something: a file
    /// four folders down was put somewhere on purpose.
    func testWithEqualDatesTheShallowerPathStays() {
        let ordered = order([
            file("/Users/r/Documents/Projects/2019/Old/photo.jpg", added: day(10)),
            file("/Users/r/Documents/photo.jpg", added: day(10)),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/Documents/photo.jpg")
    }

    func testWithEqualDatesAndDepthAlphabeticalDecides() {
        let ordered = order([
            file("/Users/r/b.jpg", added: day(10)),
            file("/Users/r/a.jpg", added: day(10)),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/a.jpg")
    }

    // MARK: - When the date is not there

    /// **This test used to assert the opposite**, and the rule it was defending
    /// was the wrong end of the same reasoning: a volume that does not record
    /// when a file was added reports nothing, and nothing was read as a *loss*
    /// for the copy it was missing from. So one blank date settled a group
    /// outright, and every rung below it — where the file sits, how deep it is —
    /// was never asked. Silence is not evidence: the ladder carries on.
    func testAnUnknownDateSettlesNothingAndTheShallowerPathStays() {
        let ordered = order([
            file("/Users/r/Documents/Archive/z.jpg", added: day(400)),
            file("/Users/r/Documents/a.jpg"),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/Documents/a.jpg",
                       "one date and one blank separate nothing at all")
    }

    func testWithNoDatesAtAllTheShallowerPathStays() {
        let ordered = order([
            file("/Users/r/Documents/Projects/Old/photo.jpg"),
            file("/Users/r/Documents/photo.jpg"),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/Documents/photo.jpg")
    }

    // MARK: - It always answers

    func testEveryPathSurvivesTheOrderingAndNoneIsInventedOrLost() {
        let paths = ["/a/b/c.jpg", "/a/c.jpg", "/z.jpg", "/a/b/a.jpg"]
        let ordered = order(paths.map { file($0, added: day(7)) })
        XCTAssertEqual(Set(ordered), Set(paths))
        XCTAssertEqual(ordered.count, paths.count)
    }

    /// Two files whose facts are identical in every way the rule reads must
    /// still come back in one fixed order, or the row moves between scans.
    func testTheOrderDoesNotDependOnTheInputOrder() {
        let files = [file("/a/x.jpg", added: day(3)), file("/b/x.jpg", added: day(3))]
        XCTAssertEqual(order(files), order(files.reversed()))
    }

    /// The copies come back whole, not as paths the caller has to look up again:
    /// the size, the clone family and the date travel with each one.
    func testTheOrderHandsBackTheCopiesThemselves() {
        let ordered = SurvivingCopy.order([file("/late.jpg", added: day(9), bytes: 20),
                                           file("/early.jpg", added: day(1), bytes: 10)],
                                          by: rule)
        XCTAssertEqual(ordered.map(\.bytes), [10, 20])
        XCTAssertEqual(ordered.first?.added, day(1))
    }

    func testOneFileIsItsOwnSurvivor() {
        XCTAssertEqual(order([file("/only.jpg")]), ["/only.jpg"])
    }

    func testNoFilesIsNoPaths() {
        XCTAssertTrue(order([]).isEmpty)
    }
}
