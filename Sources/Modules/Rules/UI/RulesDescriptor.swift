import HelmContract
import HelmRuntime
import HelmUI
import Module_Rules_Engine
import SwiftUI

@MainActor public final class RulesDescriptor: ModuleDescriptor {
    public static let id = ModuleID("rules")
    public static let metadata = ModuleMetadata(
        id: id, name: RuStr.moduleName, summary: RuStr.summary,
        sfSymbol: "folder.badge.gearshape", permissions: [.fullDisk])
    public static let isolation: ModuleIsolation = .inProcess
    public static let category: ModuleCategory = .files
    /// Folders and their rules span the pane; the header must not centre itself
    /// on the 744 pt form column.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        RulesEngine(store: store)
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(RulesSettingsPage(vm: vm))
    }
}
