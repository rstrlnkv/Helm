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

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        self.store = store
        return LayoutEngine(tap: CGKeyTap(),
                            typing: SynthesisTyping(),
                            sources: TISLayoutSources(),
                            translation: UCTranslation(),
                            spell: SystemSpell(),
                            secure: AXSecureContext(),
                            rules: store.boolTable("appRules"),
                            exceptions: store.stringArray("exceptions"),
                            automatic: store.bool("automatic", default: true),
                            triggers: ConversionTriggers(
                                onSpace: store.bool("onSpace", default: true),
                                onReturn: store.bool("onReturn", default: true),
                                onPunctuation: store.bool("onPunctuation", default: true)),
                            settings: store)
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(LayoutSettingsPage(
            vm: vm,
            store: store ?? NamespacedStore(namespace: "layout", backing: UserDefaults.standard)))
    }
}
