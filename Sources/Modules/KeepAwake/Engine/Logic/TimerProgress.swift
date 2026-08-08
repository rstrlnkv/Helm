import Foundation
import HelmRuntime

/// Fraction of a timed session that is still remaining (1 → just started,
/// 0 → finished). Drives the menu-bar ring drawn as a countdown arc.
public enum TimerProgress {
    public static func remainingFraction(now: Date, start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let left = end.timeIntervalSince(now)
        return (left / total).clamped(to: 0...1)
    }

    /// Compact remaining-time label. The app has one, read by the menu bar, the
/// panel tile and the settings page — it had three, and the third had no hours
/// field, so a two-hour session read "120:00" beside a menu bar saying "2:00:00": "9:05" under an hour,
    /// "1:04:09" above it. Never negative.
    public static func label(remaining seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds.rounded()))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
