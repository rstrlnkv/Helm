import AppKit
import HelmAppStrings
import HelmRuntime
import HelmUI

/// **The header row's one right-click menu**, an `NSMenu` the settings window pops up itself
/// (`SettingsWindow.watchHeaderPresses`): what it offers, in what order, what each item writes and which press
/// opens it is said here once.
///
/// **Why the window and not the row.** The row lies in the window's title bar zone (`.fullSizeContentView`, a
/// transparent title bar), where AppKit's own title bar view takes a right-click before the hosting view, so a
/// SwiftUI `.contextMenu` on the row never opens for a person (opened through accessibility, it draws a blank row
/// after each choice and writes nothing). A local event monitor sees the press first, and
/// `opens(type:modifiers:at:band:excluding:)` decides it from a point alone.
///
/// **Top to bottom**: Page header (With Icon, Without Icon) on every page; Tab labels (Text Only, Icon Only,
/// Icon and Text) only where the page has tabs; Appearance (Flat, Liquid Glass) on every page; Always Collapse Search,
/// a plain tick, only where the page has a search, after a separator of its own. Absent rather than
/// dimmed where a part does not apply: a context menu hides what cannot act (HIG, context menus). Appearance is the
/// mirror of General's `BarAppearanceRow`, Page header of `PageHeaderRow`.
///
/// **Built each time it opens**, from the store, so a tick is never older than the setting. **A write goes through
/// `AppSettings` only**: its setter posts the change that reaches the row and General's rows, the same path
/// General's rows take, and refuses a value equal to the stored one. `NSMenuItem.target` is weak, so each item
/// holds its `Choice` as `representedObject`, which is strong.
@MainActor
enum HeaderBarMenu {
    /// **Whether a press opens the menu**: the right button, or the left one with Control held (how a trackpad
    /// without a right click sends it), inside the header row's `band` and outside every `excluding` rect — the
    /// window's own buttons and the search field while it is being edited, whose text menu is the one a person
    /// is reaching for there. All in window coordinates.
    nonisolated static func opens(type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags, at point: NSPoint,
                                  band: NSRect, excluding: [NSRect]) -> Bool {
        switch type {
        case .rightMouseDown: break
        case .leftMouseDown: guard modifiers.contains(.control) else { return false }
        default: return false
        }
        return band.contains(point) && !excluding.contains { $0.contains(point) }
    }

    /// The rects of what keeps its own press, in window coordinates: the three window buttons, and the view
    /// whose text is being edited.
    static func excluded(in window: NSWindow) -> [NSRect] {
        var rects = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { kind in
            window.standardWindowButton(kind).map { $0.convert($0.bounds, to: nil) }
        }
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
           let field = editor.delegate as? NSView {
            rects.append(field.convert(field.bounds, to: nil))
        }
        return rects
    }

    /// The menu for a page; `tabLabels` is offered only where `hasTabs`, Always Collapse Search only where `hasSearch`.
    static func menu(hasTabs: Bool, hasSearch: Bool, in store: NamespacedStore = AppSettings.store) -> NSMenu {
        let menu = NSMenu(title: AppStr.pageBar)
        menu.autoenablesItems = false
        var items = [NSMenuItem.sectionHeader(title: AppStr.pageBar)]
        let pageBar = AppSettings.pageBarStyle(in: store)
        items += [(PageBarStyle.moduleName, AppStr.pageBarWithIcon), (.windowTitle, AppStr.pageBarWithoutIcon)]
            .map { choice, title in
                tick(title, choice == pageBar) { AppSettings.setPageBarStyle(choice, in: store) }
            }
        if hasTabs {
            let labels = AppSettings.tabLabels(in: store)
            items.append(.separator())
            items.append(.sectionHeader(title: AppStr.tabLabels))
            items += [(HeaderTabLabels.text, AppStr.tabLabelsText), (.icons, AppStr.tabLabelsIcons),
                      (.iconsAndText, AppStr.tabLabelsIconsAndText)].map { choice, title in
                tick(title, choice == labels) { AppSettings.setTabLabels(choice, in: store) }
            }
        }
        let look = AppSettings.barAppearance(in: store)
        items.append(.separator())
        items.append(.sectionHeader(title: AppStr.appearance))
        items += [(HelmBarAppearance.flat, AppStr.barAppearanceFlat),
                  (.liquidGlass, AppStr.barAppearanceLiquidGlass)].map { choice, title in
            tick(title, choice == look) { AppSettings.setBarAppearance(choice, in: store) }
        }
        if hasSearch {
            let collapses = AppSettings.alwaysCollapseSearch(in: store)
            items.append(.separator())
            items.append(tick(AppStr.alwaysCollapseSearch, collapses) {
                AppSettings.setAlwaysCollapseSearch(!collapses, in: store)
            })
        }
        for item in items { menu.addItem(item) }
        return menu
    }

    private static func tick(_ title: String, _ isOn: Bool, write: @escaping () -> Void) -> NSMenuItem {
        let choice = Choice(write: write)
        let item = NSMenuItem(title: title, action: #selector(Choice.chose(_:)), keyEquivalent: "")
        item.target = choice
        item.representedObject = choice
        item.state = isOn ? .on : .off
        return item
    }

    @MainActor final class Choice: NSObject {
        private let write: () -> Void
        init(write: @escaping () -> Void) { self.write = write }
        @objc func chose(_ sender: NSMenuItem) { write() }
    }
}
