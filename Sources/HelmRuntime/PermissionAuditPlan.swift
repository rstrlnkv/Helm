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

    /// True when this version has not yet said its piece.
    ///
    /// Keyed by version rather than a flag: the same build asking twice is
    /// nagging, and a new build not asking at all is the bug this exists for.
    public static func shouldSpeak(lastSeenVersion: String, current: String) -> Bool {
        !current.isEmpty && lastSeenVersion != current
    }
}
