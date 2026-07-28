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

    /// The category's accent, used for sidebar badges and panel utility rows so
    /// the same category always reads in the same color.
    public var tint: Color {
        switch self {
        case .power: return .orange
        case .network: return .indigo
        case .clipboard: return .blue
        case .window: return .green
        case .media: return .pink
        case .files: return .cyan
        case .appearance: return .purple
        case .utilities: return .pink
        case .misc: return .gray
        }
    }
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
}
