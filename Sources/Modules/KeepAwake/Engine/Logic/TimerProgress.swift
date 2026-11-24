import Foundation
import HelmRuntime

/// Fraction of a timed session that is still remaining (1 → just started,
/// 0 → finished). Drives the menu-bar ring drawn as a countdown arc.
public enum TimerProgress {
    /// Not a number is *finished*. Two dates far enough apart overflow their
    /// own subtraction, `left / total` is then `inf / inf`, and `total > 0`
    /// cannot see that coming. What comes out of here is
    /// `StatusAppearance.timerProgress`, which the host converts to an `Int`
    /// once a second.
    ///
    /// Only NaN: an infinite fraction is more of the session left than the
    /// session ever was, and the bound already answers that with a full ring.
    public static func remainingFraction(now: Date, start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let left = end.timeIntervalSince(now)
        return (left / total).clamped(to: 0...1, whenNotANumber: 0)
    }

    /// Compact remaining-time label: "9:05" under an hour, "1:04:09" above it,
    /// and never negative.
    ///
    /// The one label the menu bar, the panel tile and the settings page read,
    /// so a two-hour session reads the same on all three.
    ///
    /// The seconds are bounded before they are converted, not after:
    /// `Int(_:)` of a `Double` past `Int.max` **traps**, and every surface calls
    /// this once a second with `end.timeIntervalSinceNow`, so a deadline that
    /// got past the engine would take all three surfaces with it.
    public static func label(remaining seconds: TimeInterval) -> String {
        let t = Int(seconds.rounded().clampedIfFinite(to: 0...TimerPolicy.longestSession) ?? 0)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
