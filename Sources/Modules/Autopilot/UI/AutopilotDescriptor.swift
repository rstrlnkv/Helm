import HelmContract
import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

@MainActor public final class AutopilotDescriptor: ModuleDescriptor {
    public static let id = ModuleID("autopilot")
    public static let metadata = ModuleMetadata(
        id: id, name: ApStr.moduleName, summary: ApStr.summary,
        sfSymbol: "location.north.circle", permissions: [.fullDisk])
    public static let category: ModuleCategory = .files
    public static let tint: ModuleTint = .autopilot
    /// Folders and their rules span the pane; the header must not centre itself
    /// on the 744 pt form column.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        AutopilotEngine(store: store)
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(AutopilotSettingsPage(vm: vm))
    }
}
