import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import SwiftUI

@MainActor public final class DuplicatesDescriptor: ModuleDescriptor {
    public static let id = ModuleID(DuplicatesEngine.moduleID)
    public static let metadata = ModuleMetadata(
        id: id, name: DupStr.moduleName, summary: DupStr.summary,
        sfSymbol: "doc.on.doc", permissions: [.fullDisk])
    public static let category: ModuleCategory = .files
    public static let tint: ModuleTint = .duplicates
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    /// The store reaches the engine because a background scan reads the folder
    /// the person chose, and there is no view model awake when the timer fires.
    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        DuplicatesEngine(store: store)
    }
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }
    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(DuplicatesSettingsPage(
            vm: vm, store: NamespacedStore(namespace: DuplicatesDescriptor.id.rawValue,
                                           backing: UserDefaults.standard)))
    }
}

/// The same, for the duplicate finder.
public typealias DuplicatesCommand = Module_Duplicates_Engine.DuplicatesCommand
