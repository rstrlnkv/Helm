import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine

@MainActor public final class DiskDescriptor: ModuleDescriptor {
    public static let id = ModuleID(DiskEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: DkStr.moduleName, summary: DkStr.summary,
        sfSymbol: "chart.pie", permissions: [.fullDisk]) }
    public static let category: ModuleCategory = .files
    public static let tint = ModuleTint(
        ordinary: (light: (0.796, 0.208, 0.878), dark: (0.859, 0.227, 0.949)),
        increasedContrast: (light: (0.754, 0.197, 0.831), dark: (0.752, 0.199, 0.831)))
    public static let glyph = ShellGlyph(
        body: ShellGlyph.circle(12, 12, 8.5),
        detail: ShellGlyph.lines([[ShellGlyph.pt(12, 3.5), ShellGlyph.pt(12, 12), ShellGlyph.pt(19.2, 16.4)]]))
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine { DiskEngine() }
    /// Not a utility any more. It has two figures worth a glance — how much
    /// room is left and out of how much — and both cost a volume-attributes
    /// read rather than a walk.
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? {
        MenuBarContribution(panelTile: AnyView(DiskWidget(vm: vm, size: .wide)))
    }

    /// All three. 1×1 is what is free; 2×1 adds how much of the disk that is;
    /// 2×N lists the other volumes, because the space somebody is looking for
    /// is often on one of them.
    public func panelWidget(_ size: PanelWidgetSize, _ vm: ModuleViewModel) -> AnyView? {
        // 2×N is «why that number is that number», and on a Mac with one
        // volume there is no why — the tall card added a list of the other
        // volumes and there were none, so it was 2×1 with a taller frame.
        if size == .tall, DiskViewModel.shared(vm: vm).volumes.count < 2 { return nil }
        return AnyView(DiskWidget(vm: vm, size: size))
    }
    public func settingsPage(_ vm: ModuleViewModel) -> AnyView { AnyView(DiskSettingsPage(vm: vm)) }
}

/// `DiskCommand`, where the host's tests can see it: the coordinator sends this
/// module's background scan and no compiler sees both sides of that name.
public typealias DiskCommand = Module_Disk_Engine.DiskCommand
