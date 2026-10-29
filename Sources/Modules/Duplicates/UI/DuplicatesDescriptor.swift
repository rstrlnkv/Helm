import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import SwiftUI

@MainActor public final class DuplicatesDescriptor: ModuleDescriptor {
    public typealias Model = DuplicatesViewModel

    public static let id = ModuleID(DuplicatesEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: DupStr.moduleName, summary: DupStr.summary,
        sfSymbol: "doc.on.doc", permissions: [.fullDisk]) }
    public static let category: ModuleCategory = .files
    public static let tint = ModuleTint(
        ordinary: (light: (0.000, 0.645, 0.688), dark: (0.000, 0.646, 0.690)),
        increasedContrast: (light: (0.000, 0.516, 0.550), dark: (0.000, 0.516, 0.551)))
    public static let glyph = ShellGlyph(
        body: ShellGlyph.box(8, 8, 12.5, 12.5, 3.5),
        extra: {
            var back = Path()
            back.move(to: ShellGlyph.pt(7.5, 16))
            back.addArc(tangent1End: ShellGlyph.pt(3.5, 16), tangent2End: ShellGlyph.pt(3.5, 3.5), radius: 3.5)
            back.addArc(tangent1End: ShellGlyph.pt(3.5, 3.5), tangent2End: ShellGlyph.pt(16, 3.5), radius: 3.5)
            back.addArc(tangent1End: ShellGlyph.pt(16, 3.5), tangent2End: ShellGlyph.pt(16, 16), radius: 3.5)
            back.addLine(to: ShellGlyph.pt(16, 7.5))
            return back
        }())
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        productionEngine(store: store)
    }

    /// The one place the production engine is built; `makeModule` needs it as
    /// the concrete type the model calls.
    private func productionEngine(store: NamespacedStore) -> DuplicatesEngine {
        DuplicatesEngine(store: store, trashing: HelmTrash.moveToTrash)
    }

    /// The engine and the model that calls it, built over one store. The keychain is
    /// not asked here — the model's `init` reads only the remembered folder from
    /// the store; the keychain waits for the first draw
    /// (`DuplicatesViewModel.appear()`), so the module starting at launch asks
    /// it nothing. The model's state outlives the settings page because the
    /// host keeps these parts, not because the page does.
    public func makeModule(store: NamespacedStore) -> ModuleParts<DuplicatesViewModel> {
        let engine = productionEngine(store: store)
        return ModuleParts(engine: engine, model: DuplicatesViewModel(work: engine, store: store))
    }

    /// Closes the model; the host calls it before the engine's `deactivate()`, on
    /// the person's switch and on quit.
    public func stop(_ model: DuplicatesViewModel) { model.stop() }

    /// Asked of the model, not of the engine through a cast or the wire: a model
    /// that is stopped answers nil.
    public func backgroundScan(_ parts: ModuleParts<DuplicatesViewModel>) async -> ScanReport? {
        await parts.model.backgroundScan()
    }

    public func menuBar(_ model: DuplicatesViewModel) -> MenuBarContribution? { .utility }
    public func settingsPage(_ model: DuplicatesViewModel) -> AnyView {
        AnyView(DuplicatesSettingsPage(dvm: model))
    }
}
