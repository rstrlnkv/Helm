import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A category block is a folder-shaped entry in the window's state, so everything a person can do to a folder must be refused in the
/// category view: no lift, no rename, no resize, nothing sent to the engine, and the layout file is the same bytes after. Each case
/// first proves the category view is shown and the thing it presses on exists.
@MainActor final class TheCategoryViewWritesNoArrangementTests: XCTestCase {
    private let apps = ["a", "b", "c", "d", "e", "f", "g"]

    private func rig() throws -> LiftRig {
        let rig = LiftRig(self, apps: apps, layout: LaunchpadLayout(items: [.app("c"), .app("a"), .app("g"), .app("b"), .app("f"), .app("d"), .app("e")]))
        rig.categorize(["a": "public.app-category.music", "b": "public.app-category.music", "c": "public.app-category.music",
                        "d": "public.app-category.music", "e": "public.app-category.music", "f": "public.app-category.weather"])
        return rig
    }

    /// The block's frame in the window, and a point on its quadrant `q`.
    private func block(_ rig: LiftRig, _ index: Int = 0) -> CGRect {
        let slot = rig.state.slots[0][index]
        return rig.state.geometry.frame(of: slot).offsetBy(dx: 0, dy: rig.state.geometry.gridTop)
    }

    private func quadrant(_ rig: LiftRig, block index: Int = 0, _ q: Int) -> CGPoint {
        let g = rig.state.geometry, block = block(rig, index), mark = g.largeMark
        let f = LaunchpadCategoryMark.frame(ofQuadrant: q, size: mark)
        return CGPoint(x: block.midX - mark / 2 + f.midX, y: block.minY + LaunchpadMetrics.iconTop + f.midY)
    }

    func testNothingADragOrACardOrASearchDoesInTheCategoryViewWritesTheArrangement() throws {
        let rig = try rig()
        let layoutBefore = try Data(contentsOf: rig.layoutFile)
        let pages = rig.state.pages, slots = rig.state.slots

        rig.state.setView(.categories)
        XCTAssertTrue(rig.state.categoriesShown)
        XCTAssertEqual(rig.state.pages[0].count, 3, "the control: Music, Weather and Others")
        guard case .folder(_, _, let musicApps, true) = rig.state.pages[0][0] else { return XCTFail("a block is a large folder-shaped entry") }
        XCTAssertEqual(musicApps.count, 5)

        // A press and a drag on the block's margin and on a large icon: the press is taken, and nothing is carried.
        for point in [CGPoint(x: block(rig).minX + 6, y: block(rig).midY), quadrant(rig, 0)] {
            XCTAssertTrue(rig.state.pointerDown(point, time: 0))
            rig.state.pointerMoved(CGPoint(x: point.x + 120, y: point.y + 40), time: 0.1)
            rig.state.pointerMoved(CGPoint(x: point.x + 300, y: point.y + 80), time: 0.2)
            XCTAssertNil(rig.state.lift, "no tile is lifted in the category view")
            rig.state.pointerUp(CGPoint(x: point.x + 300, y: point.y + 80), time: 0.3)
            XCTAssertNil(rig.state.lift)
        }
        XCTAssertTrue(rig.launched.isEmpty, "a drag launches nothing")

        // A click on the cluster opens the card; on a large icon it launches that app.
        let cluster = quadrant(rig, 3)
        XCTAssertTrue(rig.state.pointerDown(cluster, time: 1))
        rig.state.pointerUp(cluster, time: 1.05)
        XCTAssertEqual(rig.state.openFolder, UUID(uuidString: rig.state.pages[0][0].id), "the cluster opens the card")
        XCTAssertEqual(rig.state.folderApps.count, 5)
        XCTAssertTrue(rig.launched.isEmpty)

        // In the card: a drag from a tile, the title edited and the card closed, Return on the chosen tile.
        let card = LaunchpadSurface.Card(geometry: rig.state.geometry, count: rig.state.folderApps.count)
        let tile = card.center(ofSlot: 0)
        XCTAssertTrue(rig.state.pointerDown(tile, time: 2))
        rig.state.pointerMoved(CGPoint(x: tile.x + 60, y: tile.y + 60), time: 2.1)
        rig.state.pointerMoved(CGPoint(x: tile.x + 90, y: tile.y + 90), time: 2.2)
        XCTAssertNil(rig.state.lift, "no tile is lifted out of a category's card either")
        rig.state.pointerUp(CGPoint(x: tile.x + 90, y: tile.y + 90), time: 2.3)
        rig.state.nameDraft = "Renamed"
        rig.state.commitName()
        rig.state.closeFolder()
        XCTAssertNil(rig.state.openFolder)
        XCTAssertTrue(rig.renamed.isEmpty, "a category's title is not a name a person gives")

        rig.state.move(dx: 1, dy: 0)
        rig.state.activate()
        XCTAssertEqual(rig.state.openFolder != nil, true, "Return on the chosen block opens its card")
        rig.state.move(dx: 1, dy: 0)
        rig.state.activate()
        XCTAssertEqual(rig.launched.count, 1, "Return on a tile of the card launches it: the control that launching works here")

        // A search shows the apps flat and its clearing brings the blocks back.
        rig.state.search = "a"
        XCTAssertFalse(rig.state.categoriesShown)
        rig.state.search = ""
        XCTAssertTrue(rig.state.categoriesShown)

        XCTAssertTrue(rig.placed.isEmpty, "nothing was sent to the engine to place")
        XCTAssertTrue(rig.renamed.isEmpty)
        XCTAssertNil(rig.state.lift)
        XCTAssertEqual(try Data(contentsOf: rig.layoutFile), layoutBefore, "the layout file has the same bytes")

        // Switching back: the arrangement as it was, page for page and slot for slot.
        rig.state.setView(.apps)
        XCTAssertFalse(rig.state.categoriesShown)
        XCTAssertEqual(rig.state.pages, pages)
        XCTAssertEqual(rig.state.slots, slots)
        XCTAssertEqual(rig.state.geometry, rig.g)
    }

    func testALargeIconInABlockLaunchesAndTheViewIsRememberedByTheStateOnly() throws {
        let rig = try rig()
        var told: [LaunchpadViewMode] = []
        rig.state.onViewChange = { told.append($0) }
        rig.state.setView(.categories)
        rig.state.setView(.categories)
        XCTAssertEqual(told, [.categories], "an equal view is no change")
        let icon = quadrant(rig, 0)
        XCTAssertTrue(rig.state.pointerDown(icon, time: 0))
        rig.state.pointerUp(icon, time: 0.05)
        XCTAssertEqual(rig.launched, ["a"], "the block's first app, by count then catalog order")
        XCTAssertNil(rig.state.openFolder)
    }
}
