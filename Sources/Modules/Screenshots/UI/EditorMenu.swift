import AppKit
import HelmUI
import Module_Screenshots_Engine

/// One line of the ⋯ menu, as a value: what it says, whether it is checked, what it sends.
enum EditorMenuItem: Equatable {
    case tool(title: String, symbol: String, isOn: Bool, action: EditorAction)
    case submenu(title: String, isOn: Bool, children: [EditorMenuItem])
    case separator
    /// A plain item; `isOn` is a check mark (Filled), false for Save and Pin.
    case action(title: String, action: EditorAction, isEnabled: Bool, isOn: Bool)
}

/// The ⋯ menu, in two layers like `StatusMenuBuilder`: `items(for:)` is pure (the model in, values out) and `make(for:)` is
/// the thin `NSMenu` over it. The tools come from `EditorPalette.objects`, the list the palette's row is drawn from, so a
/// tool is placed once and the check mark cannot differ from what the palette says is chosen.
///
/// Order: the row objects taken off the row, Arrow, Shapes ▸ (Rectangle, Oval, Line, a separator, Filled), Select, Thickness and Opacity… (enabled while a
/// tool is chosen), a separator, Save, and Pin only while
/// `PinEntry.isOffered`. **Filled** is checked by the fill setting and enabled exactly where the fill applies
/// (`EditorBarModel.fillApplies`): a box is the subject, so the fill changes what is drawn or selected now. A disabled
/// `NSMenuItem` sends nothing even when its action is performed.
/// **Shapes** is checked while a shape is the tool. A click on the chosen tool sends what choosing it sent: the
/// editor's rule puts a tool down by choosing it twice.
enum EditorMenu {
    /// The key a menu item shows at its right, for the tools that have one (`EditorKeys.toolKeys`): a label and nothing
    /// else, since `choose` drops an action that a key sent. Returning "" drops every label at once.
    static func keyEquivalent(of action: EditorAction) -> String {
        guard case .tool(let tool) = action else { return "" }
        return EditorKeys.toolKeys.first { $0.tool == tool }?.letter.lowercased() ?? ""
    }

    /// The image an item draws beside its title. Returning nil drops every item image at once; it was not drawn
    /// beside a checked item in the overlay's measurement, which is why this is one place.
    static func image(symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    /// Whether an action's event is a key event typing a letter of `EditorKeys.toolKeys`: `Filler.choose` drops an action
    /// for which this is true. A menu runs a key equivalent while it is open, and the owner has decided that a tool's letter
    /// pressed in the open menu does nothing; the editor's own keys meet the menu closed. Return and space on a highlighted
    /// item are key events too, but no letter of that table, so they are a choice (keyboard navigation, VoiceOver) and pass.
    static func isSentByAKey(_ event: NSEvent?) -> Bool {
        guard event?.type == .keyDown, let typed = event?.charactersIgnoringModifiers?.lowercased() else { return false }
        return EditorKeys.toolKeys.contains { $0.letter.lowercased() == typed }
    }

    @MainActor static func items(for model: EditorBarModel, pinOffered: Bool = PinEntry.isOffered) -> [EditorMenuItem] {
        func tool(_ object: (tool: AnnotationTool, symbol: String?, place: EditorPalette.Place)) -> EditorMenuItem? {
            guard let symbol = object.symbol else { return nil }
            return .tool(title: ScStr.tool(object.tool), symbol: symbol, isOn: model.tool == object.tool, action: .tool(object.tool))
        }
        let shapes = EditorPalette.objects.filter { $0.place == .shapes }
        // A row object the person took off the row stands first, above the glyph tools, checked like them; its key is shown.
        var items = EditorPalette.rowTools.filter { !model.isOnRow($0) }.map {
            EditorMenuItem.tool(title: ScStr.tool($0), symbol: EditorPalette.menuSymbol(ofRowTool: $0), isOn: model.tool == $0, action: .tool($0))
        }
        items += EditorPalette.objects.filter { $0.place == .menu }.compactMap(tool)
        items.append(.submenu(title: ScStr.shapes, isOn: shapes.contains { $0.tool == model.tool },
                              children: shapes.compactMap(tool) + [.separator,
                                  .action(title: ScStr.fill, action: .toggleFill, isEnabled: model.fillApplies, isOn: model.style.filled)]))
        items.append(.tool(title: ScStr.select, symbol: EditorPalette.selectSymbol, isOn: model.tool == nil, action: .select))
        // Every tool has steps and Select has none; the item stays in its place either way. It opens the pop-over at ⋯.
        items.append(.action(title: ScStr.thicknessAndOpacity, action: .thicknessAndOpacity(anchorX: model.moreFrame.midX),
                             isEnabled: model.tool != nil, isOn: false))
        items += [.separator, .action(title: ScStr.save, action: .exit(.save), isEnabled: true, isOn: false)]
        if pinOffered { items.append(.action(title: ScStr.pin, action: .exit(.pin), isEnabled: true, isOn: false)) }
        return items
    }

    /// An `NSMenu` that is filled from `items(for:)` each time it opens, and keeps the object that does it: a menu holds
    /// its delegate weakly.
    @MainActor static func make(for model: EditorBarModel) -> NSMenu {
        // A menu sends an item's action through the application object, which a process that has not made it yet lacks.
        _ = NSApplication.shared
        return Menu(filler: Filler(model: model))
    }

    @MainActor private final class Menu: NSMenu {
        private let filler: Filler
        init(filler: Filler) {
            self.filler = filler
            super.init(title: "")
            autoenablesItems = false
            delegate = filler
        }
        required init(coder: NSCoder) { fatalError("not from a nib") }
    }

    @MainActor private final class Filler: NSObject, NSMenuDelegate {
        let model: EditorBarModel
        init(model: EditorBarModel) { self.model = model }

        func menuNeedsUpdate(_ menu: NSMenu) {
            fill(menu, with: EditorMenu.items(for: model))
        }

        private func fill(_ menu: NSMenu, with items: [EditorMenuItem]) {
            menu.removeAllItems()
            menu.autoenablesItems = false
            for item in items {
                switch item {
                case .separator:
                    menu.addItem(.separator())
                case .tool(let title, let symbol, let isOn, let action):
                    let entry = entry(title, action, isOn: isOn, enabled: true)
                    entry.image = EditorMenu.image(symbol: symbol)
                    menu.addItem(entry)
                case .action(let title, let action, let isEnabled, let isOn):
                    menu.addItem(entry(title, action, isOn: isOn, enabled: isEnabled))
                case .submenu(let title, let isOn, let children):
                    let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    parent.state = isOn ? .on : .off
                    parent.keyEquivalentModifierMask = []
                    let sub = NSMenu(title: title)
                    fill(sub, with: children)
                    parent.submenu = sub
                    menu.addItem(parent)
                }
            }
        }

        private func entry(_ title: String, _ action: EditorAction, isOn: Bool, enabled: Bool) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: EditorMenu.keyEquivalent(of: action))
            entry.target = self
            entry.keyEquivalentModifierMask = []
            entry.representedObject = action
            entry.state = isOn ? .on : .off
            entry.isEnabled = enabled
            return entry
        }

        @objc private func choose(_ item: NSMenuItem) {
            guard !EditorMenu.isSentByAKey(NSApp.currentEvent), let action = item.representedObject as? EditorAction else { return }
            model.perform(action)
        }
    }
}
