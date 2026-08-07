import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Layout_Engine

@MainActor public final class LayoutDescriptor: ModuleDescriptor {
    public static let id = ModuleID("layout")
    public static let metadata = ModuleMetadata(
        id: id, name: LyStr.moduleName, summary: LyStr.summary,
        sfSymbol: "keyboard", permissions: [.accessibility],
        // Without the grant it watches nothing: 84 logged warnings of
        // `no accessibility grant — not watching` and no other way to work.
        inertWithout: [.accessibility])
    public static let category: ModuleCategory = .utilities
    public static let tint: ModuleTint = .keyboard

    private var store: NamespacedStore?
    private var indicator: LanguageIndicator?
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
        // Owned here, not by the host: it is this module's indicator, and it
        // goes away with the module.
        if let indicatorObserver { NotificationCenter.default.removeObserver(indicatorObserver) }
        self.indicator = nil
        let indicator = LanguageIndicator(store: store)
        self.indicator = indicator
        indicator.refresh()
        indicatorObserver = NotificationCenter.default.addObserver(
            forName: .helmStoreChanged, object: nil, queue: .main
        ) { [weak indicator] _ in
            MainActor.assumeIsolated { indicator?.refresh() }
        }
        return LayoutEngine(tap: CGKeyTap(),
                            typing: SynthesisTyping(),
                            sources: TISLayoutSources(),
                            translation: UCTranslation(),
                            spell: SystemSpell(),
                            secure: AXSecureContext(),
                            sound: SystemSound(),
                            selection: AXSelection(),
                            // Nothing about the stored settings is passed here.
                            // `activate()` reads all of them, and passing a
                            // second copy meant every default was written twice
                            // with nothing checking the two agreed — which is
                            // exactly the asymmetry that hid `tapKey` staying
                            // `.off` on every launch until 283c3cf. One reader.
                            settings: store)
    }

    /// Not a utility any more: it has a figure worth a glance — how many
    /// words it put right today — and that is the whole test for whether a
    /// module belongs in the panel rather than behind a disclosure in it.
    /// A row in the utilities list, not a tile.
    ///
    /// It had a widget for a while — the count of watched folders, the words
    /// put right today — and both are numbers without a question behind them:
    /// nobody opens a menu bar to find out how many folders are watched. A tile
    /// has to earn its 90 pt, and this one was earning it by existing.
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

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
