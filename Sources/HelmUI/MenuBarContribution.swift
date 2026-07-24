import SwiftUI
public struct MenuBarContribution {
    public var panelTile: AnyView?
    public init(panelTile: AnyView? = nil) {
        self.panelTile = panelTile
    }
}
public enum ModuleCategory: String, CaseIterable, Sendable {
    case power, network, clipboard, window, media, files, appearance, misc
}
