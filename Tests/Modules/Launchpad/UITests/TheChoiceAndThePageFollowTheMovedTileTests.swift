import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// After a reorder by key the choice stays on the tile it moved, and the page shows where the tile landed: a tile moved
/// over a page's end takes the page along, in the grid and in a folder's card.
@MainActor final class TheChoiceAndThePageFollowTheMovedTileTests: XCTestCase {
    func testTheChoiceAndThePageGoWithATileMovedOntoTheNextPage() async {
        let ids = (0..<8).map { String(format: "app%02d", $0) }
        let r = LiftRig(self, apps: ids, layout: LaunchpadLayout(items: ids.map { .app($0) }))
        r.state.regrid(LaunchpadGridSettings(automatic: false, rows: 2, columns: 3, iconSize: 80))
        r.choose("app05")
        XCTAssertEqual(r.state.page, 0, "subject: the tile is on the first page")
        XCTAssertTrue(r.state.reorderKey(dx: 1, dy: 0, combine: false))
        await grace()
        XCTAssertEqual(r.ids(1).first, "app05", "subject: it landed on the second page")
        XCTAssertEqual(r.state.page, 1, "the page turned with it")
        XCTAssertEqual(r.state.selection.map { r.state.pages.joined().map(\.id)[$0] }, "app05", "and the choice is still on it")
    }

    func testTheCardsPageGoesWithAnAppMovedOverItsEnd() async {
        let f = UUID()
        let members = (0..<60).map { String(format: "m%02d", $0) }
        let r = LiftRig(self, apps: members, layout: LaunchpadLayout(items: [.folder(.init(id: f, name: "F", apps: members))]))
        r.state.open(folder: f)
        let capacity = LaunchpadSurface.Card(geometry: r.state.geometry, count: members.count, page: 0).capacity
        XCTAssertLessThan(capacity, members.count, "subject: the card has pages")
        r.state.move(dx: 1, dy: 0)
        for _ in 1..<capacity { r.state.move(dx: 1, dy: 0) }
        XCTAssertEqual(r.state.cardPage, 0)
        XCTAssertEqual(r.state.selection, capacity - 1, "the choice is on the card's last tile of its first page")
        XCTAssertTrue(r.state.reorderKey(dx: 1, dy: 0, combine: false))
        await grace()
        XCTAssertEqual(r.state.selection, capacity, "the choice is where the app is")
        XCTAssertEqual(r.state.cardPage, 1, "and the card shows that page")
    }
}
