import SwiftUI
public struct StatusItemSpec { public init() {} }   // reserved v1, unused
public struct MenuBarContribution {
    public var panelTile: AnyView?
    public var statusItem: StatusItemSpec?
    public init(panelTile: AnyView? = nil, statusItem: StatusItemSpec? = nil) {
        self.panelTile = panelTile; self.statusItem = statusItem
    }
}
public enum ModuleCategory: String, CaseIterable, Sendable {
    case power, clipboard, window, media, files, appearance, misc
}
