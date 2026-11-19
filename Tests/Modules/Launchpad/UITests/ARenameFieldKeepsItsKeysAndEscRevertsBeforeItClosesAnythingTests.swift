import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A folder's name is typed in a field in a panel that takes its keys before any field sees them. While the field has the
/// keyboard only Return and Esc are the window's; the caret, the arrows and the typing are the field's, and Esc undoes the
/// typing and nothing more: the folder stays open, and the search and the window are not asked.
@MainActor final class ARenameFieldKeepsItsKeysAndEscRevertsBeforeItClosesAnythingTests: XCTestCase {
    private let folderID = UUID()
    private func rig() -> LiftRig {
        let r = LiftRig(self, apps: ["a", "b", "c", "d"],
                        layout: LaunchpadLayout(items: [.app("a"), .folder(.init(id: folderID, name: "F", apps: ["b", "c"])), .app("d")]))
        r.state.open(folder: folderID)
        r.state.beginRenaming(selectAll: false)
        return r
    }

    func testEveryKeyButReturnAndEscGoesOnToTheField() {
        let r = rig()
        r.state.nameDraft = "typed"
        for code: UInt16 in [123, 124, 125, 126, 48, 0, 51, 117, 49] {
            XCTAssertFalse(r.state.handleNameKey(code), "key \(code) is the field's")
        }
        XCTAssertTrue(r.state.renaming)
        XCTAssertEqual(r.state.nameDraft, "typed")
        XCTAssertEqual(r.state.openFolder, folderID)
        XCTAssertTrue(r.renamed.isEmpty)
    }

    func testEscRevertsTheTypingAndLeavesTheFolderTheSearchAndTheWindowAlone() {
        let r = rig()
        r.state.nameDraft = "typed"
        XCTAssertTrue(r.state.handleNameKey(53))
        XCTAssertEqual(r.state.nameDraft, "F")
        XCTAssertFalse(r.state.renaming)
        XCTAssertEqual(r.state.openFolder, folderID, "the folder stays open")
        XCTAssertEqual(r.closes, 0)
        XCTAssertTrue(r.renamed.isEmpty, "nothing was written")
    }

    func testTheEscapeOrderIsTheNameThenTheFolderThenTheWindow() {
        let r = rig()
        r.state.nameDraft = "typed"
        r.state.escape()
        XCTAssertFalse(r.state.renaming)
        XCTAssertEqual(r.state.openFolder, folderID)
        r.state.escape()
        XCTAssertNil(r.state.openFolder)
        XCTAssertEqual(r.closes, 0)
        XCTAssertTrue(r.renamed.isEmpty, "an Esc'd draft is not committed by the card closing")
        r.state.escape()
        XCTAssertEqual(r.closes, 1)
    }
}
