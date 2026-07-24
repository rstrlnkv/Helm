import Foundation
import HelmRuntime

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

    static var menuBarIconSize: String {
        get { store.string("menuBarIconSize", default: "medium") }
        set {
            store.set(newValue, for: "menuBarIconSize")
            NotificationCenter.default.post(name: .helmMenuBarStyleChanged, object: nil)
        }
    }
}
