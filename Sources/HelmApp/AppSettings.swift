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

    /// nil = follow the build type (dev builds log, stable builds don't);
    /// true/false = the user overrode it in Diagnostics.
    static var loggingOverride: Bool? {
        get {
            // -1 = follow the build type, 0/1 = explicit user choice.
            let raw = store.int("loggingOverride", default: -1)
            return raw < 0 ? nil : raw == 1
        }
        set {
            store.set(newValue.map { $0 ? 1 : 0 } ?? -1, for: "loggingOverride")
        }
    }

    /// Ids in the order the user arranged them in the panel.
    static var moduleOrder: [String] {
        get { store.stringArray("moduleOrder") }
        set {
            store.set(newValue, for: "moduleOrder")
            NotificationCenter.default.post(name: .helmModuleOrderChanged, object: nil)
        }
    }

    static var menuBarIconStyle: String {
        get { store.string("menuBarIconStyle", default: "ring") }
        set {
            store.set(newValue, for: "menuBarIconStyle")
            NotificationCenter.default.post(name: .helmMenuBarStyleChanged, object: nil)
        }
    }

    /// Optional shortcuts in the panel footer; both actions are always available
    /// from the status item's right-click menu, so these default to off.
    static var showSettingsButton: Bool {
        get { store.bool("showSettingsButton", default: false) }
        set {
            store.set(newValue, for: "showSettingsButton")
            NotificationCenter.default.post(name: .helmMenuBarStyleChanged, object: nil)
        }
    }

    static var showQuitButton: Bool {
        get { store.bool("showQuitButton", default: false) }
        set {
            store.set(newValue, for: "showQuitButton")
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
