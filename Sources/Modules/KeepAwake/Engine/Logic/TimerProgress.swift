import Foundation

/// Fraction of a timed session that is still remaining (1 → just started,
/// 0 → finished). Drives the menu-bar ring drawn as a countdown arc.
public enum TimerProgress {
    public static func remainingFraction(now: Date, start: Date, end: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let left = end.timeIntervalSince(now)
        return min(1, max(0, left / total))
    }
}
