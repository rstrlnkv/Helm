import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Leftovers_Engine

@MainActor public final class LeftoversDescriptor: ModuleDescriptor {
    public static let id = ModuleID(LeftoversEngine.moduleID)
    public static let metadata = ModuleMetadata(
        id: id, name: LfStr.moduleName, shortName: LfStr.moduleNameShort,
        summary: LfStr.summary,
        sfSymbol: "wand.and.rays", permissions: [.fullDisk])
    public static let category: ModuleCategory = .utilities
    public static let tint: ModuleTint = .leftovers
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine { LeftoversEngine() }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(LeftoversSettingsPage(vm: vm))
    }
}
