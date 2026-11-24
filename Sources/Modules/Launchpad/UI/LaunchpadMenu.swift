import Foundation
import HelmUI
import Module_Launchpad_Engine

/// What a menu row does, as data: the description stays `Equatable`, and `LaunchpadScreenState.perform(_:)` looks the app or the folder up again
/// when the row is pressed, so a snapshot that changed while the menu tracked cannot act on stale data.
enum LaunchpadMenuAction: Equatable {
    case hide(AppID), show(AppID)
    case move(AppID, LaunchpadCategoryTarget?)
    case reveal(AppID), copyPath(AppID)
    case resize(UUID, large: Bool)
    case beginEditing
    case askToRemove(AppID)
}

/// **The menu of a tile, the window's background and a category block's large icon, as a value** with no AppKit in it: the panel pops it as an `NSMenu`
/// (`LaunchpadNSMenu`) on a right-click or a Control-click, and VoiceOver's "show menu" action pops the same one. SwiftUI's own context menu is not
/// used: it owns the `NSMenu` and rebuilds its items on every render of the hosting view, which starves an open menu.
///
/// An app's menu: Hide (Show in the Hidden card, which has no Move), "Move to category" with the app's own category as the undo on top
/// (disabled while the app is not moved) and every category under it, the one the app is in now checked, "Others" last; Show in Finder and
/// Copy Path where its file is offered (`LaunchpadScreenState.fileActions(for:)`); then Edit where the mode can begin and, in the mode, Remove where the
/// Uninstaller offers the app. A folder's: its other size, then Edit. The background's: Edit. A VoiceOver custom action cannot be a submenu, and 29 of
/// them would be noise: VoiceOver reaches Move through this menu (VO-Shift-M), and Hide stays an action as well.
struct LaunchpadMenu: Equatable {
    indirect enum Item: Equatable {
        case action(title: String, LaunchpadMenuAction, enabled: Bool = true, checked: Bool = false)
        case submenu(title: String, [Item])
        case separator
    }

    var items: [Item]

    /// Where the app is shown now: its move, else its own.
    static func effective(moved: LaunchpadCategoryTarget?, raw: String?) -> LaunchpadCategoryTarget {
        moved ?? LaunchpadCategoryTarget(raw: raw)
    }

    /// An app's menu. `hasFiles`: its file is offered; `canEdit`: the mode can begin; `removable`: the mode is on and the Uninstaller offers the app.
    static func app(_ app: CatalogApp, moved: LaunchpadCategoryTarget?, hasFiles: Bool, inHidden: Bool = false, canEdit: Bool = false,
                    removable: Bool = false, language: AppLanguage = AppLanguage.current) -> LaunchpadMenu {
        var items: [Item] = []
        if inHidden {
            items.append(.action(title: HelmWord.show, .show(app.id)))
        } else {
            let effective = Self.effective(moved: moved, raw: app.category)
            items.append(.action(title: LpStr.hide, .hide(app.id)))
            var rows: [Item] = [.action(title: LpStr.ownCategory, .move(app.id, nil), enabled: moved != nil), .separator]
            rows += LaunchpadCategoryName.choices(language: language).map { choice in
                .action(title: choice.title, .move(app.id, choice.target), checked: choice.target == effective)
            }
            items.append(.submenu(title: LpStr.moveToCategory, rows))
        }
        if hasFiles {
            items += [.separator, .action(title: HelmWord.showInFinder, .reveal(app.id)), .action(title: LpStr.copyPath, .copyPath(app.id))]
        }
        if canEdit { items.append(.action(title: HelmWord.edit, .beginEditing)) }
        if removable { items.append(.action(title: LpStr.removeAction, .askToRemove(app.id))) }
        return LaunchpadMenu(items: items)
    }

    /// A folder's menu: its other size (`large` is what it is now), then Edit where the mode can begin.
    static func folder(_ id: UUID, large: Bool, canEdit: Bool) -> LaunchpadMenu {
        var items: [Item] = [.action(title: large ? LpStr.shrinkFolder : LpStr.enlargeFolder, .resize(id, large: !large))]
        if canEdit { items.append(.action(title: HelmWord.edit, .beginEditing)) }
        return LaunchpadMenu(items: items)
    }

    /// The window's background: Edit.
    static let background = LaunchpadMenu(items: [.action(title: HelmWord.edit, .beginEditing)])
}
