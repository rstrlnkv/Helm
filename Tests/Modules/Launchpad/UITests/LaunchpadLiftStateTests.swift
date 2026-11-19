import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// What the state does with the lift's effects: the pages it shows, what a release writes, what it refuses, what a snapshot
/// that lands mid-lift does. The pointer and the time are fed by hand; nothing is launched.
@MainActor final class LaunchpadLiftStateTests: XCTestCase {
    private let six = ["a", "b", "c", "d", "e", "f"]
    private func rig(_ apps: [String]? = nil, layout: LaunchpadLayout? = nil) -> LiftRig { LiftRig(self, apps: apps ?? six, layout: layout) }
    private func ids(_ n: Int) -> [String] { (0..<n).map { String(format: "app%02d", $0) } }

    // MARK: Pages

    func testPagesAreTheItemsCutAtEachBreakThenChunkedByWhatAPageHolds() {
        let r = rig(ids(70), layout: LaunchpadLayout(items: ids(3).map { .app($0) } + [.pageBreak] + ids(70).dropFirst(3).map { .app($0) }))
        let capacity = r.g.capacity
        XCTAssertEqual(r.state.pages.map(\.count), [3, capacity, capacity, 67 - 2 * capacity].filter { $0 > 0 })
        XCTAssertEqual(r.state.pages[1].first?.id, "app03", "the break is where a page begins")
    }

    func testTheArrowKeysCountOverTheListAcrossAShortPage() {
        let r = rig(layout: LaunchpadLayout(items: [.app("a"), .app("b"), .pageBreak, .app("c"), .app("d"), .app("e"), .app("f")]))
        XCTAssertEqual(r.state.pages.map(\.count), [2, 4])
        XCTAssertEqual(r.state.flatIndex(page: 1, slot: 0), 2)
        r.state.move(dx: 1, dy: 0)
        r.state.move(dx: 1, dy: 0)
        r.state.move(dx: 1, dy: 0)
        XCTAssertEqual(r.state.selection, 2)
        XCTAssertEqual(r.state.page, 1, "the choice is on the second page: the page follows it")
    }

    // MARK: Whether a press is taken

    func testAClickWithoutMovementLaunchesTheAppAndAFolderOpens() {
        let r = rig(layout: LaunchpadLayout(items: [.app("a"), .folder(.init(id: UUID(), name: "F", apps: ["b", "c"])), .app("d")]))
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 0))
        XCTAssertEqual(r.state.pressedID, "a", "the press wash")
        r.state.pointerUp(r.core(0), time: 0.1)
        XCTAssertEqual(r.launched, ["a"])
        XCTAssertNil(r.state.pressedID)
        XCTAssertTrue(r.state.pointerDown(r.core(1), time: 1))
        r.state.pointerUp(r.core(1), time: 1.1)
        XCTAssertNotNil(r.state.openFolder)
        XCTAssertEqual(r.launched, ["a"])
    }

    func testAPressIsLeftToTheViewsWhereNothingMayBeLifted() {
        let r = rig()
        XCTAssertFalse(r.state.pointerDown(CGPoint(x: 640, y: 10), time: 0), "off the tiles")
        XCTAssertFalse(r.state.pointerDown(r.core(9), time: 0), "an empty cell")
        r.state.search = "a"
        XCTAssertFalse(r.state.liftAllowed)
        XCTAssertFalse(r.state.pointerDown(r.core(0), time: 0), "a search's hits are not the arrangement")
        r.state.search = ""
        XCTAssertTrue(r.state.liftAllowed, "the control: the same press is taken without a search")
        r.state.launched("a")
        XCTAssertFalse(r.state.pointerDown(r.core(0), time: 0), "a launch is under way")
        r.state.launchFailed()
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 0))
        r.state.cancelLift()
        r.state.setShown(false)
        XCTAssertFalse(r.state.pointerDown(r.core(0), time: 0), "the window is closing")
    }

    func testASearchTypedMidLiftEndsTheLift() {
        let r = rig()
        r.lift(0)
        r.state.search = "b"
        XCTAssertNil(r.state.lift)
        XCTAssertFalse(r.state.pointerBusy)
    }

    // MARK: Drops

    func testAReleaseBesideWritesAPlaceByAnchorAndAReleaseOnTheGapWritesNothing() async {
        let r = rig()
        r.lift(3)
        r.state.pointerUp(r.core(3), time: 0.5)
        XCTAssertTrue(r.placed.isEmpty, "back where it was")
        XCTAssertEqual(r.ids(), six)
        r.lift(3, at: 1)
        r.state.pointerMoved(r.margin(0), time: 2)
        r.state.tick(at: 2.2)
        XCTAssertEqual(r.ids(), [LaunchpadEntry.gapID, "a", "b", "c", "e", "f"])
        r.state.pointerUp(r.margin(0), time: 2.3)
        await waitUntil("the edit was written") { r.placed.count == 1 }
        await waitUntil("the page took the answer") { r.ids() == ["d", "a", "b", "c", "e", "f"] }
        XCTAssertEqual(r.placed, [.place("d", relativeTo: "a", after: false)], "the first of its page goes before the page's first")
    }

    func testAReleaseOutsideTheGridKeepsTheLastGap() async {
        let r = rig()
        r.lift(0)
        r.state.pointerMoved(r.margin(2), time: 1)
        r.state.tick(at: 1.2)
        r.state.pointerMoved(CGPoint(x: 600, y: r.g.size.height - 5), time: 2)
        r.state.pointerUp(CGPoint(x: 600, y: r.g.size.height - 5), time: 2.1)
        await waitUntil("the edit was written") { r.placed.count == 1 }
        await waitUntil("the page took the answer") { r.ids() == ["b", "c", "a", "d", "e", "f"] }
        XCTAssertEqual(r.placed, [.place("a", relativeTo: "c", after: true)])
    }

    func testAReleaseOntoAnAppMakesAFolderAndOpensIt() async {
        let r = rig()
        r.lift(0)
        r.state.pointerMoved(r.core(2), time: 1)
        r.state.tick(at: 1.31)
        XCTAssertEqual(r.state.lift?.onto, "c", "the target is armed")
        r.state.pointerUp(r.core(2), time: 1.4)
        await waitUntil("the folder opened") { r.state.openFolder != nil }
        XCTAssertEqual(r.placed, [.makeFolder(drop: "a", onto: "c", name: LaunchpadCategoryName.folderName(target: nil, dropped: nil))])
        XCTAssertEqual(r.state.folderApps.map(\.id), ["c", "a"])
        XCTAssertEqual(r.ids(), ["b", r.state.openFolder!.uuidString, "d", "e", "f"])
    }

    func testAReleaseOntoAFolderAddsToIt() async {
        let folder = LaunchpadLayout.Folder(id: UUID(), name: "F", apps: ["b", "c"])
        let r = rig(layout: LaunchpadLayout(items: [.app("a"), .folder(folder), .app("d"), .app("e"), .app("f")]))
        r.lift(0)
        r.state.pointerMoved(r.core(1), time: 1)
        r.state.tick(at: 1.31)
        r.state.pointerUp(r.core(1), time: 1.4)
        await waitUntil("the app joined") { r.placed.count == 1 && r.ids() == [folder.id.uuidString, "d", "e", "f"] }
        XCTAssertEqual(r.placed, [.add("a", toFolder: folder.id, relativeTo: nil, after: true)])
    }

    func testHoldingTheLastPagesRightEdgeMakesAPageOfItsOwnAndAReleaseThereWritesNewPage() async {
        let r = rig()
        r.lift(1)
        let edge = CGPoint(x: r.g.size.width - 10, y: r.g.gridTop + 20)
        r.state.pointerMoved(edge, time: 1)
        r.state.tick(at: 1.61)
        XCTAssertEqual(r.state.pages.count, 2)
        XCTAssertEqual(r.state.pages[1].map(\.id), [LaunchpadEntry.gapID])
        XCTAssertEqual(r.state.page, 1, "the new page is shown")
        r.state.tick(at: 2.6)
        XCTAssertEqual(r.state.pages.count, 2, "held longer, no third page")
        r.state.pointerUp(edge, time: 3)
        await waitUntil("the edit was written") { r.placed.count == 1 }
        await waitUntil("the page took the answer") { r.state.pages.count == 2 && r.state.pages[1].map(\.id) == ["b"] }
        XCTAssertEqual(r.placed, [.newPage(moving: "b")])
    }

    func testTheEdgeTurnsToTheNextPageWhenThereIsOne() {
        let r = rig(ids(40))
        r.lift(0)
        let edge = CGPoint(x: r.g.size.width - 10, y: r.g.gridTop + 20)
        r.state.pointerMoved(edge, time: 1)
        r.state.tick(at: 1.61)
        XCTAssertEqual(r.state.page, 1)
        XCTAssertEqual(r.state.pages.count, 2, "no new page: there was one to turn to")
    }

    // MARK: Cancels

    func testALeftButtonNoLongerDownOnATickEndsTheLiftAndWritesNothing() {
        let r = rig()
        r.lift(0)
        r.state.pointerMoved(r.margin(3), time: 1)
        r.state.buttonDown = { false }
        r.state.tick(at: 1.2)
        XCTAssertNil(r.state.lift)
        XCTAssertEqual(r.ids(), six)
        XCTAssertTrue(r.placed.isEmpty)
    }

    func testShutdownMidLiftLeavesNoLiftAndWritesNothing() async {
        let r = rig()
        r.lift(0)
        r.state.pointerMoved(r.margin(3), time: 1)
        r.state.shutdown()
        XCTAssertNil(r.state.lift)
        XCTAssertFalse(r.state.pointerBusy)
        XCTAssertEqual(r.ids(), six)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(r.placed.isEmpty)
    }

    func testASnapshotThatLandsMidLiftKeepsTheLiftAndTheGapByItsNeighbour() {
        let r = rig()
        r.lift(0)
        r.state.pointerMoved(r.margin(3), time: 1)
        r.state.tick(at: 1.2)
        XCTAssertEqual(r.ids(), ["b", "c", "d", LaunchpadEntry.gapID, "e", "f"])
        r.catalog.reading = CatalogReading(apps: (six + ["g"]).map { CatalogApp(id: $0, name: $0, path: "/Applications/\($0).app") }, complete: true)
        r.state.update(snapshot: r.engine.read())
        XCTAssertEqual(r.state.lift?.entry.id, "a")
        XCTAssertEqual(r.ids(), ["b", "c", "d", LaunchpadEntry.gapID, "e", "f", "g"], "the gap stays after d")
    }

    func testASnapshotThatTakesTheCarriedAppAwayCancelsTheLift() {
        let r = rig()
        r.lift(0)
        r.catalog.reading = CatalogReading(apps: six.dropFirst().map { CatalogApp(id: $0, name: $0, path: "/Applications/\($0).app") }, complete: true)
        r.state.update(snapshot: r.engine.read())
        XCTAssertNil(r.state.lift)
        XCTAssertFalse(r.state.pointerBusy)
        XCTAssertEqual(r.ids(), ["b", "c", "d", "e", "f"])
        XCTAssertTrue(r.placed.isEmpty)
    }

    // MARK: An app whose id is the gap's old one; a mouse-up that never came

    func testAnAppNamedGapIsNotTheGapTheDropAnchorsOnItsNeighbourAndThePreviewMovesTheRightTile() async {
        let r = rig(["a", "gap", "c", "d", "e", "f"])
        r.lift(0)
        XCTAssertEqual(r.ids(), [LaunchpadEntry.gapID, "gap", "c", "d", "e", "f"], "the app's tile is its own, beside the gap")
        r.state.pointerMoved(r.margin(3), time: 1)
        r.state.tick(at: 1.2)
        XCTAssertEqual(r.ids(), ["gap", "c", "d", LaunchpadEntry.gapID, "e", "f"], "the preview moved the app a left of d, not the app named gap")
        r.state.pointerUp(r.margin(3), time: 1.3)
        await waitUntil("the edit was written") { r.placed.count == 1 }
        XCTAssertEqual(r.placed, [.place("a", relativeTo: "d", after: true)])
        XCTAssertNotEqual(LaunchpadEntry.gapID, "gap")
    }

    func testAPressWhoseMouseUpWasLostIsReleasedByTheCheckAndALiftToo() async {
        var m = LaunchpadLift()
        let g = LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 0)
        let surface = LaunchpadSurface(geometry: g, page: 0, pageCounts: [10], gap: nil)
        XCTAssertNil(m.stuckWake, "idle: nothing to look at")
        _ = m.feed(.down, at: g.center(ofSlot: 0), surface: surface, time: 1)
        XCTAssertEqual(m.stuckWake ?? 0, 1 + LaunchpadLiftTiming.stuckCheck, accuracy: 1e-9)
        _ = m.feed(.tick, at: g.center(ofSlot: 0), surface: surface, time: 1.5)
        XCTAssertEqual(m.stuckWake ?? 0, 1.5 + LaunchpadLiftTiming.stuckCheck, accuracy: 1e-9, "a look moves the next one on: no zero-delay loop")

        let r = rig()
        r.state.clock = { 0.5 }
        r.state.buttonDown = { false }
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 0))
        XCTAssertTrue(r.state.pointerBusy)
        await waitUntil("the check let the press go") { !r.state.pointerBusy }
        XCTAssertTrue(r.launched.isEmpty)

        let l = rig()
        l.state.clock = { 0.5 }
        l.lift(0)
        XCTAssertNotNil(l.state.lift)
        l.state.buttonDown = { false }
        await waitUntil("the check ended the lift") { l.state.lift == nil }
        XCTAssertTrue(l.placed.isEmpty)
        XCTAssertEqual(l.ids(), six)
    }
}
