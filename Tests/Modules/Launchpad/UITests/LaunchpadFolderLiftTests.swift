import HelmUI
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Folders in the lift: a folder opened by a held tile, drops into it and out of it, the name field, and the names a new
/// folder gets. The pointer and the time are fed by hand; nothing is launched.
@MainActor final class LaunchpadFolderLiftTests: XCTestCase {
    private let six = ["a", "b", "c", "d", "e", "f"]
    private let folderID = UUID()
    /// a, a folder of b and c, d, e, f.
    private func rig() -> LiftRig {
        LiftRig(self, apps: six, layout: LaunchpadLayout(items: [.app("a"), .folder(.init(id: folderID, name: "F", apps: ["b", "c"])),
                                                                 .app("d"), .app("e"), .app("f")]))
    }
    private func card(_ r: LiftRig, count: Int) -> LaunchpadSurface.Card { LaunchpadSurface.Card(geometry: r.g, count: count) }

    /// `a` lifted and held on the folder until it opens.
    private func openedByALift(_ r: LiftRig) {
        r.lift(0)
        r.state.pointerMoved(r.core(1), time: 1)
        r.state.tick(at: 1.31)
        XCTAssertEqual(r.state.lift?.onto, folderID.uuidString, "the control: armed before it opens")
        r.state.tick(at: 1.71)
    }

    func testAFolderHeldOnOpensWithTheGapAtTheEndOfItsApps() {
        let r = rig()
        openedByALift(r)
        XCTAssertEqual(r.state.openFolder, folderID)
        XCTAssertEqual(r.state.cardEntries.map(\.id), ["b", "c", LaunchpadEntry.gapID])
        XCTAssertNil(r.state.lift?.onto)
        XCTAssertNotNil(r.state.lift, "still carried")
    }

    func testAReleaseInsideTheOpenCardWritesAnAddAtTheGapAndTheFolderStaysOpen() async {
        let r = rig()
        openedByALift(r)
        let c = card(r, count: 3)
        r.state.pointerMoved(c.center(ofSlot: 0), time: 2)
        r.state.tick(at: 2.13)
        XCTAssertEqual(r.state.cardEntries.map(\.id), [LaunchpadEntry.gapID, "b", "c"])
        r.state.pointerUp(c.center(ofSlot: 0), time: 2.2)
        await waitUntil("the app joined") { r.state.folderApps.map(\.id) == ["a", "b", "c"] }
        XCTAssertEqual(r.placed, [.add("a", toFolder: folderID, relativeTo: "b", after: false)])
        XCTAssertEqual(r.state.openFolder, folderID)
        XCTAssertEqual(r.ids(), [folderID.uuidString, "d", "e", "f"])
    }

    func testAReleaseInTheCardOnTheGapWhereItStartedWritesAnAddToTheEnd() async {
        let r = rig()
        openedByALift(r)
        let c = card(r, count: 3)
        r.state.pointerMoved(c.center(ofSlot: 0), time: 2)
        r.state.pointerUp(c.center(ofSlot: 2), time: 2.05)
        await waitUntil("the app joined") { r.state.folderApps.map(\.id) == ["b", "c", "a"] }
        XCTAssertEqual(r.placed, [.add("a", toFolder: folderID, relativeTo: "c", after: true)])
    }

    func testLeavingTheCardClosesItAndTheLiftGoesOnOverTheGrid() async {
        let r = rig()
        openedByALift(r)
        let c = card(r, count: 3)
        r.state.pointerMoved(c.center(ofSlot: 1), time: 2)
        r.state.pointerMoved(r.margin(4), time: 2.5)
        r.state.tick(at: 2.76)
        XCTAssertNil(r.state.openFolder, "the card closed")
        XCTAssertNotNil(r.state.lift, "the app is still carried")
        XCTAssertEqual(r.ids(), [LaunchpadEntry.gapID, folderID.uuidString, "d", "e", "f"], "its gap is where it was lifted from")
        r.state.pointerMoved(r.margin(4), time: 3)
        r.state.tick(at: 3.13)
        r.state.pointerUp(r.margin(4), time: 3.2)
        await waitUntil("the edit was written") { r.placed.count == 1 }
        XCTAssertEqual(r.placed, [.place("a", relativeTo: "f", after: true)])
    }

    func testAnAppLiftedOutOfAFolderAndLetGoOnTheGridIsPlacedThereAndATwoAppFolderDissolves() async {
        let r = rig()
        r.state.open(folder: folderID)
        let c = card(r, count: 2)
        XCTAssertTrue(r.state.pointerDown(c.center(ofSlot: 0), time: 0), "a press on a tile of the open card is taken")
        r.state.pointerMoved(CGPoint(x: c.center(ofSlot: 0).x + 20, y: c.center(ofSlot: 0).y), time: 0.01)
        XCTAssertEqual(r.state.lift?.entry.id, "b")
        XCTAssertEqual(r.state.cardEntries.map(\.id), [LaunchpadEntry.gapID, "c"])
        r.state.pointerMoved(r.margin(0), time: 1)
        r.state.tick(at: 1.26)
        XCTAssertNil(r.state.openFolder)
        XCTAssertEqual(r.ids(), ["a", folderID.uuidString, LaunchpadEntry.gapID, "d", "e", "f"], "the gap takes its place after the folder")
        r.state.pointerMoved(r.margin(0), time: 1.3)
        r.state.tick(at: 1.43)
        XCTAssertEqual(r.ids(), [LaunchpadEntry.gapID, "a", folderID.uuidString, "d", "e", "f"])
        r.state.pointerUp(r.margin(0), time: 1.5)
        await waitUntil("the app was placed") { r.ids() == ["b", "a", "c", "d", "e", "f"] }
        XCTAssertEqual(r.placed, [.place("b", relativeTo: "a", after: false)])
    }

    func testAnAppLiftedFromAFolderAndLetGoInsideItsCardReordersItThere() async {
        let r = rig()
        r.state.open(folder: folderID)
        let c = card(r, count: 2)
        _ = r.state.pointerDown(c.center(ofSlot: 0), time: 0)
        r.state.pointerMoved(CGPoint(x: c.center(ofSlot: 0).x + 20, y: c.center(ofSlot: 0).y), time: 0.01)
        r.state.pointerMoved(c.center(ofSlot: 1), time: 1)
        r.state.tick(at: 1.13)
        XCTAssertEqual(r.state.cardEntries.map(\.id), ["c", LaunchpadEntry.gapID])
        r.state.pointerUp(c.center(ofSlot: 1), time: 1.2)
        await waitUntil("the folder was reordered") { r.state.folderApps.map(\.id) == ["c", "b"] }
        XCTAssertEqual(r.placed, [.moveInFolder("b", toIndex: 1)])
    }

    func testAnEscDuringALiftInACardCancelsTheLiftAndKeepsTheCardOpen() {
        let r = rig()
        openedByALift(r)
        r.state.escape()
        XCTAssertNil(r.state.lift)
        XCTAssertEqual(r.state.openFolder, folderID)
        XCTAssertEqual(r.state.cardEntries.map(\.id), ["b", "c"], "no gap left behind")
        XCTAssertEqual(r.closes, 0)
        XCTAssertTrue(r.placed.isEmpty)
    }

    func testAFolderIsNotOpenedByAFolderCarried() {
        let r = LiftRig(self, apps: six, layout: LaunchpadLayout(items: [.folder(.init(id: folderID, name: "F", apps: ["b", "c"])),
                                                                         .folder(.init(id: UUID(), name: "G", apps: ["d", "e"])), .app("a"), .app("f")]))
        r.lift(0)
        r.state.pointerMoved(r.core(1), time: 1)
        r.state.tick(at: 1.31)
        r.state.tick(at: 2)
        XCTAssertNil(r.state.openFolder, "folders never nest")
    }

    // MARK: The name

    private func named(_ r: LiftRig) {
        r.state.open(folder: folderID)
        r.state.beginRenaming(selectAll: false)
    }

    func testReturnCommitsTheDraftAndTheFolderStaysOpen() async {
        let r = rig()
        named(r)
        r.state.nameDraft = "  Work  "
        XCTAssertTrue(r.state.handleNameKey(36))
        XCTAssertEqual(r.renamed, ["Work"])
        XCTAssertFalse(r.state.renaming)
        XCTAssertEqual(r.state.openFolder, folderID)
        XCTAssertEqual(r.state.folderName, "Work")
    }

    func testABlankDraftRevertsOnReturnAndWritesNothing() {
        let r = rig()
        named(r)
        r.state.nameDraft = "   "
        XCTAssertTrue(r.state.handleNameKey(76))
        XCTAssertEqual(r.state.nameDraft, "F")
        XCTAssertTrue(r.renamed.isEmpty)
    }

    func testClosingTheFolderCommitsAChangedDraftAndNotAnUnchangedOne() {
        let r = rig()
        named(r)
        r.state.nameDraft = "Tools"
        r.state.closeFolder()
        XCTAssertEqual(r.renamed, ["Tools"])
        r.state.open(folder: folderID)
        r.state.closeFolder()
        XCTAssertEqual(r.renamed, ["Tools"], "the control: an unchanged name is not written again")
    }

    func testANewFolderOpensWithItsNameFieldInHandAndTheTextSelected() async {
        let r = rig()
        r.categorize(["a": "public.app-category.action-games"])
        r.lift(0)
        r.state.pointerMoved(r.core(4), time: 1)
        r.state.tick(at: 1.31)
        r.state.pointerUp(r.core(4), time: 1.4)
        await waitUntil("the folder opened") { r.state.openFolder != nil }
        XCTAssertTrue(r.state.renaming)
        XCTAssertTrue(r.state.selectNameOnFocus)
        XCTAssertEqual(r.state.nameDraft, L(.categoryGames), "the dropped app's category, the target has none")
        XCTAssertEqual(r.state.folderName, r.state.nameDraft)
    }

    func testTheNewFoldersNameIsTheTargetsCategoryThenTheDroppedAppsThenOther() async {
        let cases: [([String: String], String)] = [
            (["a": "public.app-category.games", "e": "public.app-category.utilities"], HelmWord.utilities),
            (["a": "public.app-category.music"], L(.categoryMusic)),
            (["a": "x", "e": "public.app-category.nonsense"], L(.categoryOther)),
        ]
        for (categories, expected) in cases {
            let r = rig()
            r.categorize(categories)
            r.lift(0)
            r.state.pointerMoved(r.core(3), time: 1)
            r.state.tick(at: 1.31)
            r.state.pointerUp(r.core(3), time: 1.4)
            await waitUntil("the edit was written") { r.placed.count == 1 }
            XCTAssertEqual(r.placed, [.makeFolder(drop: "a", onto: "e", name: expected)], "\(categories)")
        }
        XCTAssertEqual(Set([HelmWord.utilities, L(.categoryMusic), L(.categoryOther)]).count, 3, "the three are three different words")
    }

    // MARK: A card with pages

    private var cardCapacity: Int { LaunchpadSurface.Card(geometry: LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 0), count: 10_000).capacity }

    /// A folder of `count` apps, opened by id (not by a lift), on its page `page`.
    private func pagedRig(_ count: Int, page: Int) -> LiftRig {
        let apps = (0..<count).map { "f\($0)" }
        let r = LiftRig(self, apps: ["x"] + apps, layout: LaunchpadLayout(items: [.folder(.init(id: folderID, name: "F", apps: apps)), .app("x")]))
        r.state.open(folder: folderID)
        r.state.go(to: page)
        return r
    }

    func testAnAppLiftedFromTheSecondPageOfACardIsThatAppAndLetGoWhereItWasWritesNothing() async {
        let cap = cardCapacity
        let r = pagedRig(cap + 4, page: 1)
        let c = LaunchpadSurface.Card(geometry: r.g, count: cap + 4, page: 1)
        let from = c.center(ofSlot: 1)
        XCTAssertTrue(r.state.pointerDown(from, time: 0), "a press on a tile of a paged card's second page is taken")
        r.state.pointerMoved(CGPoint(x: from.x + 20, y: from.y), time: 0.01)
        XCTAssertEqual(r.state.lift?.entry.id, "f\(cap + 1)", "the tile under the pointer, by its place in the whole list")
        XCTAssertEqual(r.state.cardEntries.firstIndex(of: .gap), cap + 1)
        r.state.pointerUp(from, time: 0.5)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(r.placed.isEmpty, "dropped on its own gap: no edit")
        XCTAssertNil(r.state.lift)
        XCTAssertEqual(r.state.cardEntries.map(\.id), (0..<(cap + 4)).map { "f\($0)" }, "the card is as it was")
    }

    func testATurnUnderALiftFromTheSecondPageSeatsTheGapOnTheFirstAndTheMoveIsWrittenThere() async {
        let cap = cardCapacity
        let r = pagedRig(cap + 4, page: 1)
        let c = LaunchpadSurface.Card(geometry: r.g, count: cap + 4, page: 1)
        let from = c.center(ofSlot: 1)
        _ = r.state.pointerDown(from, time: 0)
        r.state.pointerMoved(CGPoint(x: from.x + 20, y: from.y), time: 0.01)
        let strip = CGPoint(x: c.origin.x - 5, y: c.rect.midY)
        r.state.pointerMoved(strip, time: 1)
        r.state.tick(at: 1.61)
        XCTAssertEqual(r.state.cardPage, 0)
        XCTAssertEqual(r.state.cardEntries.firstIndex(of: .gap), cap - 1, "backward: the end of page 0, the carried app's old place is gone")
        r.state.pointerUp(strip, time: 1.7)
        await waitUntil("the folder was reordered") { r.state.folderApps.first { $0.id == "f\(cap + 1)" } != nil && r.placed.count == 1 }
        XCTAssertEqual(r.placed.count, 1)
        let order = r.state.folderApps.map(\.id)
        XCTAssertEqual(order.firstIndex(of: "f\(cap + 1)"), cap - 1, "it landed on the page the person was looking at")
        XCTAssertEqual(r.state.openFolder, folderID)
    }
}
