import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine

@MainActor public final class DiskDescriptor: ModuleDescriptor {
    public static let id = ModuleID("disk")
    public static let metadata = ModuleMetadata(
        id: id, name: DkStr.moduleName, summary: DkStr.summary,
        sfSymbol: "chart.pie", permissions: [.fullDisk])
    public static let category: ModuleCategory = .files
    public static let tint: ModuleTint = .disk
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine { DiskEngine() }
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }
    public func settingsPage(_ vm: ModuleViewModel) -> AnyView { AnyView(DiskSettingsPage(vm: vm)) }
}

/// `DiskCommand`, where the host's tests can see it: the coordinator sends this
/// module's background scan and no compiler sees both sides of that name.
public typealias DiskCommand = Module_Disk_Engine.DiskCommand
