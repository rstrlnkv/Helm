import XCTest
@testable import HelmApp

/// What the composer table does with an update it has just been handed.
///
/// The table is fed by `updateNSView`, which SwiftUI calls for **any** change
/// in the block around it — including the block's own reaction to the height
/// the table just reported. Deciding by hand inside that call reloaded the
/// table 31 ms into a 300 ms transition and threw away every row that was
/// animating, so the rows snapped and the note and buttons carried on. The
/// decision is a value now, and these are the cases it has to get right.
final class SidebarComposerRedrawTests: XCTestCase {

    private func state(rows: [String], editing: Bool, content: [String]? = nil)
    -> SidebarComposerState {
        SidebarComposerState(rowIDs: rows, editing: editing,
                             content: content ?? rows)
    }

    /// The one that matters: an update that changes nothing changes nothing.
    /// This is the height report coming back round, and it used to reload.
    func testAnIdenticalUpdateDoesNothing() {
        let before = state(rows: ["a", "b"], editing: true)
        XCTAssertEqual(SidebarComposerRedraw.between(before, before), .nothing)
    }

    /// The same rows in a new mode is the transition: the rows change shape.
    func testAModeChangeOverTheSameRowsAnimates() {
        let before = state(rows: ["a", "b"], editing: false, content: ["a-rest", "b-rest"])
        let after = state(rows: ["a", "b"], editing: true, content: ["a-edit", "b-edit"])
        XCTAssertEqual(SidebarComposerRedraw.between(before, after), .animate)
    }

    /// A row that has to appear is not a row that can change shape.
    func testNewRowsReload() {
        let before = state(rows: ["a", "b"], editing: true)
        let after = state(rows: ["a", "b", "c"], editing: true)
        XCTAssertEqual(SidebarComposerRedraw.between(before, after), .reload)
    }

    /// A drop reorders the same rows. The table still has to rebuild: row 0 is
    /// somebody else now.
    func testReorderedRowsReload() {
        let before = state(rows: ["a", "b"], editing: true)
        let after = state(rows: ["b", "a"], editing: true)
        XCTAssertEqual(SidebarComposerRedraw.between(before, after), .reload)
    }

    /// Entering edit can also add a row — an empty section is drawn only in
    /// edit. Then it is a reload, because the shape change is the smaller half.
    func testAModeChangeThatAlsoChangesTheRowsReloads() {
        let before = state(rows: ["a"], editing: false)
        let after = state(rows: ["a", "empty-section"], editing: true)
        XCTAssertEqual(SidebarComposerRedraw.between(before, after), .reload)
    }

    /// A rename, or a switch turned off: same rows, same mode, new contents.
    /// The rows are handed what they now say, without a transition.
    func testNewContentsOverTheSameRowsRefreshes() {
        let before = state(rows: ["a"], editing: true, content: ["a on"])
        let after = state(rows: ["a"], editing: true, content: ["a off"])
        XCTAssertEqual(SidebarComposerRedraw.between(before, after), .refresh)
    }
}
