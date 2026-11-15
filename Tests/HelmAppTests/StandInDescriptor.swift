import HelmContract
import HelmUI
import SwiftUI

/// The filler a test descriptor does not care about: grey, a gear, no menu bar,
/// an empty page and a `stop` that does nothing. A fake keeps only what it records;
/// the real `ModuleDescriptor` stays undefaulted (its tint and glyph say why).
@MainActor protocol StandInDescriptor: ModuleDescriptor {}

extension StandInDescriptor {
    static var metadata: ModuleMetadata {
        ModuleMetadata(id: id, name: "\(id)", summary: "", sfSymbol: "gear", permissions: [])
    }
    static var category: ModuleCategory { .utilities }
    static var tint: ModuleTint {
        ModuleTint(ordinary: ((0.5, 0.5, 0.5), (0.5, 0.5, 0.5)),
                   increasedContrast: ((0.5, 0.5, 0.5), (0.5, 0.5, 0.5)))
    }
    static var glyph: ShellGlyph { .settings }
    func stop(_ model: Model) {}
    func menuBar(_ model: Model) -> MenuBarContribution? { nil }
    func settingsPage(_ model: Model) -> AnyView { AnyView(EmptyView()) }
}
