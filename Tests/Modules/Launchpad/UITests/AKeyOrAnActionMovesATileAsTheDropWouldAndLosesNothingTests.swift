import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Option+arrow, Option+Shift+arrow and VoiceOver's actions are drops by anchors: each writes the edit the matching drop writes
/// (`LaunchpadLayout.edit(dropping:)`), never an index of the layout, since the window draws a subset of it (a stored page
/// break is not drawn). Across a stored break the tile lands on the near side of the page it enters and the break stays; a
/// folder never nests; a take-out of a two-app folder dissolves it and no app is lost or copied.
@MainActor final class AKeyOrAnActionMovesATileAsTheDropWouldAndLosesNothingTests: XCTestCase {
    private let apps = ["a", "b", "c", "d", "e", "h"]

    private func rig(_ items: [LaunchpadLayout.Item], hidden: Set<String> = []) -> LiftRig {
        var layout = LaunchpadLayout(items: items)
        layout.hidden = hidden
        return LiftRig(self, apps: apps, layout: layout)
    }

    private var broken: [LaunchpadLayout.Item] { [.app("a"), .app("h"), .app("b"), .pageBreak, .app("c"), .app("d"), .app("e")] }

    func testEveryChordWritesTheEditTheMatchingDropWritesWithAHiddenAppAndAStoredBreakBetween() async {
        let cases: [(tile: String, dx: Int, combine: Bool, destination: LaunchpadDropDestination)] = [
            ("b", 1, false, .beside("c", after: false)),   // over the break: first on the next page
            ("c", -1, false, .beside("b", after: true)),   // back over it: last on the previous page
            ("d", -1, false, .beside("c", after: false)),
            ("c", 1, false, .beside("d", after: true)),
            ("a", 1, true, .onto("b")),
            ("d", -1, true, .onto("c")),
        ]
        for (tile, dx, combine, destination) in cases {
            let r = rig(broken, hidden: ["h"])
            let before = r.layout, appsBefore = r.placedApps
            XCTAssertFalse(r.pagesShowAHiddenApp, "subject: the hidden app is not drawn")
            let expected = before.edit(dropping: tile, source: .top, destination: destination,
                                       folderName: LaunchpadCategoryName.folderName(target: nil, dropped: nil))
            XCTAssertNotNil(expected, "\(tile) \(dx): the matching drop is an edit")
            r.choose(tile)
            XCTAssertTrue(r.state.reorderKey(dx: dx, dy: 0, combine: combine))
            await grace()
            XCTAssertEqual(r.placed, expected.map { [$0] } ?? [], "\(tile) \(dx) \(combine): the drop's own edit, once")
            XCTAssertEqual(r.placedApps.sorted(), appsBefore.sorted(), "\(tile): no app lost or copied")
        }
    }

    func testAnArrowDownGoesWhereTheArrowGoesAndWritesTheDropBesideIt() async {
        let ids = (0..<30).map { String(format: "app%02d", $0) }
        let r = LiftRig(self, apps: ids, layout: LaunchpadLayout(items: ids.map { .app($0) }))
        let columns = r.state.geometry.columns
        XCTAssertGreaterThan(r.state.pages[0].count, columns, "subject: a second row")
        r.choose("app00")
        XCTAssertTrue(r.state.reorderKey(dx: 0, dy: 1, combine: false))
        await grace()
        XCTAssertEqual(r.placed, [.place("app00", relativeTo: ids[columns], after: true)])
    }

    func testAcrossAStoredBreakTheTileLandsOnTheNearSideAndTheBreakStays() async {
        let r = rig(broken, hidden: ["h"])
        r.choose("b")
        XCTAssertTrue(r.state.reorderKey(dx: 1, dy: 0, combine: false))
        await grace()
        XCTAssertEqual(r.ids(1).prefix(1), ["b"], "first on the next page")
        XCTAssertEqual(r.layout.items.filter { $0 == .pageBreak }.count, 1, "the break is still one")
        XCTAssertEqual(r.layout.items.firstIndex(of: .pageBreak).map { r.layout.items[$0 + 1] }, .app("b"), "and right before the tile")
        XCTAssertEqual(r.placedApps.sorted(), ["a", "b", "c", "d", "e"], "nothing lost, nothing twice")

        XCTAssertEqual(r.state.page, 1, "subject: the tile is first on the second page, and the choice is on it")
        XCTAssertTrue(r.state.reorderKey(dx: -1, dy: 0, combine: false))
        await grace()
        XCTAssertEqual(r.ids(0).suffix(1), ["b"], "the reverse chord puts it back: last on the previous page")
        XCTAssertEqual(r.layout.items.filter { $0 == .pageBreak }.count, 1)
    }

    func testWhereAPageEndsOnlyBecauseItIsFullTheTileLandsFirstOrLastOnThePageToo() async {
        let ids = (0..<8).map { String(format: "app%02d", $0) }
        let r = LiftRig(self, apps: ids, layout: LaunchpadLayout(items: ids.map { .app($0) }))
        r.state.regrid(LaunchpadGridSettings(automatic: false, rows: 2, columns: 3, iconSize: 80))
        XCTAssertEqual(r.state.pages.map(\.count), [6, 2], "subject: the pages are cut by what a page holds")
        r.choose("app05")
        XCTAssertTrue(r.state.reorderKey(dx: 1, dy: 0, combine: false))
        await grace()
        XCTAssertEqual(r.ids(1).first, "app05", "the last tile of a full page, moved later, is first on the next")
        r.choose("app05")
        XCTAssertTrue(r.state.reorderKey(dx: -1, dy: 0, combine: false))
        await grace()
        XCTAssertEqual(r.ids(0).last, "app05", "and back: last on the page before")
        r.state.reorder(tile: "app02", .page(1))
        await grace()
        XCTAssertEqual(r.ids(1).first, "app02", "a page action lands first on the next page")
        r.state.reorder(tile: "app02", .page(-1))
        await grace()
        XCTAssertEqual(r.ids(0).last, "app02", "and last on the previous")
        XCTAssertEqual(r.placedApps.sorted(), ids, "nothing lost, nothing twice")
    }

    func testAFolderNeverNestsByKeyOrByAction() async {
        let f = UUID(), g = UUID()
        let r = LiftRig(self, apps: apps, layout: LaunchpadLayout(items: [.folder(.init(id: f, name: "F", apps: ["a", "b"])),
                                                                          .folder(.init(id: g, name: "G", apps: ["c", "d"])), .app("e")]))
        let bytes = try? Data(contentsOf: r.layoutFile), before = r.layout
        r.choose(f.uuidString)
        XCTAssertNotNil(r.state.moves(for: f.uuidString)?.later, "subject: a folder can be moved")
        XCTAssertNotNil(r.state.moves(for: "e")?.addToPreviousFolder, "and an app can be added to a folder")
        XCTAssertNil(r.state.moves(for: f.uuidString)?.addToNextFolder, "but a folder is added to none")
        XCTAssertNil(r.state.moves(for: f.uuidString)?.folderWithNext)
        XCTAssertTrue(r.state.reorderKey(dx: 1, dy: 0, combine: true), "the chord is the state's, it only does nothing")
        r.state.reorder(tile: g.uuidString, .combine(dx: 1, dy: 0))
        await grace()
        XCTAssertTrue(r.placed.isEmpty, "no edit was written")
        XCTAssertEqual(try? Data(contentsOf: r.layoutFile), bytes)
        XCTAssertEqual(r.layout, before)
    }

    func testATakeOutOfATwoAppFolderDissolvesItAndLosesNoApp() async {
        let f = UUID()
        let r = LiftRig(self, apps: apps, layout: LaunchpadLayout(items: [.folder(.init(id: f, name: "F", apps: ["a", "b"])), .app("c")]))
        let appsBefore = r.placedApps
        r.state.open(folder: f)
        r.state.move(dx: 1, dy: 0)
        XCTAssertEqual(r.state.selection, 0, "subject: the first app of the card is chosen")
        XCTAssertTrue(r.state.reorderKey(dx: 1, dy: 0, combine: true))
        await grace()
        XCTAssertEqual(r.placed, [.place("a", relativeTo: f.uuidString, after: true)])
        XCTAssertFalse(r.layout.items.contains { if case .folder = $0 { true } else { false } }, "the folder with one app left is no folder")
        XCTAssertEqual(r.placedApps.sorted(), appsBefore.sorted(), "no app lost, none twice")
        XCTAssertNil(r.state.openFolder, "the card closed")
        XCTAssertEqual(r.state.selection.map { r.state.pages[0][$0].id }, "a", "and the app taken out stays chosen")
    }
}

extension LiftRig {
    var pagesShowAHiddenApp: Bool { state.pages.joined().contains { $0.id == "h" } }
}

