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
    public static let tint: ModuleTint = .keyboard

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

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        self.store = store
        return LayoutEngine(tap: CGKeyTap(),
                            typing: SynthesisTyping(),
                            sources: TISLayoutSources(),
                            translation: UCTranslation(),
                            spell: SystemSpell(),
                            secure: AXSecureContext(),
                            sound: SystemSound(),
                            announcer: LayoutAnnouncer(store: store),
                            selection: AXSelection(),
                            // Nothing about the stored settings is passed here.
                            // `activate()` reads all of them, and passing a
                            // second copy meant every default was written twice
                            // with nothing checking the two agreed — which is
                            // exactly the asymmetry that hid `tapKey` staying
                            // `.off` on every launch until 283c3cf. One reader.
                            settings: store,
                            // The one construction that gets the real keychain,
                            // and it is the app's. Read lazily and off the
                            // launch path — `VocabularyStore.warm`.
                            vocabulary: VocabularyStore(keys: LayoutEngine.saltKeychain))
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
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        guard let store else { return .utility }
        return MenuBarContribution(panelTile: AnyView(
            LayoutWidgets.Wide(lvm: LayoutViewModel.shared(vm: vm), store: store,
                               period: Self.storedPeriod(store), onNever: { Self.never($0, store) })))
    }

    /// Three sizes, three questions: how many · how many and what to do · why
    /// that many and whether it goes on happening.
    public func panelWidget(_ size: PanelWidgetSize, _ vm: ModuleViewModel) -> AnyView? {
        guard let store else { return nil }
        let lvm = LayoutViewModel.shared(vm: vm)
        switch size {
        case .compact:
            return AnyView(LayoutWidgets.Compact(lvm: lvm, period: Self.storedPeriod(store)))
        case .wide:
            return AnyView(LayoutWidgets.Wide(lvm: lvm, store: store,
                                              period: Self.storedPeriod(store),
                                              onNever: { Self.never($0, store) }))
        case .tall:
            return AnyView(LayoutTallWidget(lvm: lvm, store: store,
                                            onNever: { Self.never($0, store) },
                                            onAutomatic: { Self.automatic($0, store, vm) }))
        }
    }

    /// The period the page was left on: the panel and the window answer the
    /// same question, so they must not answer it differently.
    private static func storedPeriod(_ store: NamespacedStore) -> ConversionPeriod {
        ConversionPeriod(rawValue: store.string(LayoutKey.heroPeriod, default: "")) ?? .today
    }

    /// Both verbs write where the settings page writes, and tell the engine —
    /// a list the engine never hears about is a list that does nothing.
    private static func never(_ word: String, _ store: NamespacedStore) {
        var words = store.stringArray(LayoutKey.exceptions)
        let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty, !words.contains(where: { $0.lowercased() == cleaned })
        else { return }
        words.append(cleaned)
        store.set(words, for: LayoutKey.exceptions)
    }

    private static func automatic(_ on: Bool, _ store: NamespacedStore, _ vm: ModuleViewModel) {
        store.set(on, for: LayoutKey.automatic)
        vm.send(LayoutCommand.settingsChanged)
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
    public func activity(_ vm: ModuleViewModel) -> ModuleActivity? {
        let state = LayoutViewModel.shared(vm: vm).state
        return Self.activity(enabled: state.enabled, suspended: state.suspended)
    }

    /// The rule itself, pure so a test can reach it: the method above needs a
    /// `ModuleViewModel`, which needs a transport and an engine, and none of
    /// that is the subject.
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

    /// Which figure the hero is showing, beside the module's name — see
    /// `LayoutHeaderMetric` for why it is here rather than in the hero's own
    /// row of buttons.
    public func headerAccessory(_ vm: ModuleViewModel) -> AnyView? {
        guard let store else { return nil }
        return AnyView(LayoutHeaderMetric(store: store))
    }

    /// Without this the header reads the badge once and never again: the tap
    /// going live, or macOS taking it away, is exactly the case where nothing
    /// else on screen redraws.
    public func statusChanges(_ vm: ModuleViewModel) -> AnyPublisher<Void, Never>? {
        LayoutViewModel.shared(vm: vm).objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(LayoutSettingsPage(
            vm: vm,
            store: store ?? NamespacedStore(namespace: LayoutDescriptor.id.rawValue, backing: UserDefaults.standard)))
    }
}

/// LayoutCommand, where the host can see it.
///
/// The host talks to a module through its descriptor and the transport, and
/// never links its engine — a direct edge there is a door past the transport.
/// But the two global shortcuts it registers send the keyboard module's commands, and a
/// hotkey wired to a misspelt name is silence with no symptom at all. The name
/// is re-exported here rather than retyped there.
public typealias LayoutCommand = Module_Layout_Engine.LayoutCommand

/// The chord's two names, where the host can see them — the same reason and the
/// same direction as `LayoutCommand` above.
public typealias LayoutHotkey = Module_Layout_Engine.LayoutHotkey
