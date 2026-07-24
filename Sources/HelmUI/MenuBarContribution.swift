import SwiftUI

public struct MenuBarContribution {
    /// Interactive tile shown directly in the panel (quick toggles, timers, …).
    public var panelTile: AnyView?
    /// Utility modules have no quick actions worth a tile: the panel lists them
    /// compactly behind a disclosure and opens Settings on click, so the panel
    /// stays focused on what you can act on from the menu bar.
    public var isUtility: Bool
    /// Width this tile asks for in the grid layout (ignored in the list layout).
    public var span: PanelTileSpan

    public init(panelTile: AnyView? = nil, isUtility: Bool = false, span: PanelTileSpan = .wide) {
        self.panelTile = panelTile
        self.isUtility = isUtility
        self.span = span
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
}
