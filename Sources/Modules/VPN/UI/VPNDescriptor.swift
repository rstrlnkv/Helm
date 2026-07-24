import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_VPN_Engine

@MainActor public final class VPNDescriptor: ModuleDescriptor {
    public static let id = ModuleID("vpn")
    public static let metadata = ModuleMetadata(
        id: id, name: "VPN", summary: VPNStr.summary,
        sfSymbol: "lock.shield", permissions: [])
    public static let isolation: ModuleIsolation = .inProcess
    public static let category: ModuleCategory = .network

    private var store: NamespacedStore?
    private var cachedVM: VPNViewModel?
    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        self.store = store
        let ports = VPNSystemPorts()
        return VPNEngine(settings: VPNSettings(store: store),
                         runner: ports.runner, credentials: ports.credentials, apps: ports.apps)
    }

    /// One VPNViewModel per module: building a fresh one each call would leak a
    /// permanent transport-events subscriber every time the panel/settings open.
    private func viewModel(_ hostVM: ModuleViewModel) -> VPNViewModel {
        if let cachedVM { return cachedVM }
        let m = VPNViewModel(transport: hostVM.transport)
        cachedVM = m
        return m
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        MenuBarContribution(panelTile: AnyView(VPNPanelTile(vm: viewModel(vm))))
    }
    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        let store = self.store ?? NamespacedStore(namespace: "vpn", backing: UserDefaults.standard)
        return AnyView(VPNSettingsPage(vm: viewModel(vm), store: store))
    }
}
