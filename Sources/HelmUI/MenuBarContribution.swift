import SwiftUI
public struct MenuBarContribution {
    public var panelTile: AnyView?
    public init(panelTile: AnyView? = nil) {
        self.panelTile = panelTile
    }
}
public enum ModuleCategory: String, CaseIterable, Sendable {
    case power, network, clipboard, window, media, files, appearance, maintenance, misc
}

public extension Notification.Name {
    /// Posted by a module (e.g. a panel tile) to bring up the Settings window.
    static let helmOpenSettings = Notification.Name("helmOpenSettings")
}
