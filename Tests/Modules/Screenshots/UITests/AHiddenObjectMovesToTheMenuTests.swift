import AppKit
import Foundation
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A row object taken off the palette stands as the first item of the ⋯ menu, above the glyph tools, with its own check
/// mark, and choosing it there raises the same tool its key does.** The owner accepted it (section 8, V1): the hidden
/// object is reachable by the mouse and not only by the key. What is held: exactly the hidden objects are in the menu, in
/// the row's order, none of the visible ones; the check follows the tool in use, among hidden and visible alike and
/// never twice; the menu is made again from the model at every opening; the item sends `.tool(tool)` and shows the key
/// the tool has; and the whole path through the overlay ends in a layer of that tool.
///
/// The tool is asked of every object of `EditorPalette.rowTools`, hidden alone and with every other; no count is a number.
@MainActor
final class AHiddenObjectMovesToTheMenuTests: XCTestCase {

    private let rig = HiddenPaletteRig()

    override func tearDown() {
        rig.close()
        AppLanguage.override = nil
        super.tearDown()
    }

    private func model(tool: AnnotationTool? = nil, hiding items: Set<PaletteItem> = []) -> EditorBarModel {
        let model = EditorBarModel()
        model.show(tool: tool, style: AnnotationStyle(), canUndo: false, canRedo: false)
        model.hide(items)
        return model
    }

    private func titles(_ items: [EditorMenuItem]) -> [String] {
        items.map {
            switch $0 {
            case .tool(let title, _, _, _), .action(let title, _, _, _), .submenu(let title, _, _): title
            case .separator: "—"
            }
        }
    }

    /// Every item of the menu that is checked, nested ones included.
    private func checked(_ items: [EditorMenuItem]) -> [String] {
        items.flatMap { item -> [String] in
            switch item {
            case .tool(let title, _, let isOn, _): isOn ? [title] : []
            case .action(let title, _, _, let isOn): isOn ? [title] : []
            case .submenu(let title, let isOn, let children): (isOn ? [title] : []) + checked(children)
            case .separator: []
            }
        }
    }

    private func flat(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(flat) ?? []) } }

    /// The row objects that stand in the menu: `.tool` items sending a row tool's own action, or the eraser's or the ruler's.
    private func hiddenItems(_ items: [EditorMenuItem]) -> [(title: String, symbol: String, action: EditorAction, isOn: Bool)] {
        items.compactMap {
            guard case .tool(let title, let symbol, let isOn, let action) = $0 else { return nil }
            switch action {
            case .tool(let tool): return EditorPalette.rowTools.contains(tool) ? (title, symbol, action, isOn) : nil
            case .erase, .toggleRuler: return (title, symbol, action, isOn)
            default: return nil
            }
        }
    }

    // MARK: - What stands in the menu

    func testTheMenuIsTheSameAsBeforeWhileNothingIsHidden() {
        AppLanguage.override = .en
        let none = EditorMenu.items(for: model())
        XCTAssertTrue(hiddenItems(none).isEmpty, "an item stands for an object nobody took off: \(titles(none))")
        XCTAssertEqual(titles(none).first, ScStr.tool(.arrow), "Arrow is the first item with nothing hidden")
    }

    func testEachHiddenObjectIsTheFirstItemAboveTheGlyphTools() throws {
        AppLanguage.override = .en
        let rowTools = EditorPalette.rowTools
        XCTAssertFalse(rowTools.isEmpty, "the subject: the row has objects")
        for tool in rowTools {
            let item = try XCTUnwrap(EditorPalette.item(of: tool))
            let items = EditorMenu.items(for: model(hiding: [item]))
            XCTAssertEqual(titles(items).first, ScStr.tool(tool), "\(tool): not the first item of ⋯: \(titles(items))")
            XCTAssertEqual(items.first, .tool(title: ScStr.tool(tool), symbol: EditorPalette.menuSymbol(ofRowTool: tool), isOn: false, action: .tool(tool)), "\(tool)")
            XCTAssertEqual(hiddenItems(items).map(\.title), [ScStr.tool(tool)], "\(tool): other row objects stand in the menu with it")
            let arrow = try XCTUnwrap(titles(items).firstIndex(of: ScStr.tool(.arrow)), "Arrow left the menu")
            XCTAssertEqual(arrow, 1, "\(tool): the glyph tools do not follow the hidden object at once")
            // The rest of the menu is as it was with nothing hidden.
            XCTAssertEqual(Array(items.dropFirst()), EditorMenu.items(for: model()), "\(tool): the menu changed beyond the one item")
        }
    }

    func testEveryHiddenObjectStandsInTheRowsOrderAndNoVisibleOneDoes() throws {
        AppLanguage.override = .en
        let rowTools = EditorPalette.rowTools
        var hidden: Set<PaletteItem> = []
        for (index, tool) in rowTools.enumerated() {
            hidden.insert(try XCTUnwrap(EditorPalette.item(of: tool)))
            let items = EditorMenu.items(for: model(hiding: hidden))
            XCTAssertEqual(hiddenItems(items).map(\.title), rowTools.prefix(index + 1).map(ScStr.tool),
                           "\(index + 1) hidden: the menu does not hold them in the row's order")
            XCTAssertEqual(titles(items).prefix(index + 1).map { $0 }, rowTools.prefix(index + 1).map(ScStr.tool))
            XCTAssertEqual(titles(items)[index + 1], ScStr.tool(.arrow), "the glyph tools start after the hidden ones")
        }
        // A visible object never stands in the menu: hide all but one, in turn.
        for kept in rowTools {
            let others = Set(rowTools.filter { $0 != kept }.compactMap(EditorPalette.item(of:)))
            let items = EditorMenu.items(for: model(hiding: others))
            XCTAssertFalse(hiddenItems(items).map(\.title).contains(ScStr.tool(kept)), "\(kept) is on the row and in the menu")
            XCTAssertEqual(hiddenItems(items).count, rowTools.count - 1)
        }
    }

    /// The menu's items for hidden objects are asked from the model's own `isOnRow`, one answer for the row and the menu.
    func testTheMenuAndTheRowAnswerOneQuestion() throws {
        AppLanguage.override = .en
        for item in Set(HiddenPaletteRig.rowItems) {
            for hide in [true, false] {
                let m = model(hiding: hide ? [item] : [])
                let inMenu = Set(hiddenItems(EditorMenu.items(for: m)).map(\.title))
                let expected = Set(EditorPalette.rowKinds.filter { !m.isOnRow($0) }.map(EditorPalette.name(of:)))
                XCTAssertEqual(inMenu, expected, "\(item) hidden=\(hide): the menu and the row disagree")
                XCTAssertEqual(expected.isEmpty, !hide)
            }
        }
    }

    /// The eraser and the ruler are no `AnnotationTool`, yet each can be taken off the row: it stands in the menu sending its
    /// own action, checked while it is on, and a hidden eraser that is raised is ⋯'s badge. (The ruler raised changes no badge.)
    func testAHiddenEraserAndRulerStandInTheMenuWithTheirOwnActions() {
        AppLanguage.override = .en
        let cases: [(PaletteItem, EditorAction, String)] = [(.eraser, .erase, ScStr.eraser), (.ruler, .toggleRuler, ScStr.ruler)]
        for (item, action, name) in cases {
            let off = model(hiding: [item])
            XCTAssertEqual(hiddenItems(EditorMenu.items(for: off)).map(\.title), [name], "\(item) hidden")
            XCTAssertEqual(hiddenItems(EditorMenu.items(for: off)).map(\.action), [action], "\(item) sends another action")
            XCTAssertFalse(checked(EditorMenu.items(for: off)).contains(name), "\(item) is checked while it is not on")
            let on = EditorBarModel()
            on.show(tool: nil, erasing: item == .eraser, ruler: item == .ruler, style: AnnotationStyle(), canUndo: false, canRedo: false)
            on.hide([item])
            XCTAssertTrue(checked(EditorMenu.items(for: on)).contains(name), "\(item) is on and hidden, and not checked in the menu")
        }
        let erasing = EditorBarModel()
        erasing.show(tool: nil, erasing: true, style: AnnotationStyle(), canUndo: false, canRedo: false)
        XCTAssertNil(EditorPalette.moreBadge(for: erasing), "the eraser is on the row and raised: ⋯ shows nothing")
        erasing.hide([.eraser])
        XCTAssertEqual(EditorPalette.moreBadge(for: erasing), "eraser", "the eraser is hidden and raised: ⋯ shows its symbol")
        XCTAssertEqual(EditorPalette.moreValue(for: erasing), ScStr.eraser)
    }

    // MARK: - The check mark

    /// One check among everything, on the tool in use, wherever that tool stands — hidden object or glyph tool.
    func testTheCheckIsOnTheToolInUseAndOnNoOtherItem() throws {
        AppLanguage.override = .en
        let everyHidden = Set(PaletteItem.allCases)
        let choices: [AnnotationTool?] = [nil] + AnnotationTool.allCases.map { Optional($0) }
        for hidden in [Set<PaletteItem>(), everyHidden] {
            for tool in choices {
                let items = EditorMenu.items(for: model(tool: tool, hiding: hidden))
                let on = checked(items)
                let context = "tool \(String(describing: tool)), hidden \(hidden.count)"
                let onTheRow = tool.map { EditorPalette.rowTools.contains($0) } ?? false
                if onTheRow, let tool, !hidden.isEmpty {
                    XCTAssertEqual(on, [ScStr.tool(tool)], "\(context): the hidden object in use is not the one checked item")
                } else if onTheRow {
                    XCTAssertEqual(on, [], "\(context): a row object that is on the row is checked in the menu")
                }
                XCTAssertLessThanOrEqual(on.count, 2, "\(context): more than the tool and its Shapes parent are checked: \(on)")
                XCTAssertEqual(Set(on).count, on.count, "\(context): an item is checked twice")
            }
        }
    }

    // MARK: - The NSMenu

    private func openedMenu(_ model: EditorBarModel) -> NSMenu {
        let menu = EditorMenu.make(for: model)
        menu.delegate?.menuNeedsUpdate?(menu)
        return menu
    }

    /// The menu is made again from the model at every opening: a pick between two openings is in the second.
    func testTheMenuReadsTheModelAgainAtEveryOpening() throws {
        AppLanguage.override = .en
        let tool = try XCTUnwrap(EditorPalette.rowTools.first)
        let item = try XCTUnwrap(EditorPalette.item(of: tool))
        let m = model()
        let menu = EditorMenu.make(for: m)
        menu.delegate?.menuNeedsUpdate?(menu)
        XCTAssertFalse(menu.items.map(\.title).contains(ScStr.tool(tool)), "the subject: not hidden yet")
        m.hide([item])
        menu.delegate?.menuNeedsUpdate?(menu)
        XCTAssertEqual(menu.items.first?.title, ScStr.tool(tool), "the second opening did not take the hidden object")
        m.show(tool: tool, style: AnnotationStyle(), canUndo: false, canRedo: false)
        menu.delegate?.menuNeedsUpdate?(menu)
        XCTAssertEqual(menu.items.first?.state, .on, "the check did not follow the tool in use")
        m.hide([])
        menu.delegate?.menuNeedsUpdate?(menu)
        XCTAssertFalse(menu.items.map(\.title).contains(ScStr.tool(tool)), "the object came back to the row and stays in the menu")
    }

    /// The item sends what the key sends, and says the key beside its name.
    func testTheItemSendsTheKeysActionAndShowsTheKey() throws {
        AppLanguage.override = .en
        for tool in EditorPalette.rowTools {
            let item = try XCTUnwrap(EditorPalette.item(of: tool))
            let m = model(hiding: [item])
            var sent: [EditorAction] = []
            m.perform = { sent.append($0) }
            let menu = openedMenu(m)
            let entry = try XCTUnwrap(menu.items.first, "\(tool)")
            XCTAssertEqual(entry.title, ScStr.tool(tool))
            XCTAssertTrue(entry.isEnabled, "\(tool): the item is disabled")
            // The spotlight has no key: its item shows none and is the only way to it from the menu.
            let key = EditorKeys.toolKeys.first { $0.tool == tool }
            XCTAssertEqual(entry.keyEquivalent, key?.letter.lowercased() ?? "", "\(tool): the key is not shown beside the name")
            XCTAssertEqual(entry.keyEquivalentModifierMask, [], "\(tool): the key is shown with a modifier")
            menu.performActionForItem(at: 0)
            if let key {
                XCTAssertEqual(sent, [EditorKeys.action(keyCode: UInt16(key.code), flags: [])].compactMap { $0 },
                               "\(tool): the item sent another action than its key")
            }
            XCTAssertEqual(sent, [.tool(tool)])
        }
    }

    /// Choosing the chosen one again sends what choosing it sent: the editor puts a tool down by choosing it twice.
    func testChoosingTheCheckedHiddenObjectAgainSendsTheSameAction() throws {
        let tool = try XCTUnwrap(EditorPalette.rowTools.first)
        let m = model(tool: tool, hiding: [try XCTUnwrap(EditorPalette.item(of: tool))])
        var sent: [EditorAction] = []
        m.perform = { sent.append($0) }
        let menu = openedMenu(m)
        XCTAssertEqual(menu.items.first?.state, .on, "the subject: checked")
        menu.performActionForItem(at: 0)
        XCTAssertEqual(sent, [.tool(tool)])
    }

    /// Every language: a name for the item, not a key that fell through, and not one another item has.
    func testTheItemIsNamedInEveryLanguageAndTwoItemsNeverShareAName() throws {
        AppLanguage.each { language in
            let m = model(hiding: Set(PaletteItem.allCases))
            let names = EditorMenu.items(for: m).prefix(EditorPalette.rowTools.count).map { titles([$0])[0] }
            XCTAssertEqual(names.count, EditorPalette.rowTools.count, "\(language)")
            for name in names { XCTAssertFalse(name.trimmingCharacters(in: .whitespaces).isEmpty, "\(language): an item has no name") }
            let all = titles(EditorMenu.items(for: m)).filter { $0 != "—" }
            XCTAssertEqual(Set(all).count, all.count, "\(language): two items of ⋯ share a name: \(all)")
        }
    }

    // MARK: - Through the overlay

    /// The path a hand takes: hide, release an area, open ⋯, choose the object, draw, Done — a layer of that tool; then the
    /// key of the same tool puts it down.
    func testChoosingAHiddenObjectFromTheMenuRaisesItAndTheKeyThenPutsItDown() throws {
        for tool in EditorPalette.rowTools {
            let item = try XCTUnwrap(EditorPalette.item(of: tool))
            try rig.build(store: HiddenPaletteRig.store(hiding: [item]))
            let palette = try XCTUnwrap(rig.overlay?.palette)
            let menu = openedMenu(palette)
            XCTAssertEqual(menu.items.first?.title, ScStr.tool(tool), "the subject: \(tool) is in the menu")
            menu.performActionForItem(at: 0)
            XCTAssertEqual(palette.tool, tool, "\(tool): choosing it in ⋯ did not raise it")
            XCTAssertEqual(openedMenu(palette).items.first?.state, .on, "\(tool): the menu does not check it after the choice")
            rig.stroke()
            XCTAssertEqual(try rig.drawnTools(), [tool], "\(tool): the menu's tool drew another")
        }
        let tool = try XCTUnwrap(EditorPalette.rowTools.first)
        try rig.build(store: HiddenPaletteRig.store(hiding: [try XCTUnwrap(EditorPalette.item(of: tool))]))
        let palette = try XCTUnwrap(rig.overlay?.palette)
        openedMenu(palette).performActionForItem(at: 0)
        XCTAssertEqual(palette.tool, tool)
        let key = try XCTUnwrap(EditorKeys.toolKeys.first { $0.tool == tool }).code
        rig.overlay?.keyDown(rig.key(key))
        XCTAssertNil(palette.tool, "the key after the menu's choice did not put the tool down")
    }

    /// The menu is gone from under a closed overlay: an item chosen after the close finds no editor (the existing rule holds for
    /// the new items too).
    func testAnItemChosenAfterTheOverlayClosedDoesNothing() throws {
        let tool = try XCTUnwrap(EditorPalette.rowTools.first)
        try rig.build(store: HiddenPaletteRig.store(hiding: [try XCTUnwrap(EditorPalette.item(of: tool))]))
        let palette = try XCTUnwrap(rig.overlay?.palette)
        let menu = openedMenu(palette)
        rig.overlay?.close()
        let before = palette.tool
        menu.performActionForItem(at: 0)
        XCTAssertEqual(palette.tool, before, "a closed overlay's menu still raised a tool")
        XCTAssertTrue(rig.results.isEmpty)
    }
}
