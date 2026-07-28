import Foundation
import XCTest
@testable import Module_Duplicates_Engine

/// The row the keyboard is on.
///
/// The list had no `selection`, so — as the disk list's own comment puts it —
/// it had no focusable rows at all: arrow keys did nothing, the "stays" row
/// held no control to land on, and Reveal in Finder existed only in a context
/// menu, which a Full Keyboard Access user without VoiceOver cannot open.
///
/// A selection is a path, and the list under it changes: emptying the basket
/// removes rows, and a group that drops to one copy disappears entirely. What
/// this pins is that the keyboard is never left pointing at a row that is no
/// longer there.
final class DuplicateSelectionTests: XCTestCase {

    private func group(_ paths: [String]) -> DuplicateGroup {
        DuplicateGroup(bytes: 1_000_000, paths: paths)
    }

    func testASelectedRowThatIsStillThereStaysSelected() {
        let groups = [group(["/a/one.bin", "/b/one.bin"])]
        XCTAssertEqual(DuplicateSelection.surviving("/b/one.bin", in: groups), "/b/one.bin")
    }

    func testARowThatWasRemovedIsNoLongerSelected() {
        let groups = [group(["/a/one.bin", "/b/one.bin"])]
        XCTAssertNil(DuplicateSelection.surviving("/c/gone.bin", in: groups))
    }

    /// The whole group can go: two copies minus one is not a duplicate.
    func testNothingIsSelectedWhenTheListEmpties() {
        XCTAssertNil(DuplicateSelection.surviving("/a/one.bin", in: []))
    }

    func testNoSelectionStaysNoSelection() {
        XCTAssertNil(DuplicateSelection.surviving(nil, in: [group(["/a/one.bin", "/b/one.bin"])]))
    }
}
