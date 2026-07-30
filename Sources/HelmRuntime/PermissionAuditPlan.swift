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

    /// True when this version has not yet said its piece — and only from the
    /// second run on.
    ///
    /// The audit exists to catch a grant that went away: "it was granted
    /// yesterday and is denied today." That is a question you can only ask
    /// once there is a previous version to compare against. A first run has
    /// nothing to compare, and every module that needs a grant already shows
    /// its own note with a Grant button on its own page — asking here too
    /// meant a brand-new install requested Full Disk Access and Accessibility
    /// before the person had asked for anything.
    public static func shouldSpeak(lastSeenVersion: String, current: String) -> Bool {
        !lastSeenVersion.isEmpty && !current.isEmpty && lastSeenVersion != current
    }
}
