import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Leftovers_Engine

@MainActor public final class LeftoversDescriptor: ModuleDescriptor {
    public typealias Model = LeftoversViewModel

    public static let id = ModuleID(LeftoversEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: LfStr.moduleName, shortName: LfStr.moduleNameShort,
        summary: LfStr.summary,
        sfSymbol: "wand.and.rays", permissions: [.fullDisk]) }
    public static let category: ModuleCategory = .utilities
    public static let tint = ModuleTint(
        ordinary: (light: (0.675, 0.498, 0.369), dark: (0.718, 0.541, 0.400)),
        increasedContrast: (light: (0.587, 0.433, 0.321), dark: (0.579, 0.436, 0.322)))
    public static let glyph = ShellGlyph(
        body: {
            var star = Path()
            star.move(to: ShellGlyph.pt(12, 3))
            star.addCurve(to: ShellGlyph.pt(21, 12), control1: ShellGlyph.pt(12.6, 8.5), control2: ShellGlyph.pt(15.5, 11.4))
            star.addCurve(to: ShellGlyph.pt(12, 21), control1: ShellGlyph.pt(15.5, 12.6), control2: ShellGlyph.pt(12.6, 15.5))
            star.addCurve(to: ShellGlyph.pt(3, 12), control1: ShellGlyph.pt(11.4, 15.5), control2: ShellGlyph.pt(8.5, 12.6))
            star.addCurve(to: ShellGlyph.pt(12, 3), control1: ShellGlyph.pt(8.5, 11.4), control2: ShellGlyph.pt(11.4, 8.5))
            star.closeSubpath()
            return star
        }())
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        LeftoversEngine(store: store)
    }

    /// The engine and the model that calls it, built together. The model holds the
    /// scan and every checkbox for as long as the module lives, so Settings
    /// rebuilding the page on each sidebar visit costs neither.
    public func makeModule(store: NamespacedStore) -> ModuleParts<LeftoversViewModel> {
        let engine = LeftoversEngine(store: store)
        return ModuleParts(engine: engine, model: LeftoversViewModel(work: engine))
    }

    /// Closes the model; the host calls it before the engine's `deactivate()`: on
    /// the person's switch after `willDisable()` has given the switches back, and
    /// on quit, where no `willDisable()` runs.
    public func stop(_ model: LeftoversViewModel) { model.stop() }

    public func menuBar(_ model: LeftoversViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ model: LeftoversViewModel) -> AnyView {
        AnyView(LeftoversSettingsPage(lvm: model))
    }
}
