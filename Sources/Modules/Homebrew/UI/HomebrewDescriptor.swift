import Foundation
import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Homebrew_Engine

@MainActor public final class HomebrewDescriptor: ModuleDescriptor {
    public static let id = ModuleID("homebrew")
    public static let metadata = ModuleMetadata(
        id: id, name: HbStr.moduleName, summary: HbStr.summary,
        sfSymbol: "shippingbox", permissions: [])
    public static let isolation: ModuleIsolation = .inProcess
    public static let category: ModuleCategory = .maintenance

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        let ports = HomebrewSystemPorts()
        return HomebrewEngine(locator: ports.locator, runner: ports.runner,
                              privileged: ports.privileged, user: NSUserName())
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        MenuBarContribution(panelTile: AnyView(HomebrewPanelTile()))
    }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(HomebrewSettingsPage(vm: vm))
    }
    // statusAppearance: default (.inactive).
}
