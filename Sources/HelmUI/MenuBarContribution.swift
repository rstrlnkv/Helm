import SwiftUI

public struct MenuBarContribution {
    /// Interactive tile shown directly in the panel (quick toggles, timers, …).
    public var panelTile: AnyView?
    /// Utility modules have no quick actions worth a tile: the panel lists them
    /// compactly behind a disclosure and opens Settings on click, so the panel
    /// stays focused on what you can act on from the menu bar.
    public var isUtility: Bool
    public init(panelTile: AnyView? = nil, isUtility: Bool = false) {
        self.panelTile = panelTile
        self.isUtility = isUtility
    }

    /// A module whose UI lives in Settings only. Computed (not a stored global)
    /// because `AnyView` isn't `Sendable`.
    public static var utility: MenuBarContribution {
        MenuBarContribution(panelTile: nil, isUtility: true)
    }
}

public enum ModuleCategory: String, CaseIterable, Sendable {
    case power, network, clipboard, window, media, files, appearance, utilities, misc
}

public extension Notification.Name {
    /// Posted to bring up the Settings window. `object` may carry a module id
    /// (String) to open that module's page directly.
    static let helmOpenSettings = Notification.Name("helmOpenSettings")
    /// Posted when a module is switched off. A module's UI state can outlive
    /// its page on purpose — losing a minute-long scan to a sidebar click is
    /// hostile — but "outlives the page" is not "outlives the module": a scan
    /// tree the person switched off is gigabytes nobody asked to keep.
    static let helmModuleDisabled = Notification.Name("helmModuleDisabled")
    /// Posted when a module is switched **on** by hand — not at launch, where
    /// `bootstrap` enables every module the person already had on. `object`
    /// carries the module id. A module that has something to do the moment it is
    /// switched on does it here.
    static let helmModuleEnabled = Notification.Name("helmModuleEnabled")
}
