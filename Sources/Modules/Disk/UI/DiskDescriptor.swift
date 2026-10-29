import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine

@MainActor public final class DiskDescriptor: ModuleDescriptor {
    public typealias Model = DiskViewModel

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

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine { DiskEngine(trashing: HelmTrash.moveToTrash) }

    /// The engine and the model that calls it, built together. Nothing is read
    /// here: the model's saved scan and its mount observers wait for the first
    /// draw (`DiskViewModel.appear()`).
    public func makeModule(store: NamespacedStore) -> ModuleParts<DiskViewModel> {
        let engine = DiskEngine(trashing: HelmTrash.moveToTrash)
        return ModuleParts(engine: engine, model: DiskViewModel(work: engine))
    }

    /// Closes the model; the host calls it before the engine's `deactivate()`, on
    /// the person's switch and on quit.
    public func stop(_ model: DiskViewModel) { model.stop() }

    /// Asked of the model, not of the engine through a cast or the wire: a model
    /// that is stopped answers nil, and a cast that missed would too, unseen.
    public func backgroundScan(_ parts: ModuleParts<DiskViewModel>) async -> ScanReport? {
        await parts.model.backgroundScan()
    }

    /// Not a utility any more. It has two figures worth a glance — how much
    /// room is left and out of how much — and both cost a volume-attributes
    /// read rather than a walk.
    public func menuBar(_ model: DiskViewModel) -> MenuBarContribution? {
        MenuBarContribution(panelTile: AnyView(DiskWidget(model: model, size: .wide)))
    }

    /// All three. 1×1 is what is free; 2×1 adds how much of the disk that is;
    /// 2×N lists the other volumes, because the space somebody is looking for
    /// is often on one of them.
    public func panelWidget(_ size: PanelWidgetSize, _ model: DiskViewModel) -> AnyView? {
        // 2×N is «why that number is that number», and on a Mac with one
        // volume there is no why — the tall card added a list of the other
        // volumes and there were none, so it was 2×1 with a taller frame.
        if size == .tall, model.volumes.count < 2 { return nil }
        return AnyView(DiskWidget(model: model, size: size))
    }
    public func settingsPage(_ model: DiskViewModel) -> AnyView { AnyView(DiskSettingsPage(dvm: model)) }
}
