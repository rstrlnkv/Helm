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
    public static let category: ModuleCategory = .utilities
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        let ports = HomebrewSystemPorts()
        return HomebrewEngine(locator: ports.locator, runner: ports.runner,
                              privileged: ports.privileged, user: NSUserName())
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(HomebrewSettingsPage(vm: vm))
    }
    // statusAppearance: default (.inactive).
}
