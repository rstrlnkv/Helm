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
/// Order, this stage: Arrow, Shapes ▸ (Rectangle, Oval, Line, separator, Filled), Text, Steps, Blur, Crop, Select, Magnifier, Emoji, Thickness and Opacity…
/// (always there, right after the tools), separator, Save, Pin only while offered, and Share… last. Exactly one tool item is on: the chosen menu tool; while a row object (the pencil, the
/// highlighter, the spotlight) is chosen none is. The tool is asked of every case of `AnnotationTool` and of none, so a tool added
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
            case .reading(let title, _, _, _, _): "reading:\(title)"
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
         "tool:\(ScStr.tool(.text))", "tool:\(ScStr.tool(.step))", "tool:\(ScStr.tool(.blur))", "tool:\(ScStr.crop)", "tool:\(ScStr.select)", "tool:\(ScStr.tool(.magnifier))", "tool:\(ScStr.tool(.emoji))", "action:\(ScStr.thicknessAndOpacity)", "separator", "action:\(ScStr.save)"] + (pinOffered ? ["action:\(ScStr.pin)"] : []) + ["action:\(ScStr.share)"]
            + ["separator", "reading:\(ScStr.copyText)", "reading:\(ScStr.blurPersonalText)"]
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
            case .arrow?, .text?, .step?, .blur?, .magnifier?, .emoji?: XCTAssertEqual(on.map(\.title), [ScStr.tool(try XCTUnwrap(tool))], context)
            case .rectangle?, .ellipse?, .line?:
                XCTAssertEqual(on.map(\.title), [ScStr.tool(try XCTUnwrap(tool))], context)
            case .pen?, .pencil?, .highlighter?, .spotlight?:
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
                              [ScStr.tool(.ellipse): .tool(.ellipse)], [ScStr.tool(.line): .tool(.line)], [ScStr.tool(.text): .tool(.text)],
                              [ScStr.tool(.step): .tool(.step)], [ScStr.tool(.blur): .tool(.blur)],
                              [ScStr.crop: .crop], [ScStr.select: .select],
                              [ScStr.tool(.magnifier): .tool(.magnifier)], [ScStr.tool(.emoji): .tool(.emoji)]],
                       "re-choosing the chosen tool sends what choosing it sent (Q3)")
        XCTAssertEqual(tools(items).map(\.symbol), ["arrow.up.right", "rectangle", "circle", "line.diagonal", "textformat", "1.circle", "square.grid.3x3", "crop", "cursorarrow", "plus.magnifyingglass", "face.smiling"])
        guard case .action(_, let save, let enabled, let saveOn)? = items.first(where: { if case .action(let title, _, _, _) = $0 { title == ScStr.save } else { false } }) else {
            return XCTFail("no Save: \(outline(items))")
        }
        XCTAssertEqual(save, .exit(.save))
        XCTAssertTrue(enabled)
        XCTAssertFalse(saveOn)
    }

    // MARK: - Copy Text and Blur Emails and Phone Numbers

    /// Both stand behind a separator after Save (and Pin), in that order, whatever tool is chosen; they send their own actions, which have no key;
    /// they are on while no reading runs and both off while one does; and the second carries the hint, the first none. Asked of the
    /// NSMenu as well: its items are disabled and have the same tool tips.
    func testTheTwoReadingItemsStandAfterASeparatorAndAreOffWhileAReadingRuns() throws {
        AppLanguage.override = .en
        for tool in Self.everyChoice {
            let idle = model(tool: tool)
            let items = EditorMenu.items(for: idle, pinOffered: true)
            let last = Array(items.suffix(3))
            XCTAssertEqual(last.first, .separator, "tool \(String(describing: tool))")
            XCTAssertEqual(last.dropFirst().map { if case .reading(let title, _, _, _, _) = $0 { title } else { "?" } },
                           ["Copy Text", "Blur Emails and Phone Numbers"], "tool \(String(describing: tool))")
            guard case .reading(_, _, .copyText, true, nil) = last[1], case .reading(_, _, .blurPersonalText, true, let hint?) = last[2] else {
                return XCTFail("tool \(String(describing: tool)): the items are not what they should be: \(last)")
            }
            XCTAssertEqual(hint, ScStr.blurPersonalTextHint)
            XCTAssertEqual(EditorMenu.keyEquivalent(of: .copyText) + EditorMenu.keyEquivalent(of: .blurPersonalText), "", "no key")
        }
        let busy = EditorBarModel()
        busy.show(tool: nil, style: .standard, canUndo: false, canRedo: false, reading: true)
        var sent: [EditorAction] = []
        busy.perform = { sent.append($0) }
        let menu = EditorMenu.make(for: busy)
        menu.delegate?.menuNeedsUpdate?(menu)
        let reading = flat(menu).filter { [ScStr.copyText, ScStr.blurPersonalText].contains($0.title) }
        XCTAssertEqual(reading.count, 2, "the control: both items are in the menu")
        XCTAssertEqual(reading.map(\.isEnabled), [false, false], "a reading runs and the items are on")
        XCTAssertEqual(reading.map(\.toolTip), [nil, ScStr.blurPersonalTextHint])
        for item in reading { item.menu?.performActionForItem(at: item.menu?.index(of: item) ?? 0) }
        XCTAssertEqual(sent, [], "a disabled item sent its action")
        let idle = EditorMenu.make(for: model(tool: nil))
        idle.delegate?.menuNeedsUpdate?(idle)
        for item in flat(idle) where [ScStr.copyText, ScStr.blurPersonalText].contains(item.title) {
            XCTAssertTrue(item.isEnabled, item.title)
            XCTAssertNotNil(item.image, "\(item.title) has no symbol")
        }
    }

    // MARK: - Thickness and Opacity…

    private func popoverItem(_ items: [EditorMenuItem]) -> (index: Int, action: EditorAction, isEnabled: Bool, isOn: Bool)? {
        for (index, item) in items.enumerated() {
            if case .action(let title, let action, let isEnabled, let isOn) = item, title == ScStr.thicknessAndOpacity {
                return (index, action, isEnabled, isOn)
            }
        }
        return nil
    }

    /// Always present and always in the same place: right after Select and the lens and the emoji that follow it, before the separator and Save; the menu does
    /// not change shape with the choice. Enabled for every tool that has thickness steps (all of `AnnotationTool` but the
    /// spotlight), disabled for the spotlight and for Select, which have none.
    func testTheItemIsAlwaysRightAfterSelectAndEnabledExactlyWhereThereAreSteps() throws {
        AppLanguage.override = .en
        var seen: Set<Bool> = []
        for tool in Self.everyChoice {
            let items = EditorMenu.items(for: model(tool: tool))
            let found = try XCTUnwrap(popoverItem(items), "tool \(String(describing: tool)): no «\(ScStr.thicknessAndOpacity)» in \(outline(items))")
            let selectAt = try XCTUnwrap(items.firstIndex { if case .tool(let t, _, _, _) = $0 { t == ScStr.select } else { false } })
            XCTAssertEqual(found.index, selectAt + 1 + EditorPalette.afterSelect.count, "tool \(String(describing: tool)): not right after Select and the two tools that follow it")
            XCTAssertEqual(items[found.index + 1], .separator, "tool \(String(describing: tool)): the separator comes after it")
            XCTAssertEqual(found.isEnabled, tool != nil && tool != .spotlight, "tool \(String(describing: tool)): enabled where there are steps and only there")
            XCTAssertFalse(found.isOn)
            seen.insert(found.isEnabled)
        }
        XCTAssertEqual(seen, [true, false], "the control: the answer must come out both ways in this sweep")
        XCTAssertEqual(ScStr.thicknessAndOpacity, "Thickness and Opacity…")
    }

    /// The same item in the NSMenu: its `isEnabled` follows the choice, and a click on it sends the action that opens
    /// the pop-over at ⋯'s cell, which is what the model says ⋯'s cell is; a disabled one sends nothing.
    func testTheNSMenuItemFollowsTheChoiceAndOpensThePopoverAtTheMoreCell() throws {
        AppLanguage.override = .en
        for tool in Self.everyChoice {
            let m = model(tool: tool)
            var sent: [EditorAction] = []
            m.perform = { sent.append($0) }
            let menu = EditorMenu.make(for: m)
            menu.delegate?.menuNeedsUpdate?(menu)
            let item = try XCTUnwrap(flat(menu).first { $0.title == ScStr.thicknessAndOpacity }, "tool \(String(describing: tool))")
            let hasSteps = tool != nil && tool != .spotlight
            XCTAssertEqual(item.isEnabled, hasSteps, "tool \(String(describing: tool))")
            XCTAssertEqual(menu.index(of: item), 9, "Arrow, Shapes, Text, Steps, Blur, Crop, Select, Magnifier, Emoji, then the item")
            let parent = try XCTUnwrap(item.menu)
            parent.performActionForItem(at: parent.index(of: item))
            XCTAssertEqual(sent, !hasSteps ? [] : [.thicknessAndOpacity(anchorX: m.moreFrame.midX)],
                           "tool \(String(describing: tool)): a click opens the pop-over at ⋯, or does nothing when disabled")
        }
    }

    func testTheItemIsTitledInEveryLanguage() throws {
        var titles: Set<String> = []
        AppLanguage.each { language in
            let title = ScStr.thicknessAndOpacity
            XCTAssertFalse(title.isEmpty, "\(language)")
            titles.insert(title)
        }
        XCTAssertGreaterThan(titles.count, 4, "eight languages say it in more than one way: the strings are not translated")
    }

    /// **Every object the palette does not keep in its row has a symbol, is in the menu with it, and is the badge when chosen.**
    /// Asked of `EditorPalette.objects` itself, not of a list written here: the menu is built with `compactMap`, so a
    /// `.menu` or `.shapes` object whose symbol is nil would vanish from ⋯ and from its badge without a word.
    func testEveryObjectOutsideTheRowHasASymbolAndIsInTheMenu() {
        AppLanguage.override = .en
        let outside = EditorPalette.objects.filter { $0.place != .row }
        XCTAssertFalse(outside.isEmpty, "the control: no object is outside the row, so nothing is asked")
        let inMenu = tools(EditorMenu.items(for: model(tool: nil)))
        for object in outside {
            let name = "\(object.tool)"
            XCTAssertNotNil(object.symbol, "\(name) (\(object.place)) has no symbol, so the menu leaves it out")
            let entries = inMenu.filter { $0.title == ScStr.tool(object.tool) }
            XCTAssertEqual(entries.count, 1, "\(name) is not in the ⋯ menu exactly once: \(inMenu.map(\.title))")
            XCTAssertEqual(entries.first?.symbol, object.symbol, "\(name): the menu draws another symbol than the palette's table")
            XCTAssertEqual(entries.first?.action, .tool(object.tool), "\(name): the item sends another action")
            XCTAssertEqual(EditorPalette.moreBadge(for: model(tool: object.tool)), object.symbol, "\(name): the badge is not its symbol")
        }
        // Nothing else is in the menu as a tool but these, `afterSelect` (the lens and the emoji, which have no place in the row) and Crop and Select,
        // which are no `AnnotationTool`; the two after Select are asked the same way as the objects above.
        for late in EditorPalette.afterSelect {
            let name = "\(late.tool)"
            XCTAssertEqual(inMenu.filter { $0.title == ScStr.tool(late.tool) }.map(\.symbol), [late.symbol], "\(name) is not in the ⋯ menu once, with its symbol")
            XCTAssertEqual(EditorPalette.moreBadge(for: model(tool: late.tool)), late.symbol, "\(name): the badge is not its symbol")
        }
        XCTAssertEqual(inMenu.count, outside.count + EditorPalette.afterSelect.count + 2, "the menu has a tool the table does not know, or the reverse")
    }

    func testThePinIsInTheMenuOnlyWhileOfferedAndAfterSave() {
        AppLanguage.override = .en
        XCTAssertFalse(PinEntry.isOffered, "the control: this task is written for v1, where the pin is hidden")
        let hidden = EditorMenu.items(for: model(tool: nil))
        XCTAssertFalse(outline(hidden).contains("action:\(ScStr.pin)"), "the menu offers «\(ScStr.pin)» in v1: \(outline(hidden))")
        let shown = EditorMenu.items(for: model(tool: nil), pinOffered: true)
        XCTAssertEqual(outline(shown).suffix(3), ["action:\(ScStr.save)", "action:\(ScStr.pin)", "action:\(ScStr.share)"],
                       "the item replaces the palette's cell, right after Save, and Share… stands last")
        guard case .action(_, let action, true, false)? = shown.dropLast().last else { return XCTFail("Pin is not a plain enabled item") }
        XCTAssertEqual(outline(shown).dropLast(3).suffix(2), ["action:\(ScStr.save)", "action:\(ScStr.pin)"], "the item replaces the palette's cell, right after Save")
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

    /// **Only the tool items carry a key equivalent, and no item a modifier** (⌘S is not shown): the key is a label, and
    /// `TheMenuShowsTheToolKeysAndAKeyInTheOpenMenuDoesNothingTests` asks which letters.
    func testOnlyTheToolItemsCarryAKeyLabel() throws {
        AppLanguage.override = .en
        for tool in Self.everyChoice {
            let m = model(tool: tool)
            let menu = EditorMenu.make(for: m)
            menu.delegate?.menuNeedsUpdate?(menu)
            let all = flat(menu)
            XCTAssertGreaterThanOrEqual(all.filter { !$0.isSeparatorItem }.count, 8, "the menu is empty, so «no key» means nothing")
            XCTAssertEqual(all.filter { !$0.keyEquivalent.isEmpty }.map(\.title),
                           [ScStr.tool(.arrow), ScStr.tool(.rectangle), ScStr.tool(.ellipse), ScStr.tool(.line), ScStr.tool(.text), ScStr.tool(.blur)],
                           "tool \(String(describing: tool))")
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
        XCTAssertEqual(menu.items.count, 16)
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
                XCTAssertTrue(flat(menu).filter { $0.title != ScStr.fill && $0.title != ScStr.thicknessAndOpacity && !$0.isSeparatorItem && $0.action != nil }.allSatisfy(\.isEnabled),
                              "\(context): another item is disabled")
            }
        }
        XCTAssertEqual(seen, [true, false], "the control: the rule must come out both ways in this sweep")
    }

    // MARK: - The badge on ⋯

    func testTheBadgeIsTheSymbolOfTheChosenMenuToolAndNothingForARowObject() {
        let expected: [(AnnotationTool?, String?)] = [
            (.arrow, "arrow.up.right"), (.rectangle, "rectangle"), (.ellipse, "circle"), (.line, "line.diagonal"),
            (nil, "cursorarrow"), (.pen, nil), (.pencil, nil), (.highlighter, nil), (.blur, "square.grid.3x3"), (.text, "textformat"),
            (.step, "1.circle"), (.spotlight, nil), (.magnifier, "plus.magnifyingglass"), (.emoji, "face.smiling"),
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
