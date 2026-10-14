import Foundation
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

    /// True when the power source list has anything in it — the guard's question.
    /// «Stop on low battery» watches the charge of the source
    /// `PowerSource.current()` reads. IOKit documents a UPS as a source of its own
    /// (`kIOPSUPSType`); that it lists one was not measured, and if it does, the
    /// UPS keeps the guard on a desktop. A UPS is **not** a battery of the Mac
    /// itself, which is what `hasInternalBattery` asks.
    ///
    /// `IOPSCopyPowerSourcesList` is empty on a machine with no source, which
    /// is also what an incomplete IOKit answer looks like to
    /// `PowerSource.current()`. Here the two are not confused: an empty list is
    /// the answer, because a Mac with nothing listed has no charge to guard.
    public static var hasBattery: Bool { hasBattery(sourceTypes: sourceTypes) }

    /// True for a Mac with a battery built in — every laptop, no desktop: some
    /// source's `kIOPSTypeKey` is `kIOPSInternalBatteryType`. IOKit documents a
    /// UPS with `kIOPSUPSType`, so a UPS does not count here; that IOKit lists a
    /// UPS at all, and with that type, was not measured.
    static var hasInternalBattery: Bool { hasInternalBattery(sourceTypes: sourceTypes) }

    /// The three questions apart from the read, so the shapes of Mac this one is
    /// not have tests too. A source with no type (`nil`) is a source all the
    /// same, and is not an internal battery.
    static func hasBattery(sourceTypes: [String?]) -> Bool { !sourceTypes.isEmpty }

    static func hasInternalBattery(sourceTypes: [String?]) -> Bool {
        sourceTypes.contains(where: PowerSource.isInternalBattery)
    }

    /// The window server is asked only when no internal battery settles it.
    static func hasBuiltInDisplay(sourceTypes: [String?],
                                  windowServerHasBuiltIn: @autoclosure () -> Bool) -> Bool {
        hasInternalBattery(sourceTypes: sourceTypes) || windowServerHasBuiltIn()
    }

    /// Each power source's `kIOPSTypeKey`, in the list's order; empty when IOKit
    /// listed nothing or answered nothing.
    private static var sourceTypes: [String?] { PowerSource.listed()?.types ?? [] }

    private static var windowServerHasBuiltIn: Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 }
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
    /// an internal battery means a laptop, and a laptop has a panel whether the
    /// lid is open or shut; an iMac has no battery and does have a panel, and
    /// an iMac whose panel is offline is a Mac that is asleep, so asking the
    /// window server is safe there. A mini, a Studio and a Pro answer no to
    /// both.
    public static var hasBuiltInDisplay: Bool {
        hasBuiltInDisplay(sourceTypes: sourceTypes, windowServerHasBuiltIn: windowServerHasBuiltIn)
    }

    /// A lid to close. The clamshell setting turns system sleep off for the
    /// whole Mac through a sudoers rule — and on a machine with no lid there is
    /// nothing that rule could ever be for. The internal battery is the test:
    /// every Mac with a lid has one and no Mac without a lid does.
    public static var hasLid: Bool { hasInternalBattery }
}
