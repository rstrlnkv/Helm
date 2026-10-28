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
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        let ports = HomebrewSystemPorts()
        return HomebrewEngine(locator: ports.locator, runner: ports.runner,
                              privileged: ports.privileged, user: NSUserName(),
                              marker: ports.marker, popularity: ports.popularity,
                              weight: ports.weight, tools: ports.tools, ticker: ports.ticker)
    }

    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }

    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(HomebrewSettingsPage(vm: vm))
    }
    // statusAppearance: default (.inactive).
}
