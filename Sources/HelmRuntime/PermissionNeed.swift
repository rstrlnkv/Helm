import Foundation

/// What Helm can do only with a grant, and which grant that is.
///
/// This table exists so a feature can never again be shipped with a switch that
/// macOS quietly ignores: the settings page lists the permissions from here,
/// and each feature asks here what it needs before letting the user believe an
/// option is doing something.
public enum PermissionNeed: String, CaseIterable, Sendable {
    case fullDiskAccess, accessibility, screenRecording

    /// Things Helm does that the system gates. Named after the user-visible
    /// capability, not the API behind it.
    public enum Feature: String, CaseIterable, Sendable {
        case pointerNudge          // Keep Awake moves the pointer
        case appContainers         // Uninstaller removes ~/Library/Containers
        case leftoverRemoval       // Login items & extensions removal
        case wholeDiskScan         // Disk Space reads protected folders
        case vpnControl            // needs nothing
        case homebrew              // needs nothing
        case layoutSwitch          // Layout reads keystrokes and types corrections
        case screenCapture         // Screenshots freezes the screen and cuts pictures from it
    }

    public static func of(_ feature: Feature) -> PermissionNeed? {
        switch feature {
        case .pointerNudge, .layoutSwitch: .accessibility
        case .appContainers, .leftoverRemoval, .wholeDiskScan: .fullDiskAccess
        case .screenCapture: .screenRecording
        case .vpnControl, .homebrew: nil
        }
    }

    /// How a module descriptor spells this grant — `ModulePermission`'s case
    /// name, which `HelmContract` owns and this target cannot import.
    ///
    /// The two enums do not agree: this one says `fullDiskAccess`, the contract
    /// says `fullDisk`. The one place that compared them did it through
    /// `rawValue`, which is true of Accessibility by coincidence and could
    /// never have matched for the disk — so the check would have passed for the
    /// grant it was written for and silently failed open for the other.
    /// `FeaturePermissionsTests` pins this string against the real cases.
    public var declaredName: String {
        switch self {
        case .fullDiskAccess: "fullDisk"
        case .accessibility: "accessibility"
        case .screenRecording: "screenRecording"
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
