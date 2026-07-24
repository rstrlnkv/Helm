import Foundation
import HelmRuntime
import HelmUI

extension Notification.Name {
    /// Posted when the host menu-bar icon style changes so the status item redraws.
    static let helmMenuBarStyleChanged = Notification.Name("helmMenuBarStyleChanged")
}

/// App-level (not per-module) settings, e.g. the menu-bar icon shape.
@MainActor enum AppSettings {
    static let store = NamespacedStore(namespace: "app", backing: UserDefaults.standard)

    static var menuBarIconStyle: String {
        get { store.string("menuBarIconStyle", default: "ring") }
        set {
            store.set(newValue, for: "menuBarIconStyle")
            NotificationCenter.default.post(name: .helmMenuBarStyleChanged, object: nil)
        }
    }

    /// Panel presentation. "list" (the stacked layout) is the default — the grid
    /// is an opt-in experiment kept behind Settings → Menu Bar → Panel layout.
    static var panelLayout: String {
        get { store.string("panelLayout", default: PanelLayoutStyle.list.rawValue) }
        set {
            store.set(newValue, for: "panelLayout")
            NotificationCenter.default.post(name: .helmMenuBarStyleChanged, object: nil)
        }
    }

    static var menuBarIconSize: String {
        get { store.string("menuBarIconSize", default: "medium") }
        set {
            store.set(newValue, for: "menuBarIconSize")
            NotificationCenter.default.post(name: .helmMenuBarStyleChanged, object: nil)
        }
    }
}
