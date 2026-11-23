import HelmContract
import HelmUI
import Tweak_DisplayCorners_UI

/// All compiled-in tweak descriptors. Add future tweaks here, and nothing else of a tweak is imported
/// by the host: the descriptor already depends on its own engine.
@MainActor enum TweakRegistry {
    static let all: [any TweakDescriptor] = [DisplayCornersDescriptor()]
}

extension TweakDescriptor {
    /// `id`, `name`, `summary` and `glyph` are static requirements and aren't reachable directly on the
    /// `any TweakDescriptor` existential; these forwarders go through the concrete type in one place, as
    /// `ModuleRegistry.swift`'s do.
    var idRaw: String { type(of: self).id.rawValue }
    var tweakName: String { type(of: self).name }
    var tweakSummary: String { type(of: self).summary }
    var tweakGlyph: HelmUI.ShellGlyph { type(of: self).glyph }
}
