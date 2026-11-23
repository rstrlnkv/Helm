import Foundation
import HelmContract

/// What Helm can do only with a grant, and which grant that is.
///
/// The settings page lists the permissions from here, and a module's declared
/// permission (`ModulePermission`) maps to its need through `init?(_:)`.
public enum PermissionNeed: String, CaseIterable, Sendable {
    case fullDiskAccess, accessibility, screenRecording

    /// What macOS gate a declared permission stands behind; the admin helper
    /// is a sudoers rule, not a privacy pane, and has none.
    public init?(_ permission: ModulePermission) {
        switch permission {
        case .fullDisk: self = .fullDiskAccess
        case .accessibility: self = .accessibility
        case .screenRecording: self = .screenRecording
        case .adminHelper: return nil
        }
    }

    public func state(accessibility: PermissionState, fullDisk: PermissionState,
                      screenRecording: PermissionState) -> PermissionState {
        switch self {
        case .accessibility: accessibility
        case .fullDiskAccess: fullDisk
        case .screenRecording: screenRecording
        }
    }

    public func openSettings() {
        switch self {
        case .accessibility: PermissionCheck.openAccessibilitySettings()
        case .fullDiskAccess: PermissionCheck.openFullDiskAccessSettings()
        case .screenRecording: PermissionCheck.openScreenRecordingSettings()
        }
    }
}
