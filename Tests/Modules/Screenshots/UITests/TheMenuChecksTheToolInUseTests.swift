import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The ⋯ menu checks the tool that is in use, and is made again from what the palette shows every time it opens.**
///
/// The menu is `EditorMenu.swift`: `EditorMenu.items(for:pinOffered:)` is pure (the model in, the values out;
/// `pinOffered` is passed so that the item's presence can be asked at `true` too, where the switch is a constant), and
/// `EditorMenu.make(for:)` is the `NSMenu`, whose delegate fills it from `items` in `menuNeedsUpdate`, so every opening
/// reads the model again.
///
/// Order, this stage: Arrow, Shapes ▸ (Rectangle, Oval, Line, separator, Filled), Select, separator, Save, and
/// Pin only while offered. Exactly one tool item is on: the chosen menu tool; while a row object (the pencil, the
/// highlighter) is chosen none is. The tool is asked of every case of `AnnotationTool` and of none, so a tool added
/// later has to be in the answer.
@MainActor
final class TheMenuChecksTheToolInUseTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    private func model(tool: AnnotationTool?, filled: Bool = false) -> EditorBarModel {
        let model = EditorBarModel()
        model.show(tool: tool, style: AnnotationStyle(filled: filled), canUndo: false, canRedo: false)
        return model
    }

    private static let shapeTools: [AnnotationTool] = [.rectangle, .ellipse, .line]
    /// Every case, and none (Select).
    private static let everyChoice: [AnnotationTool?] = [nil] + AnnotationTool.allCases.map { Optional($0) }

    /// The menu's shape without its state: what is there, in which order.
    private func outline(_ items: [EditorMenuItem]) -> [String] {
        items.map {
            switch $0 {
            case .tool(let title, _, _, _): "tool:\(title)"
            case .submenu(let title, _, let children): "submenu:\(title)[\(outline(children).joined(separator: ","))]"
            case .separator: "separator"
            case .action(let title, _, _, _): "action:\(title)"
            }
        }
    }

    /// Every `.tool` item, wherever it is.
    private func tools(_ items: [EditorMenuItem]) -> [(title: String, symbol: String, isOn: Bool, action: EditorAction)] {
        items.flatMap { item -> [(title: String, symbol: String, isOn: Bool, action: EditorAction)] in
            switch item {
            case .tool(let title, let symbol, let isOn, let action): [(title, symbol, isOn, action)]
            case .submenu(_, _, let children): tools(children)
            default: []
            }
        }
    }

    private func expectedOutline(pinOffered: Bool) -> [String] {
        ["tool:\(ScStr.tool(.arrow))",
         "submenu:\(ScStr.shapes)[tool:\(ScStr.tool(.rectangle)),tool:\(ScStr.tool(.ellipse)),tool:\(ScStr.tool(.line)),separator,action:\(ScStr.fill)]",
         "tool:\(ScStr.select)", "separator", "action:\(ScStr.save)"] + (pinOffered ? ["action:\(ScStr.pin)"] : [])
    }

    func testTheOrderOfTheItemsAndTheSeparatorsIsTheListOfThisStage() {
        AppLanguage.override = .en
        for pinOffered in [false, true] {
            for tool in Self.everyChoice {
                let items = EditorMenu.items(for: model(tool: tool), pinOffered: pinOffered)
                XCTAssertEqual(outline(items), expectedOutline(pinOffered: pinOffered), "tool \(String(describing: tool)), pin offered \(pinOffered)")
            }
        }
    }

    func testExactlyTheChosenToolIsOnAndNoOtherThing() throws {
        AppLanguage.override = .en
        for tool in Self.everyChoice {
            let items = EditorMenu.items(for: model(tool: tool))
            let on = tools(items).filter(\.isOn)
            let context = "tool \(String(describing: tool))"
            switch tool {
            case nil: XCTAssertEqual(on.map(\.title), [ScStr.select], "\(context): Select is on when nothing is chosen")
            case .arrow?: XCTAssertEqual(on.map(\.title), [ScStr.tool(.arrow)], context)
            case .rectangle?, .ellipse?, .line?:
                XCTAssertEqual(on.map(\.title), [ScStr.tool(try XCTUnwrap(tool))], context)
            case .pen?, .pencil?, .highlighter?:
                XCTAssertTrue(on.isEmpty, "\(context): a row object is raised and the menu checks \(on.map(\.title))")
            }
            // The parent of the shapes is on exactly while a shape is the tool.
            guard case .submenu(_, let parentOn, _)? = items.first(where: { if case .submenu = $0 { true } else { false } }) else {
                return XCTFail("\(context): no submenu among \(outline(items))")
            }
            XCTAssertEqual(parentOn, tool.map(Self.shapeTools.contains) ?? false, "\(context): Shapes' check")
            // Filled is checked by the fill setting, whatever the tool.
            for filled in [false, true] {
                let again = EditorMenu.items(for: model(tool: tool, filled: filled))
                guard case .submenu(_, _, let kids)? = again.first(where: { if case .submenu = $0 { true } else { false } }),
                      case .action(let title, let action, _, let isOn)? = kids.last else { return XCTFail("\(context): Filled is not last in Shapes") }
                XCTAssertEqual(title, ScStr.fill)
                XCTAssertEqual(action, .toggleFill)
                XCTAssertEqual(isOn, filled, "\(context): Filled's check is not the fill setting (\(filled))")
            }
        }
    }

    /// Each item says the same thing the key and the palette say: the action it sends, and a symbol it draws.
    func testEachItemSendsTheActionItNamesAndTheChosenOneStillSendsIt() {
        AppLanguage.override = .en
        let items = EditorMenu.items(for: model(tool: .arrow))
        let sent = tools(items).map { [$0.title: $0.action] }
        XCTAssertEqual(sent, [[ScStr.tool(.arrow): .tool(.arrow)], [ScStr.tool(.rectangle): .tool(.rectangle)],
                              [ScStr.tool(.ellipse): .tool(.ellipse)], [ScStr.tool(.line): .tool(.line)], [ScStr.select: .select]],
                       "re-choosing the chosen tool sends what choosing it sent (Q3)")
        XCTAssertEqual(tools(items).map(\.symbol), ["arrow.up.right", "rectangle", "circle", "line.diagonal", "cursorarrow"])
        guard case .action(_, let save, let enabled, let saveOn)? = items.last else { return XCTFail("the last item is not Save: \(outline(items))") }
        XCTAssertEqual(save, .exit(.save))
        XCTAssertTrue(enabled)
        XCTAssertFalse(saveOn)
    }

    func testThePinIsInTheMenuOnlyWhileOfferedAndAfterSave() {
        AppLanguage.override = .en
        XCTAssertFalse(PinEntry.isOffered, "the control: this task is written for v1, where the pin is hidden")
        let hidden = EditorMenu.items(for: model(tool: nil))
        XCTAssertFalse(outline(hidden).contains("action:\(ScStr.pin)"), "the menu offers «\(ScStr.pin)» in v1: \(outline(hidden))")
        let shown = EditorMenu.items(for: model(tool: nil), pinOffered: true)
        XCTAssertEqual(outline(shown).suffix(2), ["action:\(ScStr.save)", "action:\(ScStr.pin)"], "the item replaces the palette's cell, right after Save")
        guard case .action(_, let action, true, false)? = shown.last else { return XCTFail("Pin is not a plain enabled item") }
        XCTAssertEqual(action, .exit(.pin))
    }

    /// The titles are the strings of the person's language, in each of the eight.
    func testTheTitlesAreInEveryLanguage() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let items = EditorMenu.items(for: model(tool: nil))
            XCTAssertEqual(outline(items), expectedOutline(pinOffered: false), "\(language)")
            XCTAssertFalse(outline(items).contains { $0.hasSuffix(":") || $0.contains("[]") }, "\(language): an empty title")
        }
    }

    // MARK: - The NSMenu

    private func flat(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(flat) ?? []) }
    }

    /// **No item carries a key equivalent, ⌘S included**: the label is the owner's open question and a later
    /// one-place change; today the menu says no key at all.
    func testNoItemCarriesAKeyEquivalent() throws {
        AppLanguage.override = .en
        for tool in Self.everyChoice {
            let m = model(tool: tool)
            let menu = EditorMenu.make(for: m)
            menu.delegate?.menuNeedsUpdate?(menu)
            let all = flat(menu)
            XCTAssertGreaterThanOrEqual(all.filter { !$0.isSeparatorItem }.count, 8, "the menu is empty, so «no key» means nothing")
            XCTAssertEqual(all.filter { !$0.keyEquivalent.isEmpty }.map(\.title), [], "tool \(String(describing: tool))")
            XCTAssertEqual(all.filter { !$0.keyEquivalentModifierMask.isEmpty && !$0.isSeparatorItem }.count, 0, "a modifier is left on an item")
        }
    }

    /// **Made again at every opening.** The same NSMenu is opened twice with the model changed between: the
    /// second opening shows the second state. A menu built once from a copy taken at first open fails here.
    func testTheMenuIsMadeAgainFromTheModelAtEveryOpening() throws {
        AppLanguage.override = .en
        let m = model(tool: .arrow)
        let menu = EditorMenu.make(for: m)
        let delegate = try XCTUnwrap(menu.delegate, "the menu has no delegate to fill it at an opening")
        func checked() -> [String] { flat(menu).filter { $0.state == .on }.map(\.title) }
        delegate.menuNeedsUpdate?(menu)
        XCTAssertEqual(checked(), [ScStr.tool(.arrow)], "first opening")
        m.show(tool: .ellipse, style: AnnotationStyle(filled: true), canUndo: false, canRedo: false)
        delegate.menuNeedsUpdate?(menu)
        XCTAssertEqual(Set(checked()), [ScStr.shapes, ScStr.tool(.ellipse), ScStr.fill], "second opening, after the tool and the fill moved")
        m.show(tool: nil, style: AnnotationStyle(filled: false), canUndo: false, canRedo: false)
        delegate.menuNeedsUpdate?(menu)
        XCTAssertEqual(checked(), [ScStr.select], "third opening, nothing chosen")
        // And the titles after rebuilding are still the whole list, not a growing one.
        XCTAssertEqual(menu.items.count, 5)
    }

    /// A click on an item is the action the builder names, through the model's one door.
    func testAClickOnAnItemSendsItsAction() throws {
        AppLanguage.override = .en
        // A shape is chosen: Filled is enabled by today's rule (`fillApplies`), and a disabled item sends nothing.
        let m = model(tool: .rectangle)
        var sent: [EditorAction] = []
        m.perform = { sent.append($0) }
        let menu = EditorMenu.make(for: m)
        menu.delegate?.menuNeedsUpdate?(menu)
        func click(_ title: String) throws {
            let item = try XCTUnwrap(flat(menu).first { $0.title == title }, "no item «\(title)»")
            let parent = try XCTUnwrap(item.menu)
            parent.performActionForItem(at: parent.index(of: item))
        }
        for title in [ScStr.tool(.arrow), ScStr.tool(.rectangle), ScStr.tool(.line), ScStr.fill, ScStr.select, ScStr.save] { try click(title) }
        XCTAssertEqual(sent, [.tool(.arrow), .tool(.rectangle), .tool(.line), .toggleFill, .select, .exit(.save)])
    }

    /// **Filled is enabled exactly where the fill changes something** (`EditorBarModel.fillApplies`: a box is the
    /// subject, the selected object's tool first, else the picked one), asked of every tool and of every selected
    /// object's tool, both in the values and in the `NSMenu`'s item. The rule is read from the model, not copied here,
    /// and a control keeps the check honest: the answer comes out true and false in the sweep, so neither
    /// "always on" nor "always off" passes. Every other item stays enabled.
    func testFilledIsEnabledExactlyWhereTheFillApplies() throws {
        AppLanguage.override = .en
        var seen: Set<Bool> = []
        for tool in Self.everyChoice {
            for selected in Self.everyChoice {
                let m = EditorBarModel()
                m.show(tool: tool, style: AnnotationStyle(filled: false), selectedTool: selected, canUndo: false, canRedo: false)
                let context = "tool \(String(describing: tool)), selected \(String(describing: selected))"
                guard case .submenu(_, _, let kids)? = EditorMenu.items(for: m).first(where: { if case .submenu = $0 { true } else { false } }),
                      case .action(_, .toggleFill, let enabled, _)? = kids.last else { return XCTFail("\(context): Filled is not last in Shapes") }
                XCTAssertEqual(enabled, m.fillApplies, "\(context): Filled's isEnabled is not fillApplies")
                seen.insert(enabled)
                let menu = EditorMenu.make(for: m)
                menu.delegate?.menuNeedsUpdate?(menu)
                let item = try XCTUnwrap(flat(menu).first { $0.title == ScStr.fill }, context)
                XCTAssertEqual(item.isEnabled, m.fillApplies, "\(context): the NSMenuItem's isEnabled is not fillApplies")
                XCTAssertTrue(flat(menu).filter { $0.title != ScStr.fill && !$0.isSeparatorItem && $0.action != nil }.allSatisfy(\.isEnabled),
                              "\(context): another item is disabled")
            }
        }
        XCTAssertEqual(seen, [true, false], "the control: the rule must come out both ways in this sweep")
    }

    // MARK: - The badge on ⋯

    func testTheBadgeIsTheSymbolOfTheChosenMenuToolAndNothingForARowObject() {
        let expected: [(AnnotationTool?, String?)] = [
            (.arrow, "arrow.up.right"), (.rectangle, "rectangle"), (.ellipse, "circle"), (.line, "line.diagonal"),
            (nil, "cursorarrow"), (.pen, nil), (.pencil, nil), (.highlighter, nil),
        ]
        XCTAssertEqual(expected.count, Self.everyChoice.count, "a tool was added: say what its badge is")
        for (tool, symbol) in expected {
            XCTAssertEqual(EditorPalette.moreBadge(for: model(tool: tool)), symbol, "tool \(String(describing: tool))")
        }
    }

    /// VoiceOver: the name is «More actions», the value the chosen tool's name (none for a row object).
    func testTheValueIsTheNameOfTheChosenTool() {
        AppLanguage.override = .en
        XCTAssertEqual(EditorPalette.moreValue(for: model(tool: .ellipse)), ScStr.tool(.ellipse))
        XCTAssertEqual(EditorPalette.moreValue(for: model(tool: .arrow)), ScStr.tool(.arrow))
        XCTAssertEqual(EditorPalette.moreValue(for: model(tool: nil)), ScStr.select)
        XCTAssertNil(EditorPalette.moreValue(for: model(tool: .pen)))
        XCTAssertNil(EditorPalette.moreValue(for: model(tool: .pencil)))
        XCTAssertNil(EditorPalette.moreValue(for: model(tool: .highlighter)))
    }

    // MARK: - The palette has no Pin cell any more

    /// The cell is gone from the palette's code, not only hidden by the switch: its text names neither the
    /// switch nor the pin exit nor the pin's name. (`isOffered` is a constant, so no sweep can tell a cell
    /// built under it from one that is not.)
    func testThePaletteViewHasNoPinCell() throws {
        let source = SwiftSource.code(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorPalette.swift"))
        let start = try XCTUnwrap(source.range(of: "struct EditorPalette"), "the palette's struct moved")
        let rest = source[start.lowerBound...]
        // The struct ends at the next declaration at the margin.
        let end = rest.dropFirst().range(of: "\n}")?.upperBound ?? rest.endIndex
        let body = String(rest[..<end])
        XCTAssertGreaterThan(body.count, 2000, "the cut of the palette's body is too short to mean anything")
        for token in ["ScStr.pin", ".pin)", "isOffered", "PinEntry"] {
            XCTAssertFalse(body.contains(token), "the palette's view still names «\(token)»")
        }
    }
}
