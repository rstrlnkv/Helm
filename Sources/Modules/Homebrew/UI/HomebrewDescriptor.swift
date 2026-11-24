import Foundation
import SwiftUI
import HelmContract
import HelmRuntime
import HelmUI
import Module_Homebrew_Engine

@MainActor public final class HomebrewDescriptor: ModuleDescriptor {
    public static let id = ModuleID(HomebrewEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: HbStr.moduleName, summary: HbStr.summary,
        sfSymbol: "shippingbox", permissions: []) }
    public static let category: ModuleCategory = .utilities
    public static let tint = ModuleTint(
        ordinary: (light: (0.168, 0.665, 0.293), dark: (0.145, 0.664, 0.274)),
        increasedContrast: (light: (0.135, 0.533, 0.235), dark: (0.117, 0.535, 0.221)))
    public static let glyph = ShellGlyph(
        body: ShellGlyph.box(4.5, 6, 11.5, 13.5, 3.5),
        extra: {
            var handle = Path()
            handle.move(to: ShellGlyph.pt(16, 9.5))
            handle.addLine(to: ShellGlyph.pt(17, 9.5))
            handle.addQuadCurve(to: ShellGlyph.pt(20, 12.5), control: ShellGlyph.pt(20, 9.5))
            handle.addQuadCurve(to: ShellGlyph.pt(17, 15.5), control: ShellGlyph.pt(20, 15.5))
            handle.addLine(to: ShellGlyph.pt(16, 15.5))
            return handle
        }())

    public init() {}

    public typealias Model = HomebrewViewModel

    /// Architecture/Homebrew.md § The model.
    public func makeModule(store: NamespacedStore) -> ModuleParts<HomebrewViewModel> {
        makeModule(store: store, locator: nil, runner: nil)
    }

    /// The test seam: the one place the host's wiring is built, with the two ports a test
    /// replaces so it can read what the engine ran after a press on the toggle.
    func makeModule(store: NamespacedStore, locator: BrewLocator?, runner: ProcessRunner?)
        -> ModuleParts<HomebrewViewModel> {
        let setting = UpdateBeforeChecking(store: store)
        let engine = productionEngine(updateBeforeChecking: setting, locator: locator, runner: runner)
        return ModuleParts(engine: engine, model: HomebrewViewModel(work: engine, updateBeforeChecking: setting))
    }

    /// The host closes the model before the engine goes: its stream task ends
    /// and nothing it was asked after that reaches the engine.
    public func stop(_ model: HomebrewViewModel) { model.stop() }

    private func productionEngine(updateBeforeChecking: UpdateBeforeChecking,
                                  locator: BrewLocator?, runner: ProcessRunner?) -> HomebrewEngine {
        let ports = HomebrewSystemPorts()
        return HomebrewEngine(locator: locator ?? ports.locator, runner: runner ?? ports.runner,
                              privileged: ports.privileged, user: NSUserName(),
                              marker: ports.marker, popularity: ports.popularity,
                              weight: ports.weight, tools: ports.tools, ticker: ports.ticker,
                              gate: .process, updateBeforeChecking: updateBeforeChecking)
    }

    public func menuBar(_ model: HomebrewViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ model: HomebrewViewModel) -> AnyView {
        AnyView(HomebrewSettingsPage(hb: model))
    }
    // statusAppearance: default (.inactive).
}
