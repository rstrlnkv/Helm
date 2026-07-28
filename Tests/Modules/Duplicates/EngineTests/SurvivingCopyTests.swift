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
final class SurvivingCopyTests: XCTestCase {

    private func file(_ path: String, added: Date? = nil, bytes: Int = 1_000) -> FileFacts {
        FileFacts(path: path, bytes: bytes, fileID: UInt64(abs(path.hashValue)), added: added)
    }
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

    // MARK: - The original wins

    func testTheOldestCopyStaysEvenWhenItsPathSortsLast() {
        let ordered = SurvivingCopy.order([
            file("/Users/r/Desktop/photo.jpg", added: day(500)),
            file("/Users/r/Documents/Archive/2019/photo.jpg", added: day(10)),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/Documents/Archive/2019/photo.jpg",
                       "the filed original stays; the copy on the Desktop is the extra")
    }

    func testTheRestFollowInTheSameOrderSoTheListIsStable() {
        let ordered = SurvivingCopy.order([
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
        let ordered = SurvivingCopy.order([
            file("/Users/r/Documents/Projects/2019/Old/photo.jpg", added: day(10)),
            file("/Users/r/Documents/photo.jpg", added: day(10)),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/Documents/photo.jpg")
    }

    func testWithEqualDatesAndDepthAlphabeticalDecides() {
        let ordered = SurvivingCopy.order([
            file("/Users/r/b.jpg", added: day(10)),
            file("/Users/r/a.jpg", added: day(10)),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/a.jpg")
    }

    // MARK: - When the date is not there

    /// A volume that does not record when a file was added reports nothing, and
    /// nothing must not read as "the beginning of time" — that would hand the
    /// decision to whichever copy the filesystem knows least about.
    func testAKnownDateBeatsAnUnknownOne() {
        let ordered = SurvivingCopy.order([
            file("/a.jpg"),
            file("/Users/r/Documents/Archive/z.jpg", added: day(400)),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/Documents/Archive/z.jpg",
                       "a copy with a date is the one we know something about")
    }

    func testWithNoDatesAtAllTheShallowerPathStays() {
        let ordered = SurvivingCopy.order([
            file("/Users/r/Documents/Projects/Old/photo.jpg"),
            file("/Users/r/Documents/photo.jpg"),
        ])
        XCTAssertEqual(ordered.first, "/Users/r/Documents/photo.jpg")
    }

    // MARK: - It always answers

    func testEveryPathSurvivesTheOrderingAndNoneIsInventedOrLost() {
        let paths = ["/a/b/c.jpg", "/a/c.jpg", "/z.jpg", "/a/b/a.jpg"]
        let ordered = SurvivingCopy.order(paths.map { file($0, added: day(7)) })
        XCTAssertEqual(Set(ordered), Set(paths))
        XCTAssertEqual(ordered.count, paths.count)
    }

    /// Two files whose facts are identical in every way the rule reads must
    /// still come back in one fixed order, or the row moves between scans.
    func testTheOrderDoesNotDependOnTheInputOrder() {
        let files = [file("/a/x.jpg", added: day(3)), file("/b/x.jpg", added: day(3))]
        XCTAssertEqual(SurvivingCopy.order(files), SurvivingCopy.order(files.reversed()))
    }

    func testOneFileIsItsOwnSurvivor() {
        XCTAssertEqual(SurvivingCopy.order([file("/only.jpg")]), ["/only.jpg"])
    }

    func testNoFilesIsNoPaths() {
        XCTAssertTrue(SurvivingCopy.order([]).isEmpty)
    }
}
