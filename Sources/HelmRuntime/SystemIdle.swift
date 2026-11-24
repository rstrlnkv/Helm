import CoreGraphics
import Foundation

/// Seconds since the person last used keyboard, mouse or trackpad.
///
/// `CGEventSourceSecondsSinceLastEventType` is public, needs no entitlement and
/// no Accessibility grant — it reports timing, never content, which is why macOS
/// gives it away.
///
/// The first call pays for loading the framework; after that it is free, so a
/// once-a-minute poll can ask freely.
///
/// **It does not distinguish Helm's own synthetic events from a person's.**
/// Keep Awake's pointer nudge posts a `mouseMoved` to `.cghidEventTap`, which
/// resets this counter exactly as a hand on the trackpad would, with or without
/// the Accessibility grant. `ScanRunner.advance` discounts Helm's own nudges;
/// this reader does not, and must not pretend to.
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
