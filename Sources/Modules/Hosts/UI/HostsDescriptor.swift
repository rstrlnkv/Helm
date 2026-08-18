import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Hosts_Engine

@MainActor public final class HostsDescriptor: ModuleDescriptor {
    public static let id = ModuleID(HostsEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: HostsStr.moduleName, shortName: HostsStr.moduleNameShort,
        summary: HostsStr.summary,
        sfSymbol: "network", permissions: []) }
    public static let category: ModuleCategory = .utilities
    public static let tint: ModuleTint = .hosts

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        HostsEngine()
    }

    /// Nothing to act on from the menu bar: editing a hosts file is a page, not
    /// a toggle. The panel tile waits for plan 3, where two of the three things
    /// it would summarise start existing.
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(HostsSettingsPage(vm: vm))
    }
}
