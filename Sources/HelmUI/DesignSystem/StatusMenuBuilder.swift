import AppKit

/// Builds the status item's menu.
///
/// Split out of `StatusItemController` so the thing that is easy to get wrong
/// — which item carries which glyph, and where the rules fall — can be
/// asserted instead of squinted at in a screenshot.
public enum StatusMenuBuilder {

    /// One row: what to call it, what to draw beside it, and which module it
    /// opens.
    public struct Entry {
        public let id: String
        public let title: String
        public let symbol: String

        public init(id: String, title: String, symbol: String) {
            self.id = id
            self.title = title
            self.symbol = symbol
        }
    }

    /// A run of modules that belong together, named the way the sidebar names
    /// them. The menu shows no headings — a menu with section titles reads as
    /// a menu with disabled items — so the grouping is carried by rules alone.
    public struct Group {
        public let entries: [Entry]

        public init(entries: [Entry]) { self.entries = entries }
    }

    public static let glyphSize = NSSize(width: 15, height: 15)

    public static func menu(settingsTitle: String, quitTitle: String, groups: [Group],
                     target: AnyObject?,
                     openSettings: Selector, openModule: Selector, quit: Selector) -> NSMenu {
        let menu = NSMenu()

        let settings = NSMenuItem(title: settingsTitle, action: openSettings, keyEquivalent: ",")
        settings.target = target
        settings.image = glyph("gearshape")
        menu.addItem(settings)

        for group in groups where !group.entries.isEmpty {
            menu.addItem(.separator())
            for entry in group.entries {
                let item = NSMenuItem(title: entry.title, action: openModule, keyEquivalent: "")
                item.target = target
                item.representedObject = entry.id
                item.image = glyph(entry.symbol)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: quitTitle, action: quit, keyEquivalent: "q")
        quitItem.target = target
        quitItem.image = glyph("power")
        menu.addItem(quitItem)
        return menu
    }

    /// Template so the glyph takes the menu's own colour — including the
    /// inverted one it gets while the row is highlighted, which a coloured
    /// image does not.
    public static func glyph(_ name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        else { return nil }
        image.isTemplate = true
        image.size = glyphSize
        return image
    }
}
