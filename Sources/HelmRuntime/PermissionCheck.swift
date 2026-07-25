import AppKit
import Foundation

/// What Helm needs from macOS, and why. Checked on first launch so the user
/// finds out before a removal silently leaves files behind — which is exactly
/// how the gap was discovered.
public enum PermissionState: String, Sendable, Equatable {
    case granted, denied
}

public enum PermissionCheck {
    /// Full Disk Access is the gate on `~/Library/Containers` and
    /// `~/Library/Group Containers`; without it those leftovers cannot move.
    public static func state(canReadProtectedPath: Bool) -> PermissionState {
        canReadProtectedPath ? .granted : .denied
    }

    /// Probe path used in production: readable only with Full Disk Access.
    public static var probeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.stocks", isDirectory: true)
    }

    public static func currentFullDiskAccess() -> PermissionState {
        let containers = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
        // Listing is permitted without the entitlement; writing is not, so the
        // check has to attempt a write and clean up after itself.
        let probe = containers.appendingPathComponent(".helm-access-probe")
        let can = FileManager.default.createFile(atPath: probe.path, contents: Data())
        if can { try? FileManager.default.removeItem(at: probe) }
        return state(canReadProtectedPath: can)
    }
}

public extension PermissionCheck {
    /// Opens the exact pane the user needs; deep links are the documented way
    /// to send someone to a privacy setting.
    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
    }

    static func openExtensionSettings() {
        open("x-apple.systempreferences:com.apple.ExtensionsPreferences")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Why a path refused to move, so the UI can say something actionable.
public enum TrashFailure {
    public enum Reason: String, Sendable, Equatable {
        case needsFullDiskAccess, activeSystemExtension, unknown
    }

    public static func reason(path: String, hasSystemExtension: Bool) -> Reason {
        if hasSystemExtension, path.hasSuffix(".app") { return .activeSystemExtension }
        if path.contains("/Library/Containers/") || path.contains("/Library/Group Containers/") {
            return .needsFullDiskAccess
        }
        return .unknown
    }
}
