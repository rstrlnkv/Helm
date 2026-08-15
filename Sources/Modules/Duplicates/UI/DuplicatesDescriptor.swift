import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import SwiftUI

@MainActor public final class DuplicatesDescriptor: ModuleDescriptor {
    public static let id = ModuleID(DuplicatesEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: DupStr.moduleName, summary: DupStr.summary,
        sfSymbol: "doc.on.doc", permissions: [.fullDisk]) }
    public static let category: ModuleCategory = .files
    public static let tint: ModuleTint = .duplicates
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    private var store: NamespacedStore?

    /// The store reaches the engine because a background scan reads the folder
    /// the person chose, and there is no view model awake when the timer fires.
    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        self.store = store
        return DuplicatesEngine(store: store)
    }
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }
    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(DuplicatesSettingsPage(vm: vm, store: settingsStore))
    }

    /// The module's own defaults, whether or not the engine has been built yet —
    /// the seam `VPNDescriptor` and `KeepAwakeDescriptor` already keep. The page
    /// building its own UserDefaults-backed store here meant the store the host
    /// handed `makeEngine` was read by the engine and by nobody else: the page
    /// and the engine could be opened on two different rule sets, and no harness
    /// could seed what the page reads.
    private var settingsStore: NamespacedStore {
        store ?? NamespacedStore(namespace: Self.id.rawValue, backing: UserDefaults.standard)
    }
}

/// The same, for the duplicate finder.
public typealias DuplicatesCommand = Module_Duplicates_Engine.DuplicatesCommand
