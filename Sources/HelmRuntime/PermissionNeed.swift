import Foundation

/// What Helm can do only with a grant, and which grant that is.
///
/// This table exists so a feature can never again be shipped with a switch that
/// macOS quietly ignores: the settings page lists the permissions from here,
/// and each feature asks here what it needs before letting the user believe an
/// option is doing something.
public enum PermissionNeed: String, CaseIterable, Sendable {
    case fullDiskAccess, accessibility

    /// Things Helm does that the system gates. Named after the user-visible
    /// capability, not the API behind it.
    public enum Feature: String, CaseIterable, Sendable {
        case pointerNudge          // Keep Awake moves the pointer
        case appContainers         // Uninstaller removes ~/Library/Containers
        case leftoverRemoval       // Login items & extensions removal
        case wholeDiskScan         // Disk Space reads protected folders
        case vpnControl            // needs nothing
        case homebrew              // needs nothing
    }

    public static func of(_ feature: Feature) -> PermissionNeed? {
        switch feature {
        case .pointerNudge: .accessibility
        case .appContainers, .leftoverRemoval, .wholeDiskScan: .fullDiskAccess
        case .vpnControl, .homebrew: nil
        }
    }

    public func state(accessibility: PermissionState, fullDisk: PermissionState) -> PermissionState {
        switch self {
        case .accessibility: accessibility
        case .fullDiskAccess: fullDisk
        }
    }

    public func openSettings() {
        switch self {
        case .accessibility: PermissionCheck.openAccessibilitySettings()
        case .fullDiskAccess: PermissionCheck.openFullDiskAccessSettings()
        }
    }

    /// English, and the fallback rather than the source: the app maps each
    /// case to its localized strings. Stated here so a permission cannot be
    /// added without saying what it is and why Helm wants it — an unexplained
    /// request is one people deny.
    public var title: String {
        switch self {
        case .fullDiskAccess: "Full Disk Access"
        case .accessibility: "Accessibility"
        }
    }

    public var why: String {
        switch self {
        case .fullDiskAccess:
            "Needed to remove app containers and to read every folder when scanning the disk."
        case .accessibility:
            "Needed for Keep Awake to nudge the pointer."
        }
    }
}
