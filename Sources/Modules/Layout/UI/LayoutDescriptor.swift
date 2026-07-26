import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Layout_Engine

@MainActor public final class LayoutDescriptor: ModuleDescriptor {
    public static let id = ModuleID("layout")
    public static let metadata = ModuleMetadata(
        id: id, name: LyStr.moduleName, summary: LyStr.summary,
        sfSymbol: "keyboard", permissions: [.accessibility])
    public static let isolation: ModuleIsolation = .inProcess
    public static let category: ModuleCategory = .utilities

    private var store: NamespacedStore?
    private var indicator: LanguageIndicator?

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        self.store = store
        // Owned here, not by the host: it is this module's indicator, and it
        // goes away with the module.
        let indicator = LanguageIndicator(store: store)
        self.indicator = indicator
        indicator.refresh()
        NotificationCenter.default.addObserver(forName: .helmStoreChanged, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { indicator.refresh() }
        }
        return LayoutEngine(tap: CGKeyTap(),
                            typing: SynthesisTyping(),
                            sources: TISLayoutSources(),
                            translation: UCTranslation(),
                            spell: SystemSpell(),
                            secure: AXSecureContext(),
                            sound: SystemSound(),
                            rules: store.boolTable("appRules"),
                            exceptions: store.stringArray("exceptions"),
                            automatic: store.bool("automatic", default: true),
                            triggers: ConversionTriggers(
                                onSpace: store.bool("onSpace", default: ConversionTriggers.default.onSpace),
                                onReturn: store.bool("onReturn", default: ConversionTriggers.default.onReturn),
                                onPunctuation: store.bool("onPunctuation", default: ConversionTriggers.default.onPunctuation)),
                            audible: store.bool("audible", default: false),
                            settings: store)
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(LayoutSettingsPage(
            vm: vm,
            store: store ?? NamespacedStore(namespace: "layout", backing: UserDefaults.standard)))
    }
}
