import AppKit

/// A `LaunchpadMenu` as an `NSMenu`, built once when the panel pops it (`LaunchpadPanel`). Items are enabled by the description alone
/// (`autoenablesItems` off). `NSMenuItem.target` is weak, so each action item holds its `Choice` as `representedObject`, which is strong
/// (as `HeaderBarMenu` does).
@MainActor
enum LaunchpadNSMenu {
    static func make(_ menu: LaunchpadMenu, perform: @escaping (LaunchpadMenuAction) -> Void) -> NSMenu {
        let built = NSMenu()
        built.autoenablesItems = false
        for item in rows(menu.items, perform) { built.addItem(item) }
        return built
    }

    private static func rows(_ items: [LaunchpadMenu.Item], _ perform: @escaping (LaunchpadMenuAction) -> Void) -> [NSMenuItem] {
        items.map { item in
            switch item {
            case .separator:
                return .separator()
            case .submenu(let title, let subrows):
                let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let sub = NSMenu(title: title)
                sub.autoenablesItems = false
                for row in rows(subrows, perform) { sub.addItem(row) }
                parent.submenu = sub
                return parent
            case .action(let title, let action, let enabled, let checked):
                let choice = Choice(action: action, perform: perform)
                let row = NSMenuItem(title: title, action: #selector(Choice.chose(_:)), keyEquivalent: "")
                row.target = choice
                row.representedObject = choice
                row.isEnabled = enabled
                row.state = checked ? .on : .off
                return row
            }
        }
    }

    @MainActor final class Choice: NSObject {
        private let action: LaunchpadMenuAction
        private let perform: (LaunchpadMenuAction) -> Void
        init(action: LaunchpadMenuAction, perform: @escaping (LaunchpadMenuAction) -> Void) {
            self.action = action
            self.perform = perform
        }
        @objc func chose(_ sender: NSMenuItem) { perform(action) }
    }
}
