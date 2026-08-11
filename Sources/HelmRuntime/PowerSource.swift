import Foundation
import IOKit.ps

/// What the power source says, or nothing at all.
///
/// Moved here from Keep Awake, which had the only copy: a background scan has to
/// know whether it would be reading the volume off a battery, and a second IOKit
/// read written in the coordinator is the duplication this target exists to
/// prevent.
///
/// Verified against the machine in both states on 2026-08-03, because a reading
/// that is only ever checked while plugged in has never been checked at all:
/// on mains it answered `onBattery=false percent=80` while `pmset` said
/// `AC Power, 80%; AC attached`; with the cable out, `onBattery=true
/// percent=80 mains=false` against `Battery Power, discharging`. Fed to
/// `ScanSchedule` with every other condition favourable, the second state
/// produced `.onBattery` — so the refusal this exists for fires on real
/// hardware and not only in a test.
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

    /// Which supply is running the Mac, in the two words this app reasons about.
    public enum Supply: Equatable, Sendable {
        case mains
        case battery
    }

    /// What the system says is running the Mac — **independent of the battery
    /// reading above**, which is the whole point of it.
    ///
    /// `IOPSGetProvidingPowerSourceType` names the supply from the same snapshot
    /// without consulting the source list, so it answers on a desktop where that
    /// list is empty: measured on a plugged-in laptop, `AC Power` with one source
    /// at `state=AC Power now=80 max=100`. `current()` could not be asked this,
    /// because it is nil for a Mac with no battery *and* for a dictionary that
    /// came back without a capacity — and the mains fact derived from it
    /// therefore had to guess, which is how an unreadable power source came to
    /// read as ON power.
    ///
    /// Nil means the system named a supply this app does not reason about (a
    /// UPS, or whatever a later macOS invents) or named none at all. **It is not
    /// «mains»**: each caller folds it the way its own worst failure demands,
    /// and the two callers here fold it in opposite directions.
    public static func supply() -> Supply? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        // The Get rule: the string belongs to the snapshot, which the header says
        // outright for the sibling `IOPSGetPowerSourceDescription` and implies
        // here by not saying otherwise. Retaining it would over-release the
        // constant IOKit hands back.
        let named = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        return supply(providing: named)
    }

    /// The reading, apart from the read — so the states this Mac is not in have
    /// tests too.
    static func supply(providing named: String?) -> Supply? {
        switch named {
        case kIOPSACPowerValue: .mains
        case kIOPSBatteryPowerValue: .battery
        default: nil
        }
    }

    /// The **background scan's** fold, and it is the lax one on purpose: a Mac
    /// with no battery is on mains, and a supply nothing named is treated the
    /// same way, because refusing to ever scan on a Mac whose hardware stays
    /// quiet is the worse of that caller's two failures (ARCHITECTURE.md
    /// § Background scans).
    ///
    /// Keep Awake folds the other way at its own call site — an unnamed supply
    /// must not hold a Mac awake — which is why this is a fold over `supply()`
    /// rather than a second opinion inside it.
    public static func isOnMains(_ supply: Supply?) -> Bool { supply != .battery }

    public static var isOnMains: Bool { isOnMains(supply()) }
}
