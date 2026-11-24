import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Inputs the first pass of tests did not feed: a folder made by a chord on the next page, a card's later page, an action read
/// before the neighbour changed, an action offered where the edit is nil.
@MainActor final class AKeyMoveUntriedInputsTests: XCTestCase {
    private func pageOfSelection(_ r: LiftRig) -> Int? {
        guard let sel = r.state.selection else { return nil }
        var cum = 0
        for (i, p) in r.state.pages.enumerated() { if sel < cum + p.count { return i }; cum += p.count }
        return nil
    }

    func testCombineMakingAFolderOnTheNextPageLeavesTheChoiceOnAPageNotShown() async {
        let r = LiftRig(self, apps: ["a", "b", "c", "d", "e"], layout: LaunchpadLayout(items: [.app("a"), .app("b"), .app("c"), .pageBreak, .app("d"), .app("e")]))
        r.choose("c")
        XCTAssertTrue(r.state.reorderKey(dx: 1, dy: 0, combine: true))
        await grace()
        XCTAssertNotNil(r.state.openFolder, "subject: the folder was made and its card is open")
        r.state.closeFolder()
        XCTAssertEqual(pageOfSelection(r), 1, "subject: the choice is on the folder, on the second page")
        XCTAssertEqual(r.state.page, 1, "the page shown is the choice's")
    }

    func testTakeOutFromALaterCardPageAndALaterGridPage() async {
        let f = UUID()
        let members = (0..<60).map { String(format: "m%02d", $0) }
        let top = (0..<8).map { String(format: "t%02d", $0) }
        let r = LiftRig(self, apps: members + top, layout: LaunchpadLayout(items: top.map { .app($0) } + [.folder(.init(id: f, name: "F", apps: members))]))
        r.state.regrid(LaunchpadGridSettings(automatic: false, rows: 2, columns: 3, iconSize: 80))
        let before = r.placedApps.sorted()
        r.state.go(to: 1)
        r.state.open(folder: f)
        _ = LaunchpadSurface.Card(geometry: r.state.geometry, count: members.count, page: 0).capacity
        r.state.move(dx: 1, dy: 0)
        var guardN = 0
        while r.state.cardPage < 1, guardN < 200 { r.state.move(dx: 1, dy: 0); guardN += 1 }
        r.state.move(dx: 1, dy: 0)
        let chosen = r.state.selection!
        XCTAssertEqual(r.state.cardPage, 1, "subject: the choice is on the card's second page")
        XCTAssertTrue(r.state.reorderKey(dx: 1, dy: 0, combine: true))
        await grace()
        XCTAssertEqual(r.placed.count, 1)
        XCTAssertEqual(r.placedApps.sorted(), before)
        XCTAssertNil(r.state.openFolder)
        let flat = r.state.pages.joined().map(\.id)
        XCTAssertEqual(r.state.selection.map { flat[$0] }, String(format: "m%02d", chosen))
        XCTAssertEqual(r.state.page, pageOfSelection(r))
        XCTAssertEqual(r.state.cardPage, 0, "the card's page is reset")
    }

    func testAClosureReadBeforeTheNeighbourStoppedBeingAFolderDoesNotMakeAFolder() async {
        let f = UUID()
        let r = LiftRig(self, apps: ["a", "b", "c", "d"], layout: LaunchpadLayout(items: [.app("a"), .folder(.init(id: f, name: "F", apps: ["b", "c"])), .app("d")]))
        let add = r.state.moves(for: "d")?.addToPreviousFolder
        XCTAssertNotNil(add, "subject: the action is offered")
        // The folder is dissolved (take both out) before the action runs.
        _ = r.engine.apply(.place("a", relativeTo: "d", after: false))
        r.state.update(snapshot: r.engine.read(reason: .refresh))
        let beforeLayout = r.layout
        add?()
        await grace()
        XCTAssertEqual(r.layout, beforeLayout, "a stale 'add to previous folder' wrote \(r.layout.items)")
    }

    func testNoActionIsOfferedOnAFullFolderWhereItWritesNothing() {
        let f = UUID()
        let members = (0..<LaunchpadLimits.maxFolderApps).map { String(format: "m%04d", $0) }
        let r = LiftRig(self, apps: members + ["x"], layout: LaunchpadLayout(items: [.folder(.init(id: f, name: "F", apps: members)), .app("x")]))
        let moves = r.state.moves(for: "x")
        XCTAssertNotNil(moves?.earlier, "subject: the tile has actions, the ones that exist")
        XCTAssertNil(moves?.addToPreviousFolder, "'add to previous folder' is offered on a full folder, where it writes nothing")
    }
}
