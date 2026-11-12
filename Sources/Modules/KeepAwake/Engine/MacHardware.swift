import Foundation
import IOKit
import IOKit.ps

/// What this Mac physically is, for settings that only mean something on some
/// of them.
///
/// «Keep awake with an external display» is a rule about being docked, and a
/// Mac mini has no notion of docked: every display it has is external, so the
/// rule is unconditionally true there and amounts to «never sleep». «Stop on
/// low battery» is a guard on a battery a Mac Studio does not have. Both were
/// drawn on every Mac, and on a desktop the first one lied about applying while
/// the second could never fire. The first goes by having a lid, the second by
/// having a battery.
///
/// **These are hardware facts, not readings of the current state.** A laptop
/// with the lid shut reports only external displays, so a rule hidden on what
/// is switched on right now would disappear exactly when somebody docked.
public enum MacHardware {

    /// True for a Mac with an internal battery — every laptop, no desktop.
    ///
    /// `IOPSCopyPowerSourcesList` is empty on a machine with no battery, which
    /// is also what an incomplete IOKit answer looks like to
    /// `PowerSource.current()`. Here the two are not confused: an empty list is
    /// the answer, because a desktop is exactly the machine that has none.
    public static var hasBattery: Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        return !sources.isEmpty
    }

    /// A lid to close. The clamshell setting turns system sleep off for the
    /// whole Mac through a sudoers rule — and on a machine with no lid there is
    /// nothing that rule could ever be for. A battery is the test: every Mac
    /// with a lid has one and no Mac without a lid does.
    public static var hasLid: Bool { hasBattery }
}
