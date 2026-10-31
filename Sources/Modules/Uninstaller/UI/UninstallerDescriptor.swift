import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

@MainActor public final class UninstallerDescriptor: ModuleDescriptor {
    public typealias Model = UninstallerViewModel

    public static let id = ModuleID(UninstallerEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: UnStr.moduleName, summary: UnStr.summary,
        sfSymbol: "trash", permissions: [.fullDisk]) }
    public static let category: ModuleCategory = .files
    public static let tint = ModuleTint(
        ordinary: (light: (1.000, 0.220, 0.235), dark: (1.000, 0.259, 0.271)),
        increasedContrast: (light: (0.878, 0.193, 0.206), dark: (0.859, 0.222, 0.233)))
    public static let glyph = ShellGlyph(
        body: {
            var bin = Path()
            bin.move(to: ShellGlyph.pt(6.2, 8))
            bin.addLine(to: ShellGlyph.pt(7, 18.3))
            bin.addQuadCurve(to: ShellGlyph.pt(9.4, 20.5), control: ShellGlyph.pt(7.2, 20.5))
            bin.addLine(to: ShellGlyph.pt(14.6, 20.5))
            bin.addQuadCurve(to: ShellGlyph.pt(17, 18.3), control: ShellGlyph.pt(16.8, 20.5))
            bin.addLine(to: ShellGlyph.pt(17.8, 8))
            bin.closeSubpath()
            return bin
        }(),
        extra: {
            var lid = ShellGlyph.lines([[ShellGlyph.pt(4, 8), ShellGlyph.pt(20, 8)]])
            lid.move(to: ShellGlyph.pt(9.5, 8))
            lid.addLine(to: ShellGlyph.pt(9.5, 6))
            lid.addQuadCurve(to: ShellGlyph.pt(11, 4.5), control: ShellGlyph.pt(9.5, 4.5))
            lid.addLine(to: ShellGlyph.pt(13, 4.5))
            lid.addQuadCurve(to: ShellGlyph.pt(14.5, 6), control: ShellGlyph.pt(14.5, 4.5))
            lid.addLine(to: ShellGlyph.pt(14.5, 8))
            return lid
        }())
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    /// The one place the production engine is built; `makeModule` needs it as
    /// the concrete type the model calls.
    private func productionEngine(store: NamespacedStore,
                                  trashChanged: @escaping @Sendable () -> Void) -> UninstallerEngine {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let ports = UninstallerSystemPorts(home: home)
        // The store the host hands every module was unused here until the Trash
        // offer needed somewhere to remember a "no" across launches.
        return UninstallerEngine(home: home, apps: ports.apps, fs: ports.fs,
                                 trash: ports.trash, running: ports.running,
                                 extensions: SystemExtensionLister(),
                                 store: store, trashChanged: trashChanged)
    }

    /// The engine and the model that calls it. The engine's "an app reached the
    /// Trash" goes into a stream the model reads (`listenForTrash`), newest one
    /// kept: the signal means "look again" and carries nothing, so two that
    /// arrive before anyone looks are one.
    public func makeModule(store: NamespacedStore) -> ModuleParts<UninstallerViewModel> {
        let (arrivals, arrived) = AsyncStream.makeStream(of: Void.self,
                                                         bufferingPolicy: .bufferingNewest(1))
        let engine = productionEngine(store: store, trashChanged: { arrived.yield() })
        return ModuleParts(engine: engine,
                           model: UninstallerViewModel(work: engine, trashArrivals: arrivals))
    }

    /// Closes the model; the host calls it before the engine's `deactivate()`, on
    /// the person's switch and on quit.
    public func stop(_ model: UninstallerViewModel) { model.stop() }

    /// Asked of the model, not of the engine through a cast: a model
    /// that is stopped answers nil.
    public func backgroundScan(_ parts: ModuleParts<UninstallerViewModel>) async -> ScanReport? {
        await parts.model.backgroundScan()
    }

    public func menuBar(_ model: UninstallerViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ model: UninstallerViewModel) -> AnyView {
        AnyView(UninstallerSettingsPage(uvm: model))
    }
    // statusAppearance: default (.inactive) — not a toggle, never tints the menu bar.
}
