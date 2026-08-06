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
        // Same rule as Disk's: 2×N lists the rules that fired today, and on a
        // day nothing fired — which is most days — it is 2×1 with a taller
        // frame. A stored `tall` clamps down rather than vanishing.
        if size == .tall, !AutopilotDescriptor.firedToday(vm) { return nil }
        return AnyView(AutopilotWidget(vm: vm, size: size))
    }

    /// Whether anything happened today, without building a view to find out.
    @MainActor static func firedToday(_ vm: ModuleViewModel) -> Bool {
        let start = Calendar.current.startOfDay(for: Date())
        return AutopilotViewModel.shared(vm: vm).history.contains { $0.at >= start }
    }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(AutopilotSettingsPage(vm: vm))
    }
}
