import XCTest
@testable import Module_Disk_Engine

/// The brother of the free-space sum `RingLayout.layout` now saturates: the
/// «other» arc adds up every child too narrow to draw, and does it with
/// `Int.saturatingAdding(_:)`, where it once used a plain `+=`.
///
/// A walk of a real disk cannot make the children of a folder outweigh an
/// integer, but a tree does not only come from a walk — `restoreLastScan` decodes
/// one from the saved file. `DiskEntry` bounds each figure there to
/// `DiskEntry.byteCeiling`, and a bound on each figure is not one on their sum:
/// narrow children together past `Int.max` would trap the process in the layout,
/// and the saved file is read again on every opening of the page.
///
/// Without the saturating add this traps and takes the whole test process with it
/// (`unexpected signal code 5`); that is how it reads red, and it was seen red
/// that way before the add was repaired.
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
