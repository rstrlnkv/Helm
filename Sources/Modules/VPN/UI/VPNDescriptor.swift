import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_VPN_Engine

@MainActor public final class VPNDescriptor: ModuleDescriptor {
    public static let id = ModuleID("vpn")
    public static let metadata = ModuleMetadata(
        id: id, name: "VPN", summary: "Connect system VPNs, automatically per app.",
        sfSymbol: "lock.shield", permissions: [])
    public static let isolation: ModuleIsolation = .inProcess
    public static let category: ModuleCategory = .network

    private var store: NamespacedStore?
    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        self.store = store
        let ports = VPNSystemPorts()
        return VPNEngine(settings: VPNSettings(store: store),
                         runner: ports.runner, credentials: ports.credentials, apps: ports.apps)
    }
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        MenuBarContribution(panelTile: AnyView(VPNPanelTile(vm: VPNViewModel(transport: vm.transport))))
    }
    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        let store = self.store ?? NamespacedStore(namespace: "vpn", backing: UserDefaults.standard)
        return AnyView(VPNSettingsPage(vm: VPNViewModel(transport: vm.transport), store: store))
    }
}
