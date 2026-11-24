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
    public static let tint = ModuleTint(
        ordinary: (light: (0.380, 0.333, 0.961), dark: (0.427, 0.486, 1.000)),
        increasedContrast: (light: (0.380, 0.333, 0.961), dark: (0.371, 0.422, 0.869)))
    public static let glyph = ShellGlyph(
        body: {
            var shield = Path()
            shield.move(to: ShellGlyph.pt(12, 3.5))
            shield.addLine(to: ShellGlyph.pt(18.5, 6))
            shield.addQuadCurve(to: ShellGlyph.pt(19.5, 7.5), control: ShellGlyph.pt(19.5, 6.4))
            shield.addLine(to: ShellGlyph.pt(19.5, 11.5))
            shield.addCurve(to: ShellGlyph.pt(12, 20.8), control1: ShellGlyph.pt(19.5, 16), control2: ShellGlyph.pt(16.5, 19))
            shield.addCurve(to: ShellGlyph.pt(4.5, 11.5), control1: ShellGlyph.pt(7.5, 19), control2: ShellGlyph.pt(4.5, 16))
            shield.addLine(to: ShellGlyph.pt(4.5, 7.5))
            shield.addQuadCurve(to: ShellGlyph.pt(5.5, 6), control: ShellGlyph.pt(4.5, 6.4))
            shield.closeSubpath()
            return shield
        }())

    private var store: NamespacedStore?
    public init() {}

    public typealias Model = VPNViewModel

    public func makeModule(store: NamespacedStore) -> ModuleParts<VPNViewModel> {
        let engine = productionEngine(store: store)
        // The engine is built here and never activated: `VPNSystemPorts`
        // builds `KeychainCredentials`, whose init purges the credential cache
        // only when `AppBuild.isBundledApp`, so a test that builds the module
        // reaches neither the keychain nor a tunnel.
        let model = VPNViewModel(work: engine, settings: VPNSettings(store: store),
                                 notices: SystemAutomationNotice(area: VPNEngine.moduleID))
        return ModuleParts(engine: engine, model: model)
    }

    /// The host closes the model before the engine goes: its stream task ends
    /// and nothing it was asked after that reaches the engine.
    public func stop(_ model: VPNViewModel) { model.stop() }

    private func productionEngine(store: NamespacedStore) -> VPNEngine {
        self.store = store
        let ports = VPNSystemPorts()
        // Every port named, none taken from a default, so the app's wiring
        // shows what this module talks to; three reach the network or run a
        // tool for twenty seconds (`NetworkQualitySpeed.typicalRun`).
        return VPNEngine(settings: VPNSettings(store: store),
                         runner: ports.runner, credentials: ports.credentials,
                         apps: ports.apps, network: ports.network,
                         interfaces: ports.interfaces, exit: ports.exit,
                         speed: ports.speed)
    }

    public func menuBar(_ model: VPNViewModel) -> MenuBarContribution? {
        MenuBarContribution(panelTile: AnyView(VPNPanelTile(vm: model)))
    }
    /// Two sizes: 1×1 is how many are up out of how many exist, 2×1 is every
    /// connection with its switch.
    public func panelWidget(_ size: PanelWidgetSize, _ model: VPNViewModel) -> AnyView? {
        switch size {
        case .compact: return AnyView(VPNCompactWidget(vm: model))
        case .wide: return AnyView(VPNPanelTile(vm: model))
        // No 2×N: the 2×1 tile already lists every connection with a switch,
        // so a tall one would print the same list a second time underneath.
        case .tall: return nil
        }
    }

    /// The badge in the page header: whether anything is up at all.
    public func activity(_ model: VPNViewModel) -> ModuleActivity? {
        // `isConnected`, not `isUp`, which includes `.connecting`: a green
        // «Active» beside a card saying «Connecting…» would be wrong.
        model.connections.contains { $0.status.isConnected } ? .active : .idle
    }

    /// Without this the host reads `statusAppearance` only when something else
    /// redraws the icon, and a rule firing by itself is the case where nothing
    /// else does.
    public func statusChanges(_ model: VPNViewModel) -> AnyPublisher<Void, Never>? {
        model.objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// Only while a rule's firing is still news.
    ///
    /// No tint, ever: a tint is a permanent menu-bar presence, since
    /// `StatusPlan.choose` falls back to the first module that tints, and it
    /// would settle "whose icon is this" by module order. The spin's colour is
    /// `spinTintToken`, which `StatusPlan.choose` does not read.
    public func statusAppearance(_ model: VPNViewModel) -> StatusAppearance {
        guard let firing = model.lastAutomation else { return .inactive }
        // One reading of the clock, so the two windows answer for one moment.
        let now = Date()
        // The setting decides whether there is movement at all; Reduce Motion
        // is answered a level up in `StatusPlan.spins`. All three are asked
        // *on the configuration that fired*: the settings live on the card.
        let spinning = model.automationSpin(on: firing.name)
            && VPNAutomation.spinPhase(firing, now: now) != nil
        let names = model.effectiveNotice(for: firing.kind, on: firing.name).showsMenuBarName
            && VPNAutomation.showsName(firing, now: now)
        // Bounded here, where the unbounded string is: the name comes from a
        // configuration somebody else wrote (`StatusPlan.menuBarTitle`).
        return StatusAppearance(title: names ? StatusPlan.menuBarTitle(firing.name) : nil,
                                spinUntil: spinning ? VPNAutomation.spinEnd(firing) : nil,
                                spinTintToken: spinning
                                    ? model.spinTint(for: firing.kind, on: firing.name) : nil)
    }

    public func settingsPage(_ model: VPNViewModel) -> AnyView {
        AnyView(VPNSettingsPage(vm: model, store: settingsStore))
    }

    /// The module's own defaults, whether or not the engine has been built yet.
    private var settingsStore: NamespacedStore {
        store ?? NamespacedStore(namespace: Self.id.rawValue, backing: UserDefaults.standard)
    }
}
