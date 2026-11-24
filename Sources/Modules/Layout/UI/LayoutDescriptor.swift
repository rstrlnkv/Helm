import SwiftUI
import Combine
import HelmContract
import HelmRuntime
import HelmUI
import Module_Layout_Engine

@MainActor public final class LayoutDescriptor: ModuleDescriptor {
    public static let id = ModuleID(LayoutEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: LyStr.moduleName, summary: LyStr.summary,
        sfSymbol: "keyboard", permissions: [.accessibility],
        // Without the grant it watches nothing and has no other way to work.
        inertWithout: [.accessibility]) }
    public static let category: ModuleCategory = .utilities
    public static let tint = ModuleTint(
        ordinary: (light: (0.850, 0.150, 0.650), dark: (0.850, 0.150, 0.650)),
        increasedContrast: (light: (0.838, 0.148, 0.641), dark: (0.838, 0.148, 0.641)))
    public static let glyph = ShellGlyph(
        body: ShellGlyph.box(2.5, 6, 19, 12, 3.5),
        detail: ShellGlyph.lines([ShellGlyph.dot(7.5, 10.3), ShellGlyph.dot(12, 10.3), ShellGlyph.dot(16.5, 10.3),
                                  [ShellGlyph.pt(9, 13.9), ShellGlyph.pt(15, 13.9)]]))

    private var store: NamespacedStore?
    /// Readable so a test can tell «attached» from «not attached» without the
    /// indicator having to build a status item to be seen.
    private(set) var indicator: LanguageIndicator?
    /// Kept so it can be dropped. A block observer does not remove itself, and
    /// this descriptor is one long-lived instance in `ModuleRegistry.all` whose
    /// `makeModule` runs again on every enable: an indicator not dropped stays
    /// alive, retained by its own observer and owning a status item, and each
    /// toggle adds one more flag to the menu bar.
    private var indicatorObserver: NSObjectProtocol?

    public init() {}

    public typealias Model = LayoutViewModel

    public func makeModule(store: NamespacedStore) -> ModuleParts<LayoutViewModel> {
        let engine = productionEngine(store: store)
        return ModuleParts(engine: engine, model: LayoutViewModel(work: engine))
    }

    /// The host closes the model before the engine goes: its stream task ends
    /// and a late press reaches nothing.
    public func stop(_ model: LayoutViewModel) { model.stop() }

    private func productionEngine(store: NamespacedStore) -> LayoutEngine {
        self.store = store
        return LayoutEngine(tap: CGKeyTap(),
                            typing: SynthesisTyping(),
                            sources: TISLayoutSources(),
                            translation: UCTranslation(),
                            spell: SystemSpell(),
                            secure: AXSecureContext(),
                            activation: AppActivation(),
                            sound: SystemSound(),
                            announcer: LayoutAnnouncer(store: store),
                            selection: AXSelection(),
                            // Nothing about the stored settings is passed here:
                            // `activate()` reads all of them, and a second copy
                            // would write every default twice with nothing
                            // checking the two agree. One reader.
                            settings: store)
    }

    /// The module's own flag in the menu bar, built when the module starts
    /// running and taken away when it stops.
    ///
    /// Not in `makeModule`: `refresh()` builds a real `NSStatusItem` the moment
    /// it reads the setting as on, so anybody who built an engine against a
    /// store with the indicator on (the offscreen render harness included, which
    /// may read this Mac and may not change it) would decorate the Mac they run
    /// on. Building an engine and appearing in the menu bar are two acts, and
    /// the host performs the second.
    ///
    /// There it would also give the module no way off the menu bar: switching
    /// Keyboard off would leave the flag, retained by its own observers, until
    /// it was switched on again. `detach` is the other half.
    public func attachMenuBarPresence() {
        guard let store else { return }
        detachMenuBarPresence()
        let indicator = LanguageIndicator(store: store)
        self.indicator = indicator
        indicator.refresh()
        indicatorObserver = NotificationCenter.default.addObserver(
            forName: .helmStoreChanged, object: nil, queue: .main
        ) { [weak indicator] _ in
            MainActor.assumeIsolated { indicator?.refresh() }
        }
    }

    public func detachMenuBarPresence() {
        if let indicatorObserver { NotificationCenter.default.removeObserver(indicatorObserver) }
        indicatorObserver = nil
        indicator?.detach()
        indicator = nil
    }

    /// A widget, because the count outlives a launch and answers for a period,
    /// and the module has verbs that work from a panel.
    ///
    /// With a store the contribution is the tile and not `.utility`; `.utility`,
    /// the compact row behind the panel's disclosure, is what comes back only
    /// while there is no store.
    public func menuBar(_ model: LayoutViewModel) -> MenuBarContribution? {
        guard let store else { return .utility }
        return MenuBarContribution(panelTile: AnyView(
            LayoutWidgets.Fixed(lvm: model, size: .wide,
                                period: ConversionPeriod.stored(in: store), onNever: { Self.never($0, store, model) })))
    }

    /// Three sizes, three questions: how many · how many and what to do · why
    /// that many and whether it goes on happening.
    public func panelWidget(_ size: PanelWidgetSize, _ model: LayoutViewModel) -> AnyView? {
        guard let store else { return nil }
        switch size {
        case .compact:
            return AnyView(LayoutWidgets.Fixed(lvm: model, size: .compact, period: ConversionPeriod.stored(in: store)))
        case .wide:
            return AnyView(LayoutWidgets.Fixed(lvm: model, size: .wide, period: ConversionPeriod.stored(in: store),
                                               onNever: { Self.never($0, store, model) }))
        case .tall:
            return AnyView(LayoutWidgets.Tall(lvm: model, store: store,
                                              onNever: { Self.never($0, store, model) },
                                              onAutomatic: { Self.automatic($0, store, model) }))
        }
    }

    /// Both verbs write where the settings page writes, and tell the engine:
    /// it holds `exceptions` in a field refilled by `reloadSettings`, which runs
    /// on `activate()` and `settingsChanged` and nowhere else. No bridge turns a
    /// store write into that call, so a write alone would leave the engine
    /// converting the word.
    private static func never(_ word: String, _ store: NamespacedStore, _ model: LayoutViewModel) {
        guard let words = Exceptions.adding(word, to: store.stringArray(LayoutKey.exceptions))
        else { return }
        store.set(words, for: LayoutKey.exceptions)
        model.settingsChanged()
    }

    private static func automatic(_ on: Bool, _ store: NamespacedStore, _ model: LayoutViewModel) {
        store.set(on, for: LayoutKey.automatic)
        model.settingsChanged()
    }

    /// The badge beside the module's name in the page header.
    ///
    /// Two steps: `enabled` on the state is whether the tap is live, so it is
    /// `.active` or `.idle`. «Switched on but not working» would be a third
    /// case, and `ModuleActivity` has two by design. The page says that state in
    /// words where it can be acted on: an empty state for a missing grant, a
    /// note for the pause secure input causes.
    ///
    /// The header may be coarser than the page; it may not say the opposite.
    /// The tap stays live through a secure-input pause, so `suspended` reports
    /// as idle here rather than a green «Active» above the page's «Paused».
    public func activity(_ model: LayoutViewModel) -> ModuleActivity? {
        let state = model.state
        return state.enabled && !state.suspended ? .active : .idle
    }

    /// Without this the header reads the badge once and never again: the tap
    /// going live, or macOS taking it away, is exactly the case where nothing
    /// else on screen redraws.
    public func statusChanges(_ model: LayoutViewModel) -> AnyPublisher<Void, Never>? {
        model.objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    public static var hotkeys: [ModuleHotkey] {
        [ModuleHotkey(slot: LayoutHotkey.fix, prefix: LayoutHotkey.storePrefix)]
    }

    public func hotkeyPressed(_ hotkey: ModuleHotkey, _ model: LayoutViewModel) {
        model.fix()
    }

    public func settingsPage(_ model: LayoutViewModel) -> AnyView {
        AnyView(LayoutSettingsPage(
            lvm: model,
            store: store ?? NamespacedStore(namespace: LayoutDescriptor.id.rawValue, backing: UserDefaults.standard)))
    }
}
