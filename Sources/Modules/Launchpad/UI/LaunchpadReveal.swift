import SwiftUI
import HelmUI
import Module_Launchpad_Engine

/// How far the window is revealed, 0 (nothing) to 1 (whole): the window's one writer (`LaunchpadWindow.apply`) sets it with the panel's
/// alpha, from a gesture's progress or from a settle's own clock. Its own object, as the page's drag is: a scrub at 120 Hz
/// republishes this and nothing else, and only the effect that reads it runs again.
@MainActor final class LaunchpadReveal: ObservableObject {
    @Published var progress: Double = 1

    /// Where the window is for a scrub at `gesture` (0 to 1 of the pinch or spread): a pinch opens from nothing, so the reveal is the
    /// gesture; a spread closes from where the window was (`base`), so the reveal is what is left of it.
    static func value(direction: PinchDirection, base: Double, gesture: Double) -> Double {
        let g = min(max(gesture.isFinite ? gesture : 0, 0), 1)
        return direction == .pinch ? g : base * (1 - g)
    }

    /// Where a settle from `from` to `to` is at `fraction` of its time, along the interface curve.
    static func settled(from: Double, to: Double, fraction: Double) -> Double {
        from + (to - from) * HelmMotion.interfaceProgress(at: fraction)
    }
}
