import HelmAppStrings
import HelmContract
import HelmRuntime
import HelmUI
import SwiftUI

/// The Tweaks entry's engine, and the only thing that ties the entry's switch to the tweaks'.
///
/// `ModuleHost` calls `activate()` when the entry is on and `deactivate()` on its switch, on `shutdown` and on
/// reset, so every tweak starts with the entry and stops with it. Holding the host and not the descriptors keeps
/// the entry's engine as small as a module's contract asks.
final class TweaksEngine: ModuleEngine {
    /// This entry's id, written once; the descriptor builds its id from it. **The string never changes.**
    static let moduleID = "tweaks"

    private let host: TweakHost

    init(host: TweakHost) { self.host = host }

    /// The host calls both on the main actor (`ModuleHost` is `@MainActor`); the protocol cannot say so.
    func activate() { let host = host; MainActor.assumeIsolated { host.activateEnabled() } }

    func deactivate() { let host = host; MainActor.assumeIsolated { host.stopAll() } }
}

/// The one sidebar entry every tweak lives under: a module as far as the sidebar, the composer, the status
/// menu, the launch page and the About count are concerned, with no widget, status appearance or hotkey of its own.
///
/// On by default, because it runs nothing until a tweak is switched on (`TweakDescriptor`).
@MainActor final class TweaksDescriptor: ModuleDescriptor {
    static let id = ModuleID(TweaksEngine.moduleID)
    static var metadata: ModuleMetadata {
        ModuleMetadata(id: id, name: AppStr.tweaksName, summary: AppStr.tweaksSummary, sfSymbol: "slider.horizontal.3")
    }
    static let category: ModuleCategory = .utilities
    // A violet, solved by the method `ModuleTint.swift` documents against the ten before it: white reads 6,86:1 on
    // it, past both floors, so the two sets and the two appearances share one value, and the nearest of the ten
    // (VPN's) is 0,337 away in sRGB, where the floor is 0,15. Found by a search over the hue wheel from violet.
    static let tint = ModuleTint(
        ordinary: (light: (0.417, 0.000, 1.000), dark: (0.417, 0.000, 1.000)),
        increasedContrast: (light: (0.417, 0.000, 1.000), dark: (0.417, 0.000, 1.000)))
    /// Two slider tracks, each with its knob.
    static let glyph = ShellGlyph(
        body: ShellGlyph.circle(9, 8, 2.5).union(ShellGlyph.circle(15, 16, 2.5)),
        extra: ShellGlyph.lines([
            [ShellGlyph.pt(3, 8), ShellGlyph.pt(6.5, 8)], [ShellGlyph.pt(11.5, 8), ShellGlyph.pt(21, 8)],
            [ShellGlyph.pt(3, 16), ShellGlyph.pt(12.5, 16)], [ShellGlyph.pt(17.5, 16), ShellGlyph.pt(21, 16)],
        ]))

    func makeModule(store: NamespacedStore) -> ModuleParts<TweakHost> {
        let host = TweakHost()
        return ModuleParts(engine: TweaksEngine(host: host), model: host)
    }

    /// The engine's `deactivate()` stops them too; asked here as well so a model that is stopped without its engine
    /// leaves nothing running. Safe twice.
    func stop(_ model: TweakHost) { model.stopAll() }

    /// Nil: no tile, no drawer row. `HelmPanel` skips a module with no contribution.
    func menuBar(_ model: TweakHost) -> MenuBarContribution? { nil }

    func settingsPage(_ model: TweakHost) -> AnyView { AnyView(TweaksPage(host: model)) }
}
