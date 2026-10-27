import AppKit
import HelmUI

/// **The bar's one right-click menu.** `SettingsToolbar` hands
/// `menu(delegate:)`'s menu to each centre switcher and pops it up over the window's frame. It calls
/// `fill(_:showing:)` from its own `menuNeedsUpdate(_:)`, so what the menu
/// offers, in what order and what each item writes is said here once.
///
/// **What it offers, top to bottom**: the page header on every page; the tabs' label style only where the page
/// has tabs; Appearance (Flat, Liquid Glass) on every page; Always Collapse Search only where the page has a
/// search field, even one disabled right now. Absent rather than dimmed where it does not apply — a context
/// menu hides what cannot act (HIG, context menus). The Appearance section is the mirror of General's
/// "Toolbar style" row (`BarAppearanceRow`); `SettingsToolbar` draws by the look
/// (its `ShapeSignature` reads `AppSettings.barAppearance`).
///
/// **Every item's target is `actions`**: `NSMenuItem.target` is weak, so the one object is a
/// `static let`. Each action only writes the setting; the setting's own notification is what reaches the bar and
/// General's row, the same path General's Appearance rows take.
@MainActor
enum ShellBarMenu {
    /// An empty menu titled as the bar, to be filled by `fill(_:showing:)` each time it opens.
    /// `autoenablesItems` is off, and `items` sets `isEnabled` on every item that is not a separator, the
    /// section headers included.
    static func menu(delegate: any NSMenuDelegate) -> NSMenu {
        let menu = NSMenu(title: AppStr.pageBar)
        menu.autoenablesItems = false
        menu.delegate = delegate
        return menu
    }

    /// `tabLabels` and `alwaysCollapseSearch` are nil for a page without that part.
    static func items(pageBarStyle: PageBarStyle, tabLabels: ToolbarSwitcherStyle?,
                      appearance: HelmBarAppearance, alwaysCollapseSearch: Bool?) -> [NSMenuItem] {
        var items: [NSMenuItem] = [NSMenuItem.sectionHeader(title: AppStr.pageBar)]
        for (choice, title) in [(PageBarStyle.moduleName, AppStr.pageBarWithIcon),
                                (PageBarStyle.windowTitle, AppStr.pageBarWithoutIcon)] {
            let item = NSMenuItem(title: title, action: #selector(Actions.chosePageBar(_:)), keyEquivalent: "")
            item.target = actions
            item.representedObject = choice.rawValue
            item.state = choice == pageBarStyle ? .on : .off
            items.append(item)
        }
        if let tabLabels {
            items.append(.separator())
            items.append(NSMenuItem.sectionHeader(title: AppStr.tabLabels))
            for choice in ToolbarSwitcherStyle.allCases {
                let item = NSMenuItem(title: choice.label, action: #selector(Actions.choseTabLabels(_:)),
                                      keyEquivalent: "")
                item.target = actions
                item.representedObject = choice.rawValue
                item.state = choice == tabLabels ? .on : .off
                items.append(item)
            }
        }
        items.append(.separator())
        items.append(NSMenuItem.sectionHeader(title: AppStr.appearance))
        for choice in HelmBarAppearance.allCases {
            let title = choice == .flat ? AppStr.barAppearanceFlat : AppStr.barAppearanceLiquidGlass
            let item = NSMenuItem(title: title, action: #selector(Actions.choseAppearance(_:)), keyEquivalent: "")
            item.target = actions
            item.representedObject = choice.rawValue
            item.state = choice == appearance ? .on : .off
            items.append(item)
        }
        if let alwaysCollapseSearch {
            items.append(.separator())
            let item = NSMenuItem(title: AppStr.alwaysCollapseSearch,
                                  action: #selector(Actions.toggledCollapseSearch(_:)), keyEquivalent: "")
            item.target = actions
            item.state = alwaysCollapseSearch ? .on : .off
            items.append(item)
        }
        for item in items where !item.isSeparatorItem { item.isEnabled = true }
        return items
    }

    /// Fills `menu` for the page whose content `content` is, at the moment it opens — a page switch, a setting
    /// changed in General or a language change since the last time has nothing else to rebuild it by.
    /// The one place the menu's sections are derived from a page's parts and from the settings they tick.
    static func fill(_ menu: NSMenu, showing content: HelmPageToolbarContent?) {
        let hasTabs = !(content?.tabs.isEmpty ?? true)
        let hasSearch = content?.search != nil
        menu.removeAllItems()
        for item in items(pageBarStyle: AppSettings.pageBarStyle,
                          tabLabels: hasTabs ? AppSettings.toolbarSwitcherStyle : nil,
                          appearance: AppSettings.barAppearance,
                          alwaysCollapseSearch: hasSearch ? AppSettings.alwaysCollapseSearch : nil) {
            menu.addItem(item)
        }
    }

    static let actions = Actions()

    @MainActor final class Actions: NSObject {
        @objc func chosePageBar(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let choice = PageBarStyle(rawValue: raw),
                  choice != AppSettings.pageBarStyle else { return }
            AppSettings.pageBarStyle = choice
        }

        @objc func choseTabLabels(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let choice = ToolbarSwitcherStyle(rawValue: raw),
                  choice != AppSettings.toolbarSwitcherStyle else { return }
            AppSettings.toolbarSwitcherStyle = choice
        }

        @objc func choseAppearance(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let choice = HelmBarAppearance(rawValue: raw),
                  choice != AppSettings.barAppearance else { return }
            AppSettings.barAppearance = choice
        }

        @objc func toggledCollapseSearch(_ sender: NSMenuItem) {
            AppSettings.alwaysCollapseSearch.toggle()
        }
    }
}
