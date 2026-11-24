import CoreGraphics
import Foundation
import HelmRuntime

public protocol SleepAssertions: AnyObject {   // IOKit
    /// Whether the Mac is now being held awake — **everything that was asked
    /// for**, so `display: true` answers no if only the system half went up.
    ///
    /// A refused assertion read as a success lights the menu bar for a Mac that
    /// then sleeps on schedule. Not `@discardableResult` for the same reason: a
    /// caller that drops the answer cannot tell the person.
    func preventSleep(display: Bool) -> Bool
    func release()
}

public protocol DisplayInfoPort: AnyObject {
    /// One flag per online display. `[]` also means `CGGetOnlineDisplayList`
    /// failed, which fails toward sleep: no external display is seen.
    func builtInFlags() -> [Bool]
}

public protocol PowerInfoPort: AnyObject {
    /// nil both for a Mac with no battery and for an incomplete IOKit dictionary.
    func snapshot() -> (onBattery: Bool, percent: Int)?
    /// Which supply is running the Mac, which is **not** derivable from
    /// `snapshot()`, whose nil folds a desktop together with a failed read.
    /// `PowerSource.supply()` has the rest.
    ///
    /// **Three answers, because the system has three.** This module folds «I
    /// don't know» to «not on mains», because letting the Mac sleep is its safe
    /// failure. The battery guard reads `snapshot()`; on nil it asks
    /// `BatteryGuard.shouldDeactivateWithNoReading`, which ends the session when
    /// the guard is on and this answer is not `.mains`.
    func supply() -> PowerSource.Supply?
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
    /// Every observer this module starts has to be stoppable, because the
    /// module can be switched off: the engine is dropped, the port goes with
    /// it, and anything still holding a pointer to the port is holding freed
    /// memory.
    ///
    /// `NotificationCenter` observers are no exemption: the centre keeps its
    /// tokens but does not remove them, so the token is the thing to keep in
    /// order to take the observer back out.
    func stopObserving()
}

/// Whether this Mac has a lid at all — a fact about the hardware, asked at each
/// use. `MacHardware.hasLid` (a battery is present) in production; a port so a
/// Mac with no lid can be stood up in a test. Not a reading that can fail: the
/// system answer is a plain yes or no, so there is no third state to name.
public protocol LidInfoPort: AnyObject {
    func hasLid() -> Bool
    /// Whether this Mac has a battery, `MacHardware.hasBattery` in production.
    /// A hardware fact asked at each use, like `hasLid`: yes or no, no third state.
    func hasBattery() -> Bool
}

public protocol DisplayObserverPort: AnyObject {
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
    func stopObserving()
}

public protocol AppRunningPort: AnyObject {
    func runningBundleIDs() -> Set<String>
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
    /// Every observer this module starts has to be stoppable; see
    /// `PowerInfoPort.stopObserving` for why there is no exemption.
    func stopObserving()
}

public protocol PointerPort: AnyObject {
    func location() -> CGPoint?
    func move(to: CGPoint)
    func displayBounds(containing: CGPoint) -> CGRect?
}

public protocol ClamshellPort: AnyObject {
    func isSudoersInstalled() -> Bool
    /// Whether `pmset disablesleep` can actually be run without a password.
    ///
    /// Not the same question as «is our file there»: another file in
    /// `/etc/sudoers.d` can grant the same command under another name. Then the
    /// file check says no while the capability is granted, and after removal it
    /// says no while passwordless `pmset disablesleep` remains — a revocation
    /// reported as done that revoked nothing.
    ///
    /// **The probe is a write.** It runs `sudo -n pmset disablesleep 0`, a real
    /// child process that changes system state, so it is not asked casually.
    func canDisableSleepWithoutPassword() -> Bool
    func installSudoers(_ done: @escaping @Sendable (Bool) -> Void)   // admin prompt once
    /// Takes the rule back out when the feature is switched off. Raises the
    /// administrator dialog, so it needs somebody at the screen.
    func removeSudoers(_ done: @escaping @Sendable (Bool) -> Void)
    /// Takes the rule back out using the rule's own grant — `sudo -n`, no
    /// dialog, nothing to decline.
    ///
    /// Synchronous on purpose. It is the one withdrawal a *terminating* process
    /// can carry out: anything posted to a queue on the way out is a promise the
    /// process may not live to keep, and the rule is then orphaned.
    ///
    /// `false` is an ordinary answer, not a fault: a rule with no withdrawal
    /// line, or one written by something else, does not permit it.
    func removeSudoersWithoutPassword() -> Bool
    func setDisableSleep(_ on: Bool) -> Bool                // pmset (passwordless)
    /// `pmset -g`'s output; nil when it did not answer (non-zero status), which
    /// is not the same as an empty report that says sleep is enabled.
    func pmsetReport() -> String?
}

public protocol Clock: AnyObject {
    func schedule(after: TimeInterval, _ block: @escaping @Sendable () -> Void) -> AnyObject
    func now() -> Date
}
