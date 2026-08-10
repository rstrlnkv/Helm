import Foundation
import AppKit
import IOKit.pwr_mgt

/// Which of the assertions `IOPMCopyAssertionsByProcess` returns count as
/// «something other than Helm is keeping this Mac awake».
///
/// The sentence this feeds is shown to a person who is wondering why their Mac
/// did not sleep, and its worth is entirely in being rare. Both halves of the
/// filter exist because a version without them made it permanent:
///
/// * **The kind.** `UserIsActive` and `SystemIsActive` say somebody is at the
///   keyboard. Four of the ten assertions on an idle Mac are of that family.
/// * **The owner.** macOS holds the *sleep* kinds as ordinary housekeeping:
///   `powerd` holds `PreventUserIdleSystemSleep` named "Powerd - Prevent sleep
///   while display is on" for as long as the screen is lit, and `sharingd`
///   holds one named "Handoff" for as long as Handoff is switched on. Counting
///   those, the line was true every time it could be read.
///
/// Pure and out here, because the two facts it encodes were both measured and
/// neither is guessable from the API's documentation.
public enum SleepHolderFilter {
    /// The kinds that actually stop a Mac going to sleep.
    public static let holdingKinds: Set<String> = [
        kIOPMAssertionTypePreventUserIdleSystemSleep as String,
        kIOPMAssertionTypePreventSystemSleep as String,
        kIOPMAssertionTypeNoIdleSleep as String,
        kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
    ]

    /// - Parameter policy: the owner's activation policy, or `nil` when the pid
    ///   is not a Launch Services process at all.
    ///
    ///   **Measured on an Apple-silicon Mac, and the obvious test was not
    ///   enough.** `powerd`, `WindowServer`, `coreaudiod` and `backupd` all
    ///   answer `nil` to `NSRunningApplication(processIdentifier:)` — so a nil
    ///   check alone looks sufficient. But `sharingd`, the one holding
    ///   "Handoff", does *not*: it is registered and comes back as
    ///   `com.apple.sharingd`. What separates it is `.prohibited` — a process
    ///   that cannot be brought to the front, which is exactly «not something
    ///   anybody can go and quit». Claude answers `.regular` and Helm itself
    ///   `.accessory`, so both stay countable.
    public static func counts(kind: String,
                              policy: NSApplication.ActivationPolicy?) -> Bool {
        guard holdingKinds.contains(kind) else { return false }
        guard let policy else { return false }
        return policy != .prohibited
    }
}
