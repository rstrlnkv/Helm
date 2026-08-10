import Foundation
import IOKit
import IOKit.ps
import CoreGraphics

/// What this Mac physically is, for settings that only mean something on some
/// of them.
///
/// «Keep awake with an external display» is a rule about being docked, and a
/// Mac mini has no notion of docked: every display it has is external, so the
/// rule is unconditionally true there and amounts to «never sleep». «Stop on
/// low battery» is a guard on a battery a Mac Studio does not have. Both were
/// drawn on every Mac, and on a desktop the first one lied about applying while
/// the second could never fire.
///
/// **These are hardware facts, not readings of the current state.** A laptop
/// with the lid shut reports only external displays — the built-in panel goes
/// offline — so `CGGetOnlineDisplayList` cannot tell a MacBook in clamshell
/// from a Mac mini, and a rule hidden on that evidence would disappear exactly
/// when somebody docked. The question «does this Mac have a built-in panel»
/// has to be asked of the machine, not of what is switched on right now.
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

    /// True for a Mac with a panel of its own — laptops and iMacs.
    ///
    /// **Measured, and the obvious answer was wrong.** `AppleBacklightDisplay`
    /// is the service the internet names for this; probed on an Apple-silicon
    /// MacBook Pro (`hw.model` = `Mac15,6`) it does not exist, so the check
    /// would have hidden the display rule on every modern laptop. `hw.model`
    /// itself is no help either: Apple silicon reports `Mac15,6`, not
    /// `MacBookPro18,3`, so the family is not in the string any more.
    ///
    /// What does answer, in two parts that cover the three shapes of Mac:
    /// a battery means a laptop, and a laptop has a panel whether the lid is
    /// open or shut; an iMac has no battery and does have one, and an iMac
    /// whose panel is offline is a Mac that is asleep, so asking the window
    /// server is safe there. A mini, a Studio and a Pro answer no to both.
    public static var hasBuiltInDisplay: Bool {
        if hasBattery { return true }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 }
    }

    /// A lid to close. The clamshell setting turns system sleep off for the
    /// whole Mac through a sudoers rule — and on a machine with no lid there is
    /// nothing that rule could ever be for. A battery is the test: every Mac
    /// with a lid has one and no Mac without a lid does.
    public static var hasLid: Bool { hasBattery }
}
