import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Leftovers_Engine

@MainActor public final class LeftoversDescriptor: ModuleDescriptor {
    public static let id = ModuleID("leftovers")
    public static let metadata = ModuleMetadata(
        id: id, name: LfStr.moduleName, summary: LfStr.summary,
        sfSymbol: "wand.and.rays", permissions: [])
    public static let isolation: ModuleIsolation = .inProcess
    public static let category: ModuleCategory = .utilities

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine { LeftoversEngine() }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(LeftoversSettingsPage(vm: vm))
    }
}
