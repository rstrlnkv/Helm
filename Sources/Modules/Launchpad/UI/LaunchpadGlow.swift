import SwiftUI
import HelmRuntime
import HelmUI

/// The one shader in the window: a soft light on the glass over the tile the arrow keys chose (`LaunchpadGlow.metal`).
///
/// It scales the selection wash's own colour, so the wash's shape and white label contrast hold (the wash peaks near 0.18
/// alpha). It runs for one static tile, a few operations a pixel. `ready` says whether the library compiled; until it
/// has, and whenever it could not, or Reduce Motion or Increase Contrast is on, the tile keeps the plain wash.
@MainActor enum LaunchpadGlow {
    /// nil until `prepare()` has an answer; true when the shader compiled.
    private(set) static var ready: Bool?
    private static var started = false

    private static let strength: Float = 0.8

    static func shader(size: CGSize) -> Shader {
        ShaderLibrary.bundle(.module).selectionGlow(.float2(size), .float(Double(strength)))
    }

    /// Whether the glow is drawn now; read fresh at each draw.
    static var on: Bool {
        ready == true && !HelmMotion.reduceMotion && !HelmAccessibility.system.increasedContrast
    }

    /// Compiles the shader once, ahead of the first selection. A failure is one log line, and the plain wash.
    static func prepare() async {
        guard !started else { return }
        started = true
        do {
            try await shader(size: CGSize(width: 1, height: 1)).compile(as: .colorEffect)
            ready = true
        } catch {
            ready = false
            HelmLog.shared.info("launchpad", "glow unavailable: \(error.localizedDescription)")
        }
    }
}
