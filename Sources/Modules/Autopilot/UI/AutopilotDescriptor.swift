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

    /// Not a utility any more: how many folders it watches and what it did
    /// today are figures worth a glance, which is the whole test for whether a
    /// module belongs in the panel rather than behind a disclosure in it.
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        MenuBarContribution(panelTile: AnyView(AutopilotWidget(vm: vm, size: .wide)))
    }

    /// All three. 1×1 is how many folders; 2×1 adds what happened today; 2×N
    /// says why that number is what it is, by naming the rules that fired.
    public func panelWidget(_ size: PanelWidgetSize, _ vm: ModuleViewModel) -> AnyView? {
        AnyView(AutopilotWidget(vm: vm, size: size))
    }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(AutopilotSettingsPage(vm: vm))
    }
}
