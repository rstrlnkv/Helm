import XCTest
import HelmRuntime
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Inputs a large folder was not fed by the pass that made it: a page of nothing but blocks, a block first on the page after a
/// strip, a two-app block that dissolves, a resize while the card is open or before a regrid, a block carried over a page's
/// edge, a search typed while it is lifted, and a hand-edited file.
@MainActor final class ALargeFolderUntriedInputsTests: XCTestCase {
    private let folderID = UUID()
    private let small = LaunchpadGridSettings(automatic: false, rows: 2, columns: 3, iconSize: 80)
    private let big = LaunchpadGridSettings(automatic: false, rows: 8, columns: 10, iconSize: 128)
    private let four = LaunchpadGridSettings(automatic: false, rows: 4, columns: 4, iconSize: 80)

    private func apps(_ n: Int) -> [String] { (0..<n).map { String(format: "t%02d", $0) } }

    private func rig(before: Int = 0, large: Bool = true, after: Int = 26, members: [String] = ["y", "z", "z2"]) -> LiftRig {
        let items: [LaunchpadLayout.Item] = apps(before).map { .app($0) } + [.folder(.init(id: folderID, name: "F", apps: members, large: large))] + apps(after).map { .app("u" + $0) }
        let r = LiftRig(self, apps: apps(before) + members + apps(after).map { "u" + $0 }, layout: LaunchpadLayout(items: items))
        r.state.onResize = { [unowned r] id, large in if let s = r.engine.apply(.resize(id, large: large)) { r.state.update(snapshot: s) } }
        return r
    }

    private func page(of id: String, _ r: LiftRig) -> (page: Int, slot: LaunchpadPlacement.Slot)? {
        for p in r.state.pages.indices { if let i = r.state.pages[p].firstIndex(where: { $0.id == id }) { return (p, r.state.slots[p][i]) } }
        return nil
    }

    // MARK: - A page of blocks

    func testHowManyBlocksAPageOfNothingButBlocksHolds() {
        for (c, r, n) in [(3, 2, 1), (4, 4, 4), (10, 8, 20), (3, 3, 1), (5, 2, 2), (4, 2, 2)] {
            XCTAssertEqual(LaunchpadPlacement.place([Bool](repeating: true, count: 40), columns: c, rows: r).count, n, "\(c)x\(r)")
        }
        let (pages, slots) = LaunchpadPaging.pages([Array(0..<5)], columns: 3, rows: 2, isLarge: { _ in true })
        XCTAssertEqual(pages, [[0], [1], [2], [3], [4]], "at 3x2 a block takes a page")
        XCTAssertTrue(slots.allSatisfy { $0 == [LaunchpadPlacement.Slot(column: 0, row: 0, span: 2)] })
    }

    func testAWindowOfNothingButBlocksLaysThemOutAndEachOpens() {
        let items: [LaunchpadLayout.Item] = (0..<7).map { .folder(.init(id: UUID(), name: "F\($0)", apps: ["p\($0)a", "p\($0)b"], large: true)) }
        let ids = (0..<7).flatMap { ["p\($0)a", "p\($0)b"] }
        let r = LiftRig(self, apps: ids, layout: LaunchpadLayout(items: items))
        r.state.regrid(four)
        XCTAssertEqual(r.state.pages.map(\.count), [4, 3])
        for (i, s) in r.state.slots[0].enumerated() {
            let p = r.state.geometry.center(of: s)
            XCTAssertTrue(r.state.pointerDown(p, time: 0), "block \(i)")
            r.state.pointerUp(p, time: 0.05)
            XCTAssertNotNil(r.state.openFolder, "block \(i) opens")
            r.state.closeFolder()
        }
    }

    // MARK: - After a strip

    func testABlockFirstOnAPageAfterAPageThatEndedInAStrip() {
        let r = rig(before: 4, after: 3)
        r.state.regrid(small)
        XCTAssertEqual(r.state.pages[0].count, 4, "subject: the page ended with its two cells free")
        XCTAssertEqual(page(of: folderID.uuidString, r)?.page, 1)
        XCTAssertEqual(page(of: folderID.uuidString, r)?.slot, LaunchpadPlacement.Slot(column: 0, row: 0, span: 2))
        let g = r.state.geometry
        let surface = LaunchpadSurface(geometry: g, page: 0, slots: r.state.slots, gap: nil, folders: [])
        let hole = CGPoint(x: g.gridLeft + 2.5 * g.cellWidth, y: g.gridTop + 1.5 * g.cellHeight)
        XCTAssertEqual(LaunchpadHit.at(hole, in: surface), .gap(address: 4))
    }

    func testABlockCarriedOverTheStripOfThePageBeforeItDoesNotFlickerTheGap() async {
        let r = rig(before: 4, after: 3)
        r.state.regrid(small)
        r.state.settle(step: 1, velocity: 0)
        XCTAssertEqual(r.state.page, 1, "subject: the block's page is shown")
        let from = r.state.geometry.center(of: r.state.slots[1][0])
        XCTAssertTrue(r.state.pointerDown(from, time: 0))
        r.state.pointerMoved(CGPoint(x: from.x + 20, y: from.y), time: 0.01)
        XCTAssertNotNil(r.state.lift, "subject: lifted")
        let edge = CGPoint(x: 10, y: r.state.geometry.gridTop + 20)
        r.state.pointerMoved(edge, time: 1)
        r.state.tick(at: 1 + LaunchpadLiftTiming.edgeFirst + 0.01)
        XCTAssertEqual(r.state.page, 0, "subject: the page turned back")
        let g = r.state.geometry
        let hole = CGPoint(x: g.gridLeft + 2.5 * g.cellWidth, y: g.gridTop + 1.5 * g.cellHeight)
        r.state.pointerMoved(hole, time: 3)
        r.countChanges()
        for k in 1...30 { r.state.tick(at: 3 + 0.05 * Double(k)) }
        XCTAssertLessThanOrEqual(r.changes, 6, "the gap settles and stays: \(r.changes) publications over 30 ticks")
        r.state.pointerUp(hole, time: 6)
        await waitUntil("the lift ended") { !r.state.pointerBusy }
        XCTAssertEqual(page(of: folderID.uuidString, r)?.slot.span, 2, "the block is still a block and on a page")
        XCTAssertEqual(r.state.pages.joined().count, 8)
    }

    // MARK: - Dissolving, hand-edited files

    func testALargeTwoAppFolderThatLosesAnAppDissolvesAndTheFlagGoesWithIt() throws {
        let e = LaunchpadEngine(catalog: RigCatalog(["a", "b", "c"]), launcher: RigLauncher(), store: LayoutStore(directory: scratchDirectory("dissolve")))
        _ = e.read()
        _ = e.apply(.makeFolder(drop: "b", onto: "a", name: "F"))
        guard case .folder(let f)? = e.read().layout.items.first else { return XCTFail("subject: a folder") }
        _ = e.apply(.resize(f.id, large: true))
        let after = try XCTUnwrap(e.apply(.remove("a", fromFolder: f.id)))
        XCTAssertFalse(after.layout.items.contains { if case .folder = $0 { true } else { false } }, "the folder dissolved")
        let text = String(decoding: try JSONEncoder().encode(after.layout), as: UTF8.self)
        XCTAssertFalse(text.contains("large"), text)
        // A hand-edited file: a one-app folder marked large, and an app entry marked large.
        let l = try JSONDecoder().decode(LaunchpadLayout.self, from: Data(#"{"items":[{"folder":{"name":"F","apps":["a"],"large":true}},{"app":"b","large":true}]}"#.utf8))
        let again = String(decoding: try JSONEncoder().encode(l.reconciled(catalog: ["a", "b"], complete: true)), as: UTF8.self)
        XCTAssertFalse(again.contains("large"), again)
    }

    // MARK: - Resizing

    func testAResizeWhileTheCardIsOpenKeepsTheCardAndTheTilesAround() {
        let r = rig()
        r.state.open(folder: folderID)
        XCTAssertEqual(r.state.openFolder, folderID, "subject: open")
        let before = r.state.folderApps
        r.state.resize(folderID, large: false)
        XCTAssertEqual(r.state.openFolder, folderID)
        XCTAssertEqual(r.state.folderApps, before)
        XCTAssertEqual(page(of: folderID.uuidString, r)?.slot.span, 1, "subject: it shrank behind the card")
        let o = r.state.folderOrigin
        XCTAssertTrue(CGRect(origin: .zero, size: r.state.geometry.size).contains(o), "\(o)")
        r.state.resize(folderID, large: true)
        XCTAssertEqual(page(of: folderID.uuidString, r)?.slot.span, 2)
        XCTAssertEqual(r.state.pages.joined().count, 27)
    }

    func testAResizeThenARegridLosesNothingAndKeepsTheSize() {
        for settings in [small, four, big, .standard, small] {
            let r = rig(before: 3, large: false)
            r.state.resize(folderID, large: true)
            XCTAssertEqual(page(of: folderID.uuidString, r)?.slot.span, 2, "subject: large")
            let all = r.state.pages.joined().map(\.id)
            r.state.regrid(settings)
            XCTAssertEqual(r.state.pages.joined().map(\.id), all, "\(settings)")
            XCTAssertEqual(r.state.slots.map(\.count), r.state.pages.map(\.count))
            let at = page(of: folderID.uuidString, r)
            XCTAssertEqual(at?.slot.span, 2, "\(settings): the block is still a block")
            XCTAssertTrue(r.state.pages.indices.contains(r.state.page), "\(settings): the shown page exists")
        }
    }

    // MARK: - Carried over a page's edge, searched while lifted

    func testABlockCarriedOverAPageEdgeLandsWhereItsGapShowed() async {
        let r = rig(large: true, after: 30)
        r.state.regrid(small)
        let from = r.state.geometry.center(of: page(of: folderID.uuidString, r)!.slot)
        XCTAssertTrue(r.state.pointerDown(from, time: 0))
        r.state.pointerMoved(CGPoint(x: from.x + 20, y: from.y), time: 0.01)
        let g = r.state.geometry
        r.state.pointerMoved(CGPoint(x: g.size.width - 10, y: g.gridTop + 20), time: 1)
        r.state.tick(at: 1 + LaunchpadLiftTiming.edgeFirst + 0.01)
        XCTAssertEqual(r.state.page, 1, "subject: over the edge")
        let target = page(of: r.state.pages[1][1].id, r)!
        let at = CGPoint(x: g.center(of: target.slot).x + g.cellWidth * 0.42, y: g.center(of: target.slot).y)
        r.state.pointerMoved(at, time: 3)
        r.state.tick(at: 3.2)
        let gap = page(of: LaunchpadEntry.gapID, r)
        XCTAssertEqual(gap?.page, 1, "subject: the gap is on the page the pointer is on")
        XCTAssertEqual(gap?.slot.span, 2)
        r.state.pointerUp(at, time: 3.3)
        await waitUntil("the lift ended") { !r.state.pointerBusy }
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(page(of: folderID.uuidString, r)?.page, gap?.page)
        XCTAssertEqual(page(of: folderID.uuidString, r)?.slot, gap?.slot)
    }

    func testASearchTypedWhileABlockIsLiftedEndsTheLiftAndTheBlockComesBack() {
        let r = rig()
        let from = r.g.center(of: page(of: folderID.uuidString, r)!.slot)
        XCTAssertTrue(r.state.pointerDown(from, time: 0))
        r.state.pointerMoved(CGPoint(x: from.x + 20, y: from.y), time: 0.01)
        XCTAssertNotNil(r.state.lift, "subject: lifted")
        r.state.search = "u"
        XCTAssertNil(r.state.lift)
        XCTAssertFalse(r.state.pointerBusy)
        XCTAssertNil(page(of: LaunchpadEntry.gapID, r), "no gap is left")
        XCTAssertTrue(r.state.pages.joined().allSatisfy { if case .app = $0 { true } else { false } }, "a search is flat apps")
        r.state.search = ""
        XCTAssertEqual(page(of: folderID.uuidString, r)?.slot.span, 2, "the block is back, large")
        XCTAssertTrue(r.placed.isEmpty, "nothing was written")
    }
}

