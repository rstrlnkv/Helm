import Foundation
import IOKit.ps

/// What the power source says, or nothing at all.
///
/// Moved here from Keep Awake, which had the only copy: a background scan has to
/// know whether it would be reading the volume off a battery, and a second IOKit
/// read written in the coordinator is the duplication this target exists to
/// prevent.
public enum PowerSource {

    public struct Reading: Equatable, Sendable {
        /// Running on the battery right now. Not the same as "has a battery".
        public let onBattery: Bool
        /// 0–100. Only present when IOKit gave both a current and a maximum.
        public let percent: Int

        public init(onBattery: Bool, percent: Int) {
            self.onBattery = onBattery
            self.percent = percent
        }
    }

    /// Nil when the dictionary IOKit handed back was incomplete — which is a
    /// different thing from "on mains" and from "0%", and callers decide which
    /// way to read it. Keep Awake treats an unreadable source as *not* on power,
    /// because ending a session early is the safe failure there; a background
    /// scan treats it as mains, because never scanning on a Mac whose hardware
    /// stays quiet is the worse of its two failures.
    ///
    /// **"I don't know" must not arrive as 0%.** Keep Awake's battery guard
    /// reads a low figure as a critical battery and ends the session, so an
    /// incomplete dictionary used to stop it for no reason at all.
    public static func current() -> Reading? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, first)?
                  .takeUnretainedValue() as? [String: Any]
        else { return nil }

        let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
        guard let now = description[kIOPSCurrentCapacityKey] as? Int,
              let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
        else { return nil }

        return Reading(onBattery: onBattery, percent: Int((Double(now) / Double(max)) * 100.0))
    }

    /// A Mac with no battery is a desktop, and a desktop is always on mains.
    /// A source that will not answer is treated the same way, for the reason in
    /// `current()`: refusing to ever scan on a Mac whose hardware stays quiet is
    /// the worse failure.
    public static var isOnMains: Bool {
        guard let reading = current() else { return true }
        return !reading.onBattery
    }
}
