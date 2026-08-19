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

    /// A tile that says what it knows and carries no control.
    ///
    /// Editing a hosts file is a page, not a toggle: a switch here would raise a
    /// macOS password dialog from the menu bar, and a password dialog needs a
    /// gesture that asked for it. The tile waited for this plan because two of
    /// the three things it summarises — the keys and the agent — did not exist
    /// until now.
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        MenuBarContribution(panelTile: AnyView(HostsPanelTile(hvm: HostsViewModel.shared(vm: vm))))
    }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(HostsSettingsPage(vm: vm))
    }
}
