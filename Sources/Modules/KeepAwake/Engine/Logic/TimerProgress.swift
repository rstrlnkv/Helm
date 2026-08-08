import Foundation
import HelmRuntime

/// Fraction of a timed session that is still remaining (1 → just started,
/// 0 → finished). Drives the menu-bar ring drawn as a countdown arc.
public enum TimerProgress {
    /// Not a number is *finished*, which is what this line answered while it
    /// was spelled `min(1, max(0, x))`: `Swift.max(0, .nan)` is 0, and the
    /// shared clamp hands NaN back instead. Two dates far enough apart overflow
    /// their own subtraction, `left / total` is then `inf / inf`, and `total >
    /// 0` cannot see that coming. What comes out of here is
    /// `StatusAppearance.timerProgress`, which the host converts to an `Int`
    /// once a second.
    public static func remainingFraction(now: Date, start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let left = end.timeIntervalSince(now)
        return (left / total).clampedIfFinite(to: 0...1) ?? 0
    }

    /// Compact remaining-time label: "9:05" under an hour, "1:04:09" above it,
    /// and never negative.
    ///
    /// The app has one, read by the menu bar, the panel tile and the settings
    /// page — it had three, and the third had no hours field, so a two-hour
    /// session read "120:00" beside a menu bar saying "2:00:00".
    ///
    /// The seconds are bounded before they are converted, not after:
    /// `Int(_:)` of a `Double` past `Int.max` **traps**, and every surface calls
    /// this once a second with `end.timeIntervalSinceNow` — so a deadline that
    /// got past the engine would take the menu bar, the panel widget and the
    /// settings page with it. The engine bounds what it restores; a countdown is
    /// not the place to find out that it did not.
    public static func label(remaining seconds: TimeInterval) -> String {
        let t = Int(seconds.rounded().clampedIfFinite(to: 0...TimerPolicy.longestSession) ?? 0)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
