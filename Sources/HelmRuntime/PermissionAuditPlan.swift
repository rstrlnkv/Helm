import Foundation

/// What to say after an update, given what the system now allows.
///
/// Every rebuild of an ad-hoc signed app is a different app to TCC, so an
/// update silently revokes every grant while the checkbox in System Settings
/// stays ticked. Checking once at first launch was not enough: the interesting
/// moment is the *update*, and the interesting answer is which of the things
/// the user already agreed to have quietly stopped working.
public enum PermissionAuditPlan {
    /// Nil when there is nothing to say — which is most launches.
    public static func missing(fullDisk: PermissionState,
                               accessibility: PermissionState,
                               needsFullDisk: Bool,
                               needsAccessibility: Bool) -> [PermissionNeed] {
        var out: [PermissionNeed] = []
        if needsFullDisk, fullDisk == .denied { out.append(.fullDiskAccess) }
        if needsAccessibility, accessibility == .denied { out.append(.accessibility) }
        return out
    }

    /// True when this **build** has not yet said its piece — and only from the
    /// second run on.
    ///
    /// The audit exists to catch a grant that went away: "it was granted
    /// yesterday and is denied today." That is a question you can only ask
    /// once there is a previous run to compare against. A first run has
    /// nothing to compare, and every module that needs a grant already shows
    /// its own note with a Grant button on its own page — asking here too
    /// meant a brand-new install requested Full Disk Access and Accessibility
    /// before the person had asked for anything.
    ///
    /// **An identity, not a version, and the difference is the whole defect.**
    /// This compared `AppBuild.shortVersion`, which is a string in a plist: a
    /// local build twenty commits on carries the same one, so every grant died
    /// and the audit said nothing, in the one situation it exists for. TCC does
    /// not judge by that string — an ad-hoc bundle has no team identifier, so a
    /// grant is tied to the cdhash, which moves whenever the bytes do.
    /// `AppBuild.codeFingerprint` is that number, and it is what the app feeds
    /// here.
    ///
    /// Still two strings, on purpose: what a build is called is the caller's
    /// business, and a plan that read the bundle itself could not be tested
    /// against a bundle it did not run from.
    public static func shouldSpeak(lastSeenIdentity: String, current: String) -> Bool {
        !lastSeenIdentity.isEmpty && !current.isEmpty && lastSeenIdentity != current
    }

    /// What to record as the baseline for the next run, or nil when there is
    /// nothing worth recording.
    ///
    /// A run that could not read its own signature must not overwrite what a
    /// readable run left: storing «cannot tell» makes the *next* run look like a
    /// first run, and a first run is silent by the rule above — so one
    /// unreadable launch would cost the following update its audit, with
    /// nothing anywhere saying so.
    public static func baseline(current: String) -> String? {
        current.isEmpty ? nil : current
    }
}
