import CoreGraphics
import Foundation

/// Seconds since the person last used keyboard, mouse or trackpad.
///
/// `CGEventSourceSecondsSinceLastEventType` is public, needs no entitlement and
/// no Accessibility grant — it reports timing, never content, which is why macOS
/// gives it away.
///
/// Measured here on 2026-08-03, macOS 27: **34,4 ms on the very first call while
/// the framework loads, then 0,0000 ms** to the resolution of a `Date` pair. So
/// a once-a-minute poll can ask freely, and the one cold call is paid at launch
/// rather than inside a loop.
///
/// **It does not distinguish Helm's own synthetic events from a person's.**
/// Keep Awake's pointer nudge posts a `mouseMoved` to `.cghidEventTap`, and that
/// resets this counter exactly as a hand on the trackpad would. Its default
/// interval is five minutes — the same as `ScanSchedule.idleThreshold` — so a
/// caller that trusts this number alone will find that **no background scan ever
/// runs** for anybody with the nudge switched on. The scan coordinator discounts
/// Helm's own nudges; this reader does not, and must not pretend to.
///
/// Re-measured rather than inherited, because the whole feature turns on it:
/// a synthetic `mouseMoved` took the counter from **284,97 s to 0,30 s**. It
/// arrived with Accessibility *denied*, so the hazard does not need the grant
/// and cannot be dismissed as an artefact of one machine's permissions.
public enum SystemIdle {
    /// `.combinedSessionState` rather than `.hidSystemState`: both are equally
    /// fooled by a synthetic event, and the combined one also counts the
    /// keyboard events a session receives from anywhere.
    ///
    /// The `eventType` is the documented "any event" sentinel — every bit set.
    public static func seconds() -> TimeInterval {
        guard let anyEvent = CGEventType(rawValue: ~UInt32(0)) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                       eventType: anyEvent)
    }
}
