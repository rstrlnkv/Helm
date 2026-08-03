import AppKit
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

    /// Light, dark, or the system's choice. Applied to `NSApp`, which covers
    /// every window Helm owns, including the menu-bar panel.
    static var appearance: AppAppearance {
        get { AppAppearance.from(store.string("appearance", default: AppAppearance.system.rawValue)) }
        set {
            store.set(newValue.rawValue, for: "appearance")
            applyAppearance()
        }
    }

    static func applyAppearance() {
        NSApp.appearance = appearance.appearanceName.flatMap {
            NSAppearance(named: NSAppearance.Name($0))
        }
    }

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

    /// Background scans the person switched off, by module id.
    ///
    /// An off-list rather than an on-list, so a scan added by a future version
    /// arrives switched on without a migration — the same shape the module
    /// enable flags use.
    ///
    /// Disk starts in it. The other two answer a question the person asked by
    /// installing the module; Disk builds and refreshes an 8 MB index of every
    /// filename on the volume, on machines whose owner never ran a disk scan.
    static var disabledScans: Set<String> {
        get {
            guard let stored = store.object("disabledScans") as? [String] else {
                return ["disk"]
            }
            return Set(stored)
        }
        set { store.set(Array(newValue).sorted(), for: "disabledScans") }
    }

    /// When each background scan last completed, by module id.
    static var lastScanAt: [String: Date] {
        get { store.doubleTable("lastScanAt").mapValues(Date.init(timeIntervalSince1970:)) }
        set { store.set(newValue.mapValues(\.timeIntervalSince1970), for: "lastScanAt") }
    }

    /// How many times each scan ran today. Reset when the calendar day turns.
    static var scanRunsToday: [String: Int] {
        get { store.intTable("scanRunsToday") }
        set { store.set(newValue, for: "scanRunsToday") }
    }

    /// The calendar day `scanRunsToday` is counting.
    static var scanBudgetDay: Date? {
        get {
            let stored = store.double("scanBudgetDay", default: 0)
            return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
        }
        set { store.set(newValue?.timeIntervalSince1970 ?? 0, for: "scanBudgetDay") }
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
