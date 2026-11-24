import Foundation

/// What to say after an update, given what the system now allows.
///
/// Every rebuild of an ad-hoc signed app is a different app to TCC, so an
/// update silently revokes every grant while the checkbox in System Settings
/// stays ticked. The moment that matters is the *update*, and the answer is
/// which of the things the user already agreed to have quietly stopped working.
public enum PermissionAuditPlan {
    /// Empty when there is nothing to say.
    public static func missing(fullDisk: PermissionState,
                               accessibility: PermissionState,
                               screenRecording: PermissionState,
                               needsFullDisk: Bool,
                               needsAccessibility: Bool,
                               needsScreenRecording: Bool) -> [PermissionNeed] {
        var out: [PermissionNeed] = []
        if needsFullDisk, fullDisk == .denied { out.append(.fullDiskAccess) }
        if needsAccessibility, accessibility == .denied { out.append(.accessibility) }
        if needsScreenRecording, screenRecording == .denied { out.append(.screenRecording) }
        return out
    }

    /// True when the identity of this **build** differs from the one recorded
    /// last — and only from the second run on.
    ///
    /// The audit catches a grant that went away, which needs a previous run to
    /// compare against. A first run is silent: every module that needs a grant
    /// shows its own note with a Grant button, and a brand-new install should
    /// not request access before the person has asked for anything.
    ///
    /// **An identity, not a version.** A version string stays the same across
    /// many local builds while every grant dies; an ad-hoc bundle's grant is
    /// tied to the cdhash, which moves whenever the bytes do. The app feeds
    /// `AppBuild.codeFingerprint` here.
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
    /// first run, which is silent, so one unreadable launch would silently cost
    /// the following update its audit.
    public static func baseline(current: String) -> String? {
        current.isEmpty ? nil : current
    }
}
