import XCTest
@testable import Module_Disk_Engine

/// The «other» arc in `RingLayout.layout` adds up every child too narrow to
/// draw with `Int.saturatingAdding(_:)`.
///
/// A walk cannot make a folder's children outweigh an integer, but
/// `restoreLastScan` also decodes a tree from the saved file, and `DiskEntry`'s
/// bound on each figure is not a bound on their sum. Without the saturating add
/// this traps and takes the whole test process with it; that is how it reads red.
final class TheFoldedArcDoesNotTrapTests: XCTestCase {

    func testNarrowChildrenOutweighingAnIntegerDoNotTrapTheOtherArc() {
        // Each child is 1/190 of the folder — under the 2° fold — and 200 of them
        // sum past the largest integer.
        let share = Int.max / 190
        let children = (0..<200).map {
            DiskNode(name: "f\($0)", bytes: share, isDirectory: false)
        }
        let focus = DiskNode(name: "root", bytes: Int.max, isDirectory: true, children: children)
        let segments = RingLayout.layout(focus: focus, path: "/", depthLevels: 1, freeBytes: 0)
        XCTAssertTrue(segments.contains(where: \.isOther), "the narrow children fold into «other»")
    }

    /// The saved file is where such a tree comes from, so the figure is also
    /// bounded where it is decoded: a planted `Int.max` reads as the ceiling.
    func testAFigureDecodedFromAFileIsBounded() throws {
        let json = #"{"name":"x","path":"/x","bytes":9223372036854775807,"isDirectory":false,"noAccess":false,"children":[]}"#
        let entry = try JSONDecoder().decode(DiskEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.bytes, DiskEntry.byteCeiling)
        let negative = try JSONDecoder().decode(
            DiskEntry.self, from: Data(json.replacingOccurrences(of: "9223372036854775807", with: "-5").utf8))
        XCTAssertEqual(negative.bytes, 0)
    }
}
