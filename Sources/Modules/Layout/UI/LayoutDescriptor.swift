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
        // Without the grant it watches nothing: 84 logged warnings of
        // `no accessibility grant — not watching` and no other way to work.
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
    /// `makeEngine` runs again on every enable — so turning Keyboard off and on
    /// left the previous indicator alive, retained by its own orphan observer
    /// and still owning a status item, while a second one was built. One more
    /// flag in the menu bar per toggle. `LayoutEngine.activate()` learned this
    /// twenty lines away; this was the other place that needed it.
    private var indicatorObserver: NSObjectProtocol?

    public init() {}

    public typealias Model = LayoutViewModel

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        productionEngine(store: store)
    }

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
                            // Nothing about the stored settings is passed here.
                            // `activate()` reads all of them, and passing a
                            // second copy meant every default was written twice
                            // with nothing checking the two agreed — which is
                            // exactly the asymmetry that hid `tapKey` staying
                            // `.off` on every launch until 283c3cf. One reader.
                            settings: store)
    }

    /// The module's own flag in the menu bar, built when the module starts
    /// running and taken away when it stops.
    ///
    /// **Not in `makeEngine`, which is where it used to be.** `refresh()` builds
    /// a real `NSStatusItem` the moment it reads the setting as on, so anybody
    /// who built an engine against a store with the indicator switched on
    /// decorated the Mac they were running on — including the offscreen render
    /// harness, whose whole discipline is that a measurement may read this Mac
    /// and may not change it. Writing the key straight into the backing store
    /// dodges `.helmStoreChanged` and does not dodge this: no notification is
    /// involved. Building an engine and appearing in the menu bar are two acts,
    /// and the host is what performs the second one.
    ///
    /// It also gave the module no way *off* the menu bar. `makeEngine` dropped
    /// the previous indicator and built another, so switching Keyboard off left
    /// the flag where it was — retained by its own observers, for the life of
    /// the process — and only switching it on again cleaned up. `detach` is the
    /// other half the old shape could not have.
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

    /// **The widget is back, and the reason it was taken away is answered
    /// rather than forgotten.** It went because it was «a number with no
    /// question behind it» — true then. Since today the count outlives a
    /// launch, it answers for a period rather than for one day, and the module
    /// has verbs that work from a panel.
    ///
    /// Still `.utility` as well: the row in the utilities list is what a person
    /// who has not added the tile sees, and it is where the module's switch
    /// lives.
    public func menuBar(_ model: LayoutViewModel) -> MenuBarContribution? {
        guard let store else { return .utility }
        return MenuBarContribution(panelTile: AnyView(
            LayoutWidgets.Wide(lvm: model,
                               period: Self.storedPeriod(store), onNever: { Self.never($0, store, model) })))
    }

    /// Three sizes, three questions: how many · how many and what to do · why
    /// that many and whether it goes on happening.
    public func panelWidget(_ size: PanelWidgetSize, _ model: LayoutViewModel) -> AnyView? {
        guard let store else { return nil }
        switch size {
        case .compact:
            return AnyView(LayoutWidgets.Compact(lvm: model, period: Self.storedPeriod(store)))
        case .wide:
            return AnyView(LayoutWidgets.Wide(lvm: model, period: Self.storedPeriod(store),
                                              onNever: { Self.never($0, store, model) }))
        case .tall:
            return AnyView(LayoutWidgets.Tall(lvm: model, store: store,
                                              onNever: { Self.never($0, store, model) },
                                              onAutomatic: { Self.automatic($0, store, model) }))
        }
    }

    /// The period the page was left on: the panel and the window answer the
    /// same question, so they must not answer it differently.
    private static func storedPeriod(_ store: NamespacedStore) -> ConversionPeriod {
        ConversionPeriod(rawValue: store.string(LayoutKey.heroPeriod, default: "")) ?? .today
    }

    /// Both verbs write where the settings page writes, and tell the engine —
    /// a list the engine never hears about is a list that does nothing.
    ///
    /// **That sentence stood over a verb that did only the first half.** The
    /// engine holds `exceptions` in a field and refills it in `reloadSettings`,
    /// which runs on `activate()` and on `settingsChanged` and nowhere else —
    /// there is no bridge turning a store write into that call. So this
    /// button wrote the list and the engine went on converting the word until
    /// some *other* setting was saved or the app was relaunched, which is the
    /// panel widget's own headline verb doing nothing.
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
    /// **Two steps, and the third one is not this file's to invent.** `enabled`
    /// on the state is whether the tap is live — the one running/not-running
    /// this module has — so it is `.active` or `.idle` and nothing else.
    /// «Switched on but not working» would be a third case, and `ModuleActivity`
    /// has two by design; a module cannot add one from the outside, and this is
    /// not the place to decide the app should have it. The page says that state
    /// in words where it can be acted on: an empty state for a missing grant, a
    /// note for the pause secure input causes. What that means for the badge is
    /// below — coarser than the page, never against it.
    public func activity(_ model: LayoutViewModel) -> ModuleActivity? {
        let state = model.state
        return Self.activity(enabled: state.enabled, suspended: state.suspended)
    }

    /// The rule itself.
    ///
    /// **The header may be coarser than the page. It may not say the
    /// opposite.** `suspended` was left out here, and the tap stays live
    /// through a pause — so with a password field in front the header drew a
    /// green «Active» pill 56 pt above the page's orange «Paused» one. Two
    /// marks about one module, in two signal colours, disagreeing on one
    /// screen. A pause reports as idle, and the page keeps the word for it.
    static func activity(enabled: Bool, suspended: Bool) -> ModuleActivity {
        enabled && !suspended ? .active : .idle
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
