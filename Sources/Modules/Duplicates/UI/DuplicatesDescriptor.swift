import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import SwiftUI

@MainActor public final class DuplicatesDescriptor: ModuleDescriptor {
    public static let id = ModuleID("duplicates")
    public static let metadata = ModuleMetadata(
        id: id, name: DupStr.moduleName, summary: DupStr.summary,
        sfSymbol: "doc.on.doc", permissions: [.fullDisk])
    public static let category: ModuleCategory = .files
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine { DuplicatesEngine() }
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }
    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(DuplicatesSettingsPage(
            vm: vm, store: NamespacedStore(namespace: DuplicatesDescriptor.id.rawValue,
                                           backing: UserDefaults.standard)))
    }
}
