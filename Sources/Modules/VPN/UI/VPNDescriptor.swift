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
    public static let category: ModuleCategory = .network

    private var store: NamespacedStore?
    private var cached: (vm: ModuleViewModel, model: VPNViewModel)?
    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        self.store = store
        let ports = VPNSystemPorts()
        return VPNEngine(settings: VPNSettings(store: store),
                         runner: ports.runner, credentials: ports.credentials,
                         apps: ports.apps, network: ports.network)
    }

    /// One VPNViewModel per module: building a fresh one each call would leak a
    /// permanent transport-events subscriber every time the panel/settings open.
    ///
    /// Keyed to the host view model, the way `KeepAwakeViewModel.shared(vm:)`
    /// is. Without the identity check the cache survived a module restart —
    /// `ModuleHost.enable` builds a new engine and a new `ModuleViewModel`, and
    /// the old model went on talking to the dead engine's transport, whose
    /// handler is `[weak self]` and answers every command with empty `Data`.
    /// Switching VPN off and on left the tile and the page frozen until relaunch.
    func viewModel(_ hostVM: ModuleViewModel) -> VPNViewModel {
        if let cached, cached.vm === hostVM { return cached.model }
        let m = VPNViewModel(transport: hostVM.transport)
        cached = (hostVM, m)
        ModuleUICache.dropWhenDisabled(Self.id.rawValue) { [weak self] in self?.cached = nil }
        return m
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        MenuBarContribution(panelTile: AnyView(VPNPanelTile(vm: viewModel(vm))))
    }
    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        let store = self.store ?? NamespacedStore(namespace: Self.id.rawValue,
                                                  backing: UserDefaults.standard)
        return AnyView(VPNSettingsPage(vm: viewModel(vm), store: store))
    }
}
