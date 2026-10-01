import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

@MainActor public final class ScreenshotsDescriptor: ModuleDescriptor {
    public static let id = ModuleID(ScreenshotsEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: ScStr.moduleName, summary: ScStr.summary,
        sfSymbol: "camera.viewfinder", permissions: [.screenRecording],
        // Without the grant a freeze is a desktop with no windows in it, and the
        // module can do nothing at all.
        inertWithout: [.screenRecording]) }
    public static let category: ModuleCategory = .utilities
    public static let tint: ModuleTint = .screenshots

    private var store: NamespacedStore?

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        self.store = store
        return ScreenshotsEngine()
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(ScreenshotsSettingsPage(
            vm: vm,
            store: store ?? NamespacedStore(namespace: ScreenshotsDescriptor.id.rawValue,
                                            backing: UserDefaults.standard)))
    }
}

/// The shortcuts' names, where the host can see them — the host talks to a
/// module through its descriptor and never links its engine, and a hotkey wired
/// to a misspelt slot is a row that draws a shortcut pressing which does nothing.
public typealias ScreenshotsHotkey = Module_Screenshots_Engine.ScreenshotsHotkey
