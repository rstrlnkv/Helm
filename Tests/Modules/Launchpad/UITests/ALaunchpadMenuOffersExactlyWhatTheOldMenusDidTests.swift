import AppKit
import HelmUI
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The context menus the panel pops (`LaunchpadScreenState.menu(at:)`, `LaunchpadMenu`, `LaunchpadNSMenu`) offer what the SwiftUI `.contextMenu`s did and nothing
/// more: an app's Hide, Move to category (own category on top, one row checked) and files, Edit where the mode can begin, Remove only for a removable app in the mode;
/// the Hidden card's Show; a folder's other size and Edit; a category block's large icon's app; the background's Edit and where it is off. Each case first proves the
/// tile or the point it asks about is there (a menu that is not nil, a count above zero). The pop itself, and the delay that came of SwiftUI rebuilding the open
/// menu, are a live check, not a test.
@MainActor final class ALaunchpadMenuOffersExactlyWhatTheOldMenusDidTests: XCTestCase {
    private let folderID = UUID()
    private let music = "public.app-category.music"

    /// a, a folder of b and c, d, e, f.
    private func rig(removable: Set<String> = [], large: Bool = false, overrides: [String: LaunchpadCategoryTarget] = [:]) -> LiftRig {
        var layout = LaunchpadLayout(items: [.app("a"), .folder(.init(id: folderID, name: "F", apps: ["b", "c"], large: large)), .app("d"), .app("e"), .app("f")])
        layout.categoryOverrides = overrides
        let r = LiftRig(self, apps: ["a", "b", "c", "d", "e", "f"], layout: layout)
        r.state.onVerdicts = { candidates in candidates.map { removable.contains($0.bundleID) ? .removable : .refused(.notOffered) } }
        return r
    }

    private func centre(_ r: LiftRig, _ id: String) throws -> CGPoint {
        let i = try XCTUnwrap(r.state.pages[0].firstIndex { $0.id == id }, "the control: \(id) is on the page")
        let f = r.g.frame(of: r.state.slots[0][i]).offsetBy(dx: 0, dy: r.g.gridTop)
        return CGPoint(x: f.midX, y: f.midY)
    }

    private func menu(_ r: LiftRig, _ id: String) throws -> LaunchpadMenu { try XCTUnwrap(r.state.menu(at: centre(r, id)), "the control: \(id) has a menu") }

    private func moveRows(_ menu: LaunchpadMenu) throws -> [LaunchpadMenu.Item] {
        for item in menu.items { if case .submenu(let title, let rows) = item { XCTAssertEqual(title, LpStr.moveToCategory); return rows } }
        throw XCTSkip("no Move submenu")
    }

    private func checked(_ rows: [LaunchpadMenu.Item]) -> [LaunchpadMenuAction] {
        rows.compactMap { if case .action(_, let action, _, true) = $0 { action } else { nil } }
    }

    private func files(_ id: String) -> [LaunchpadMenu.Item] {
        [.separator, .action(title: HelmWord.showInFinder, .reveal(id)), .action(title: LpStr.copyPath, .copyPath(id))]
    }

    private func isMove(_ menu: LaunchpadMenu) -> Bool { menu.items.contains { if case .submenu = $0 { true } else { false } } }

    // MARK: - An app in the grid

    func testAnAppInTheGridOffersHideMoveFilesAndEditInThatOrder() throws {
        let r = rig()
        let m = try menu(r, "a")
        let rows = try moveRows(m)
        let choices = LaunchpadCategoryName.choices()
        XCTAssertGreaterThan(choices.count, 1, "the control: there are categories to move to")
        XCTAssertEqual(m.items, [.action(title: LpStr.hide, .hide("a")), .submenu(title: LpStr.moveToCategory, rows)] + files("a") + [.action(title: HelmWord.edit, .beginEditing)])
        XCTAssertEqual(rows.count, choices.count + 2, "own category, a separator, one row per category")
        XCTAssertEqual(rows[0], .action(title: LpStr.ownCategory, .move("a", nil), enabled: false, checked: false), "an app that is not moved has nothing to return to")
        XCTAssertEqual(rows[1], .separator)
        XCTAssertEqual(rows.dropFirst(2).map { if case .action(let t, let a, _, _) = $0 { "\(t)|\(a)" } else { "" } },
                       choices.map { "\($0.title)|\(LaunchpadMenuAction.move("a", $0.target))" })
        XCTAssertEqual(choices.last?.target, .others, "Others last")
        XCTAssertEqual(checked(rows), [.move("a", .others)], "no category in the catalog: it is in Others, and only there")
    }

    func testAnUnmovedAppChecksItsOwnCategoryAndAMovedOneTheTargetWithTheUndoOn() throws {
        let r = rig()
        r.categorize(["a": music])
        XCTAssertEqual(checked(try moveRows(menu(r, "a"))), [.move("a", .category(.music))])

        let moved = rig(overrides: ["a": .category(.weather)])
        XCTAssertEqual(moved.state.moved["a"], .category(.weather), "the control: the state knows the move")
        let rows = try moveRows(menu(moved, "a"))
        XCTAssertEqual(rows[0], .action(title: LpStr.ownCategory, .move("a", nil), enabled: true, checked: false))
        XCTAssertEqual(checked(rows), [.move("a", .category(.weather))], "the check is on the target, not on the app's own category")
        XCTAssertEqual(checked(try moveRows(menu(moved, "d"))), [.move("d", .others)], "another app is unaffected")
    }

    func testTheMenuOfATileAndTheMenuVoiceOverAsksForAreTheSameAndPopWhereTheTileIs() throws {
        let r = rig()
        let found = try XCTUnwrap(r.state.menu(forTile: "a"))
        XCTAssertEqual(found.menu, try menu(r, "a"))
        let at = try centre(r, "a")
        XCTAssertEqual(found.anchor.x, at.x, accuracy: 0.5)
        XCTAssertEqual(found.anchor.y, at.y, accuracy: 0.5)
        XCTAssertNil(r.state.menu(forTile: "nobody"))
    }

    // MARK: - The Hidden card

    func testAnAppInTheUnlockedHiddenCardOffersShowAndItsFilesAndNothingElse() async throws {
        let rig = HiddenRig(.immediate(.success))
        rig.state.open(folder: LaunchpadHiddenBlock.id)
        await rig.gate.settled()
        XCTAssertEqual(rig.gate.phase, .unlocked, "the subject: unlocked and the card open")
        XCTAssertEqual(rig.state.cardEntries.map(\.id), [HiddenRig.hidden])
        let card = LaunchpadSurface.Card(geometry: rig.state.geometry, count: 1, page: 0)
        let m = try XCTUnwrap(rig.state.menu(at: card.center(ofSlot: 0)))
        XCTAssertEqual(m.items, [.action(title: HelmWord.show, .show(HiddenRig.hidden))] + files(HiddenRig.hidden), "no Hide, no Move, no Edit")
        XCTAssertFalse(isMove(m))
        XCTAssertNil(rig.state.menu(at: CGPoint(x: 4, y: 4)), "a card is open: not even the background's Edit")
    }

    func testTheLockedHiddenBlockAndABlocksChromeHaveNoMenuWhereAnAppsBlockHasOne() {
        let rig = HiddenRig(.immediate(.success))
        let g = rig.state.geometry
        let slots = rig.state.slots[0]
        XCTAssertEqual(rig.state.pages[0].last?.id, rig.hiddenTile, "the control: the Hidden block is last")
        func icon(_ slot: Int) -> CGPoint {
            let block = g.frame(of: slots[slot]).offsetBy(dx: 0, dy: g.gridTop)
            let f = LaunchpadCategoryMark.frame(ofQuadrant: 0, size: g.largeMark, edge: g.largeEdge)
            return CGPoint(x: block.midX - g.largeMark / 2 + f.midX, y: block.minY + g.iconTop + f.midY)
        }
        XCTAssertNotNil(rig.state.menu(at: icon(0)), "the control: the first block's first icon has a menu")
        XCTAssertNil(rig.state.menu(at: icon(slots.count - 1)), "the Hidden block names nobody")
    }

    // MARK: - A folder

    func testAFolderOffersItsOtherSizeAndEditAndFollowsItsSize() throws {
        let small = try menu(rig(), folderID.uuidString)
        XCTAssertEqual(small.items, [.action(title: LpStr.enlargeFolder, .resize(folderID, large: true)), .action(title: HelmWord.edit, .beginEditing)])
        let large = try menu(rig(large: true), folderID.uuidString)
        XCTAssertEqual(large.items, [.action(title: LpStr.shrinkFolder, .resize(folderID, large: false)), .action(title: HelmWord.edit, .beginEditing)])
        XCTAssertNotEqual(LpStr.enlargeFolder, LpStr.shrinkFolder)
    }

    // MARK: - The edit mode

    func testInTheModeThereIsNoEditAndRemoveIsOnlyForARemovableApp() async throws {
        let r = rig(removable: ["a"])
        r.state.beginEditing()
        XCTAssertTrue(r.state.editing, "the subject")
        await waitUntil("the answer") { r.state.removable == ["a"] }
        let removable = try menu(r, "a")
        XCTAssertEqual(removable.items.last, .action(title: LpStr.removeAction, .askToRemove("a")))
        XCTAssertEqual(removable.items.count, 2 + files("a").count + 1, "Hide, Move, files, Remove and no Edit")
        XCTAssertFalse(removable.items.contains(.action(title: HelmWord.edit, .beginEditing)))
        let other = try menu(r, "d")
        XCTAssertEqual(other.items, [.action(title: LpStr.hide, .hide("d")), .submenu(title: LpStr.moveToCategory, try moveRows(other))] + files("d"),
                       "an app the Uninstaller does not offer has no Remove")
        let folder = try menu(r, folderID.uuidString)
        XCTAssertEqual(folder.items, [.action(title: LpStr.enlargeFolder, .resize(folderID, large: true))], "a folder has neither Edit nor Remove in the mode")
        XCTAssertNil(r.state.menu(at: CGPoint(x: 4, y: 4)), "the background's Edit is off in the mode")
    }

    func testBeforeTheModeAnAppIsNeverOfferedRemoveEvenWhenTheDoorWouldTakeIt() async throws {
        let r = rig(removable: ["a"])
        XCTAssertFalse(r.state.editing)
        XCTAssertFalse(try menu(r, "a").items.contains(.action(title: LpStr.removeAction, .askToRemove("a"))))
    }

    // MARK: - The category view

    private func categoryRig(count: Int) -> LiftRig {
        let r = LiftRig(self, apps: (0..<count).map { "m\($0)" })
        r.catalog.reading = CatalogReading(apps: (0..<count).map { CatalogApp(id: "m\($0)", name: "M\($0)", path: "/Applications/m\($0).app", category: music) }, complete: true)
        r.state.update(snapshot: r.engine.read(reason: .refresh))
        r.state.setView(.categories)
        return r
    }

    private func quadrant(_ r: LiftRig, _ q: Int) -> CGPoint {
        let g = r.state.geometry
        let block = g.frame(of: r.state.slots[0][0]).offsetBy(dx: 0, dy: g.gridTop)
        let f = LaunchpadCategoryMark.frame(ofQuadrant: q, size: g.largeMark, edge: g.largeEdge)
        return CGPoint(x: block.midX - g.largeMark / 2 + f.midX, y: block.minY + g.iconTop + f.midY)
    }

    func testABlocksLargeIconOffersItsAppsHideMoveAndFilesOnlyAndTheClusterAndChromeNothing() throws {
        let r = categoryRig(count: 6)
        XCTAssertTrue(r.state.categoriesShown, "the subject")
        guard case .folder(_, _, let apps, _) = r.state.pages[0][0] else { return XCTFail("the first tile is a block") }
        XCTAssertEqual(apps.count, 6)
        for q in 0..<3 {
            let m = try XCTUnwrap(r.state.menu(at: quadrant(r, q)), "quadrant \(q)")
            let id = apps[q].id
            XCTAssertEqual(m.items, [.action(title: LpStr.hide, .hide(id)), .submenu(title: LpStr.moveToCategory, try moveRows(m))] + files(id), "no Edit, no Remove, no resize")
            XCTAssertEqual(checked(try moveRows(m)), [.move(id, .category(.music))])
        }
        XCTAssertNil(r.state.menu(at: quadrant(r, 3)), "from five apps the fourth quarter is the cluster")
        let g = r.state.geometry
        let block = g.frame(of: r.state.slots[0][0]).offsetBy(dx: 0, dy: g.gridTop)
        XCTAssertNil(r.state.menu(at: CGPoint(x: block.midX, y: block.maxY - 2)), "the block's name is chrome")
        XCTAssertNil(r.state.menu(at: CGPoint(x: 4, y: 4)), "no Edit in the category view")
    }

    // MARK: - The background

    func testTheBackgroundOffersEditWhereTheModeCanBeginAndNowhereElse() async throws {
        let r = rig(removable: ["a"])
        let corner = CGPoint(x: 4, y: 4)
        XCTAssertEqual(r.state.menu(at: corner), LaunchpadMenu(items: [.action(title: HelmWord.edit, .beginEditing)]), "the subject")
        let empty = r.core(20)
        XCTAssertEqual(r.state.menu(at: empty)?.items, [.action(title: HelmWord.edit, .beginEditing)], "an empty cell is the background, as the scrim was")
        let field = CGPoint(x: r.g.size.width / 2, y: r.g.searchTop + LaunchpadMetrics.searchHeight / 2)
        XCTAssertNil(r.state.menu(at: field), "the search field keeps its own text menu")
        _ = r.state.menu(at: CGPoint(x: CGFloat.nan, y: 4))  // a point that is no place answers (the background, today) and does not trap

        r.state.search = "a"
        XCTAssertNil(r.state.menu(at: corner), "a search is typed")
        r.state.search = ""
        XCTAssertNotNil(r.state.menu(at: corner), "the control: cleared, it is back")

        r.state.open(folder: folderID)
        XCTAssertNotNil(r.state.openFolder, "the control: the card is open")
        XCTAssertNil(r.state.menu(at: corner), "a card is open")
        r.state.closeFolder()

        r.state.setShown(false)
        XCTAssertNil(r.state.menu(at: corner), "the window is not shown")
        r.state.setShown(true)

        r.state.setView(.categories)
        XCTAssertNil(r.state.menu(at: corner), "the category view has no mode")
        r.state.setView(.apps)

        r.state.beginEditing()
        await waitUntil("the answer") { r.state.removable == ["a"] }
        XCTAssertNil(r.state.menu(at: corner), "in the mode")
        r.state.onPreview = { _ in try? await Task.sleep(for: .seconds(30)); return nil }
        r.state.askToRemove("a")
        XCTAssertNotNil(r.state.removalAsk, "the control: a removal question is up")
        XCTAssertNil(r.state.menu(at: try centre(r, "a")), "no menu over a removal question")
        XCTAssertNil(r.state.menu(forTile: "a"))
        r.state.cancelRemoval()
        XCTAssertNotNil(r.state.menu(at: try centre(r, "a")), "the control: the question gone, the menu is back")
    }

    // MARK: - What a chosen row does

    func testPerformHidesShowsAndMovesAndDoesNotMoveToTheCategoryTheAppIsIn() {
        let r = rig()
        var hid: [String] = [], shown: [String] = [], moves: [String] = []
        r.state.onHide = { hid.append($0) }
        r.state.onUnhide = { shown.append($0) }
        r.state.onMove = { id, target in moves.append("\(id)>\(target.map { "\($0)" } ?? "own")") }
        r.state.perform(.hide("a"))
        r.state.perform(.show("b"))
        XCTAssertEqual(hid, ["a"])
        XCTAssertEqual(shown, ["b"])
        r.state.perform(.move("a", .others))
        XCTAssertEqual(moves, [], "Others is where a is: the checked row does nothing")
        r.state.perform(.move("a", .category(.music)))
        r.state.perform(.move("a", nil))
        XCTAssertEqual(moves.count, 2, "another category, and the undo, are moves")
        r.state.perform(.beginEditing)
        XCTAssertTrue(r.state.editing)
    }

    func testRevealAndCopyPathAskAgainAndDoNothingForAnAppThatIsNoLongerFiled() {
        let rig = HiddenRig(.immediate(.success))
        var revealed: [String] = [], copied: [String] = []
        rig.state.onRevealApp = { revealed.append($0) }
        rig.state.onCopyPath = { path, _ in copied.append(path) }
        rig.state.perform(.reveal("a"))
        rig.state.perform(.copyPath("a"))
        XCTAssertEqual(revealed, ["/Applications/a.app"], "the control: a visible app is revealed")
        XCTAssertEqual(copied, ["/Applications/a.app"])
        rig.state.perform(.reveal(HiddenRig.hidden))
        rig.state.perform(.copyPath(HiddenRig.hidden))
        rig.state.perform(.reveal("gone"))
        XCTAssertEqual(revealed, ["/Applications/a.app"], "a hidden app outside the unlocked card, and an app that is gone: nothing")
        XCTAssertEqual(copied, ["/Applications/a.app"])
    }

    // MARK: - As an NSMenu

    func testTheNSMenuKeepsCheckedEnabledAndSubmenuAndAChosenRowPerformsItsAction() throws {
        let r = rig(overrides: ["a": .category(.weather)])
        var performed: [LaunchpadMenuAction] = []
        let ns = LaunchpadNSMenu.make(try menu(r, "a")) { performed.append($0) }
        XCTAssertFalse(ns.autoenablesItems, "the description alone enables")
        XCTAssertGreaterThan(ns.items.count, 4, "the subject: the menu has rows")
        XCTAssertEqual(ns.items.map(\.title).prefix(2), [LpStr.hide, LpStr.moveToCategory])
        let move = try XCTUnwrap(ns.items.first { $0.title == LpStr.moveToCategory })
        let sub = try XCTUnwrap(move.submenu, "a submenu, not a row")
        XCTAssertFalse(sub.autoenablesItems)
        XCTAssertTrue(sub.items[0].isEnabled, "the undo of a moved app is enabled")
        XCTAssertTrue(sub.items[1].isSeparatorItem)
        let on = sub.items.filter { $0.state == .on }
        XCTAssertEqual(on.count, 1)
        XCTAssertEqual(on.first?.title, LaunchpadCategoryName.choices().first { $0.target == .category(.weather) }?.title)
        XCTAssertEqual(ns.items.filter(\.isSeparatorItem).count, 1)

        let unmoved = LaunchpadNSMenu.make(try menu(rig(), "a")) { _ in }
        XCTAssertFalse(try XCTUnwrap(unmoved.items.first { $0.submenu != nil }?.submenu).items[0].isEnabled, "nothing to undo")

        for (item, action) in [(ns.items[0], LaunchpadMenuAction.hide("a")), (sub.items[0], .move("a", nil)),
                               (try XCTUnwrap(sub.items.last), .move("a", .others))] {
            let choice = try XCTUnwrap(item.target as? NSObject)
            _ = choice.perform(item.action, with: item)
            XCTAssertEqual(performed.last, action, item.title)
        }
        XCTAssertEqual(performed.count, 3)
    }
}
