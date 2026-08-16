import SwiftUI
import Combine
import HelmContract
import HelmRuntime
import HelmUI
import Module_VPN_Engine

@MainActor public final class VPNDescriptor: ModuleDescriptor {
    public static let id = ModuleID(VPNEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: "VPN", summary: VPNStr.summary,
        sfSymbol: "lock.shield", permissions: []) }
    public static let category: ModuleCategory = .network
    public static let tint: ModuleTint = .vpn

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
        // `SystemAutomationNotice` on its own rather than through
        // `VPNSystemPorts`: building the whole bundle here would also build
        // `KeychainCredentials`, whose init purges the old credential cache.
        // Its own init touches nothing, so this stays free in a test.
        let m = VPNViewModel(transport: hostVM.transport,
                             settings: VPNSettings(store: settingsStore),
                             notices: SystemAutomationNotice(area: VPNEngine.moduleID))
        cached = (hostVM, m)
        ModuleUICache.dropWhenDisabled(Self.id.rawValue) { [weak self] in self?.cached = nil }
        return m
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        MenuBarContribution(panelTile: AnyView(VPNPanelTile(vm: viewModel(vm))))
    }
    /// Three sizes. The middle one is the tile this module has always drawn;
    /// 1×1 is how many are up out of how many exist, and 2×N is the tile with
    /// every connection listed under it — which is the case that makes somebody
    /// open the panel at all: one of them is connected and it is not the one
    /// they expected.
    public func panelWidget(_ size: PanelWidgetSize, _ vm: ModuleViewModel) -> AnyView? {
        switch size {
        case .compact: return AnyView(VPNCompactWidget(vm: viewModel(vm)))
        case .wide: return AnyView(VPNPanelTile(vm: viewModel(vm)))
        // No 2×N. The 2×1 tile already lists every connection with a switch,
        // so the tall one printed the same list a second time underneath —
        // four VPNs came out as eight rows, four of them dead. The doc comment
        // that justified it described a tile this repo does not have.
        case .tall: return nil
        }
    }

    /// The badge in the page header, which is where the count used to be.
    ///
    /// A `HelmMetricStrip` sat above this page reading «2 connections · 1
    /// active · 3 automatic». Two of those three are facts the list underneath
    /// spells out a row at a time, and the third is a number nobody acts on;
    /// what a person wants from the top of this page is whether anything is up
    /// at all. That is one word, and the window already has a place for it.
    public func activity(_ vm: ModuleViewModel) -> ModuleActivity? {
        // `isConnected`, not `isUp`. `isUp` is «something is happening here»
        // and includes `.connecting`, so a tunnel three seconds into coming up
        // put a green «Active» in the header beside a card that said
        // «Connecting…». That exact defect was found and fixed once in the
        // metric strip this badge replaced — and came back with the badge,
        // because the question was copied and the answer was not.
        viewModel(vm).connections.contains { $0.status.isConnected } ? .active : .idle
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
    ///
    /// The spin's colour is `spinTintToken`, which `StatusPlan.choose` does not
    /// read — so colouring the animation does not make this a tinting module.
    public func statusAppearance(_ vm: ModuleViewModel) -> StatusAppearance {
        let model = viewModel(vm)
        guard let firing = model.lastAutomation else { return .inactive }
        // One reading of the clock, so the two windows cannot disagree about
        // which moment they are answering for.
        let now = Date()
        // The setting decides whether there is movement at all. Reduce Motion
        // is a separate question, answered a level up in `StatusPlan.spins`:
        // this is a preference, that is an instruction from the system.
        let spinning = model.automationSpin
            && VPNAutomation.spinPhase(firing, now: now) != nil
        let names = model.effectiveNotice(for: firing.kind).showsMenuBarName
            && VPNAutomation.showsName(firing, now: now)
        // Bounded here, because this is where the unbounded string is: the name
        // comes out of a configuration somebody else wrote, and the host draws
        // whatever a descriptor hands it. The rule is `StatusPlan`'s, next to the
        // rest of what the host knows about its own menu bar.
        return StatusAppearance(title: names ? StatusPlan.menuBarTitle(firing.name) : nil,
                                spinUntil: spinning ? VPNAutomation.spinEnd(firing) : nil,
                                spinTintToken: spinning ? model.spinTint(for: firing.kind) : nil)
    }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(VPNSettingsPage(vm: viewModel(vm), store: settingsStore))
    }

    /// The module's own defaults, whether or not the engine has been built yet.
    private var settingsStore: NamespacedStore {
        store ?? NamespacedStore(namespace: Self.id.rawValue, backing: UserDefaults.standard)
    }
}
