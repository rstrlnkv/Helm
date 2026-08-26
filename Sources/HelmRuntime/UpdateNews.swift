import Foundation

/// Whether an update Helm has just found is worth interrupting somebody for.
///
/// The check itself was never the missing half: `UpdateCheck` decides what a
/// release response means and eight tests hold it. What was missing is that the
/// answer went nowhere anyone would be — `UpdateService.available` is drawn by
/// one card, on the About page, inside a settings window a menu-bar app does not
/// open by itself. The daily launch check found a release, wrote it into a
/// published property, logged a line, and waited for somebody to go looking.
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
    /// not a flag standing in for a live fact — it is which of two call sites
    /// asked, `checkNow()` or `checkOnLaunch()`, and neither can be mistaken for
    /// the other.
    ///
    /// **And a hand check does not spend the announcement.** It is refused
    /// before `lastAnnounced` is consulted, so nothing is recorded for it and
    /// the silent check that follows still has its say — pressing the button
    /// once must not be what buys the day's silence.
    ///
    /// **The same version is announced once.** The launch check runs every day
    /// against a release that may sit there for a fortnight; the same offer
    /// every morning is how a person learns to switch a channel off. What is
    /// compared is the tag as published, because that is what the caller stores
    /// and what the next response will carry — comparing parsed numbers would
    /// make `v0.12.0` and `0.12.0` two announcements of one release.
    public static func version(toAnnounce found: String,
                               lastAnnounced: String?,
                               startedByHand: Bool) -> String? {
        guard !startedByHand else { return nil }
        guard found != lastAnnounced else { return nil }
        return found
    }
}
