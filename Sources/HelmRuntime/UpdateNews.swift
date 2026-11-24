import Foundation

/// Whether an update Helm has just found is worth interrupting somebody for.
///
/// `UpdateService.available` is drawn by one card on the About page, inside a
/// settings window a menu-bar app does not open by itself, so a release the
/// daily check finds is said in a banner.
///
/// Pure for the same reason as `ScanNews`: every refusal here is a banner
/// somebody would otherwise have been shown for nothing, and each is a test
/// rather than an argument.
public enum UpdateNews {

    /// The version to say out loud, or nil for silence.
    ///
    /// **A check somebody pressed says nothing.** The card they pressed it on is
    /// already answering, in front of them, with the button that installs it; a
    /// banner over that window is the same sentence twice. `startedByHand` is
    /// which of two call sites asked, `checkNow()` or `checkOnLaunch()`.
    ///
    /// **And a hand check does not spend the announcement.** It is refused
    /// before `lastAnnounced` is consulted, so nothing is recorded for it and
    /// the silent check that follows still has its say — pressing the button
    /// once must not be what buys the day's silence.
    ///
    /// **The same version is announced once**: the same offer every morning is
    /// how a person learns to switch a channel off. The tag is compared as
    /// published, because that is what the caller stores and the next response
    /// carries.
    public static func version(toAnnounce found: String,
                               lastAnnounced: String?,
                               startedByHand: Bool) -> String? {
        guard !startedByHand else { return nil }
        guard found != lastAnnounced else { return nil }
        return found
    }
}
