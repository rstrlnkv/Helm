import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A page with a large folder lays its tiles out by first fit, so where a tile lands depends on its neighbours. The gap
/// shown while a tile is carried is as big as that tile; the tile that lands is on the page and in the cells the gap was.
/// A small app held over any part of a large block arms it, and opens it as a small folder does.
@MainActor final class ADropLandsWhereTheGapShowedTests: XCTestCase {
    private let folderID = UUID()
    private let others = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x"]

    private func rig() -> LiftRig {
        let items: [LaunchpadLayout.Item] = [.app("a"), .app("b"), .folder(.init(id: folderID, name: "F", apps: ["y", "z", "z2"], large: true))]
            + others.dropFirst(2).map { .app($0) }
        return LiftRig(self, apps: others + ["y", "z", "z2"], layout: LaunchpadLayout(items: items))
    }

    private func slot(_ r: LiftRig, _ id: String, page: Int = 0) -> LaunchpadPlacement.Slot? {
        r.state.pages[page].firstIndex { $0.id == id }.map { r.state.slots[page][$0] }
    }

    private func place(_ r: LiftRig, _ id: String) -> (page: Int, slot: LaunchpadPlacement.Slot)? {
        for page in r.state.pages.indices { if let s = slot(r, id, page: page) { return (page, s) } }
        return nil
    }

    /// The pointer on a tile's margin, where the gap moves to it.
    private func margin(_ r: LiftRig, _ id: String) -> CGPoint? {
        guard let (page, s) = place(r, id) else { XCTFail("\(id) is on no page"); return nil }
        XCTAssertEqual(page, r.state.page)
        let c = r.g.center(of: s)
        return CGPoint(x: c.x + r.g.cellWidth * 0.42 * (s.span == 1 ? 1 : 0), y: c.y)
    }

    private func carry(_ id: String, to target: String, in r: LiftRig) async {
        guard let start = place(r, id), let at = margin(r, target) else { XCTFail("subject: \(id) and \(target) are shown"); return }
        let from = r.g.center(of: start.slot)
        XCTAssertTrue(r.state.pointerDown(from, time: 0))
        r.state.pointerMoved(CGPoint(x: from.x + 20, y: from.y), time: 0.01)
        r.state.pointerMoved(at, time: 1)
        r.state.tick(at: 1.2)
        let gap = place(r, LaunchpadEntry.gapID)
        XCTAssertNotNil(gap, "subject: the gap is shown")
        XCTAssertEqual(gap?.slot.span, id == folderID.uuidString ? 2 : 1, "the gap is the carried tile's size")
        r.state.pointerUp(at, time: 1.3)
        let edits = r.placed.count
        await waitUntil("the lift ended") { !r.state.pointerBusy }
        if r.placed.count > edits || r.state.pages.joined().contains(where: { $0.id == id }) == false { await waitUntil("the edit was written") { r.placed.count > edits } }
        await waitUntil("the tile is on a page") { place(r, id) != nil }
        let landed = place(r, id)
        XCTAssertNotNil(landed, "subject: the tile is on a page")
        XCTAssertEqual(landed?.page, gap?.page, "\(id) onto \(target): the page")
        XCTAssertEqual(landed?.slot, gap?.slot, "\(id) onto \(target): the cells")
    }

    func testALargeFolderLandsInTheCellsItsGapShowed() async {
        let big = folderID.uuidString
        var moved = false
        for target in ["a", "b", "c", "d", "g", "h", "i", "j", "k", "p", "q", "x"] {
            let r = rig()
            XCTAssertNotNil(slot(r, big), "subject: the folder is shown")
            XCTAssertEqual(slot(r, big)?.span, 2, "subject: the folder is large")
            await carry(big, to: target, in: r)
            moved = moved || slot(r, big) != slot(rig(), big)
        }
        XCTAssertTrue(moved, "subject: the folder was carried somewhere else")
    }

    func testASmallAppLandsInTheCellsItsGapShowedOnAPageWithALargeFolder() async {
        for target in ["a", "b", "c", "d", "h", "i", "j", "q", "x"] {
            let r = rig()
            XCTAssertEqual(slot(r, folderID.uuidString)?.span, 2, "subject: the folder is large")
            await carry("f", to: target, in: r)
        }
    }

    func testASmallAppHeldOverAnyCornerOfALargeBlockArmsItAndOpensIt() {
        let big = folderID.uuidString
        for (dx, dy) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0), (0.5, 0.5)] {
            let r = rig()
            guard let bigSlot = slot(r, big), let small = place(r, "f") else { XCTFail("subject: both tiles are shown"); continue }
            let block = r.g.frame(of: bigSlot).offsetBy(dx: 0, dy: r.g.gridTop)
            XCTAssertEqual(bigSlot.span, 2, "subject: the folder is large")
            let from = r.g.center(of: small.slot)
            XCTAssertTrue(r.state.pointerDown(from, time: 0))
            r.state.pointerMoved(CGPoint(x: from.x + 20, y: from.y), time: 0.01)
            let at = CGPoint(x: block.minX + 3 + (block.width - 6) * dx, y: block.minY + 3 + (block.height - 6) * dy)
            r.state.pointerMoved(at, time: 1)
            XCTAssertNil(r.state.lift?.onto, "\(dx),\(dy): not yet")
            r.state.tick(at: 1 + LaunchpadLiftTiming.ontoArm + 0.01)
            XCTAssertEqual(r.state.lift?.onto, big, "\(dx),\(dy): armed")
            XCTAssertNil(r.state.openFolder)
            r.state.tick(at: 1 + LaunchpadLiftTiming.folderOpen + 0.01)
            XCTAssertEqual(r.state.openFolder, folderID, "\(dx),\(dy): opened")
        }
    }
}
