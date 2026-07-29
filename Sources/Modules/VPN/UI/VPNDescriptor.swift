import SwiftUI
import Combine
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
        let m = VPNViewModel(transport: hostVM.transport,
                             settings: VPNSettings(store: settingsStore))
        cached = (hostVM, m)
        ModuleUICache.dropWhenDisabled(Self.id.rawValue) { [weak self] in self?.cached = nil }
        return m
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        MenuBarContribution(panelTile: AnyView(VPNPanelTile(vm: viewModel(vm))))
    }
    /// Without this the host reads `statusAppearance` only when something else
    /// redraws the icon, and a rule firing by itself is precisely the case
    /// where nothing else does.
    public func statusChanges(_ vm: ModuleViewModel) -> AnyPublisher<Void, Never>? {
        viewModel(vm).objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// Only while a rule's firing is still news.
    ///
    /// No tint, ever: this module has no presence in the menu bar between
    /// firings, and giving it a permanent one — which is what a tint is, since
    /// `StatusPlan.choose` falls back to the first module that tints — is a
    /// larger change than saying that a rule fired. It would also settle
    /// "whose icon is this" by `ModuleOrder`, which `StatusItemController`
    /// notes is latent today precisely because no second module tints.
    public func statusAppearance(_ vm: ModuleViewModel) -> StatusAppearance {
        let model = viewModel(vm)
        guard let firing = model.lastAutomation else { return .inactive }
        // One reading of the clock, so the two windows cannot disagree about
        // which moment they are answering for.
        let now = Date()
        let spinning = VPNAutomation.spinPhase(firing, now: now) != nil
        // `effectiveNotice`, never the raw one: `.system` is the mode that shows
        // no name because the banner carries it, so asking the raw choice left a
        // person who had refused the banner permission with no banner AND no
        // name — the loudest setting produced the least.
        let names = model.effectiveNotice.showsMenuBarName
            && VPNAutomation.showsName(firing, now: now)
        return StatusAppearance(title: names ? firing.name : nil,
                                spinUntil: spinning ? VPNAutomation.spinEnd(firing) : nil)
    }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(VPNSettingsPage(vm: viewModel(vm), store: settingsStore))
    }

    /// The module's own defaults, whether or not the engine has been built yet.
    private var settingsStore: NamespacedStore {
        store ?? NamespacedStore(namespace: Self.id.rawValue, backing: UserDefaults.standard)
    }
}
