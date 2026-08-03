import AppKit
import ApplicationServices
import Foundation
import Security

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

    /// Files only readable with Full Disk Access. Detection has to be a READ:
    /// writing into ~/Library/Containers is refused even when access has been
    /// granted, so a write probe reported "denied" to users who had granted it.
    static var probeURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Several, because none is guaranteed to exist: TCC.db is absent on
        // macOS 26, Safari may be unused, Messages may never have run.
        return [
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
            home.appendingPathComponent("Library/Messages/chat.db"),
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Application Support/AddressBook"),
        ]
    }

    /// Ad-hoc signed builds have no stable identity, so macOS ties a granted
    /// permission to the exact binary. Every new build is a different binary:
    /// the entry stays checked in System Settings while the grant no longer
    /// applies. Worth telling the user instead of letting them re-check a box
    /// that is already ticked.
    public static func isAdHocSigned(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        return dict["teamid"] == nil
    }

    public static func currentFullDiskAccess() -> PermissionState {
        let readable = probeURLs.contains { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
            defer { try? handle.close() }
            return (try? handle.read(upToCount: 1)) != nil
        }
        return state(canReadProtectedPath: readable)
    }

    /// Accessibility. Keep Awake's pointer nudge posts a synthetic mouse event,
    /// and macOS drops those on the floor without this grant — the setting
    /// would look enabled and quietly do nothing.
    ///
    /// The non-prompting check on purpose: a settings page that reads a status
    /// must not throw a system dialog at the user for looking at it.
    public static func currentAccessibility() -> PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }
}

public extension PermissionCheck {
    /// Opens the exact pane the user needs; deep links are the documented way
    /// to send someone to a privacy setting.
    static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// Notifications is not a Privacy & Security pane and not a `PermissionNeed`
    /// — macOS answers for this grant through its own API — so it is only ever
    /// a destination. The identifier is the settings extension's own
    /// (`NotificationsSettings.appex`), not the legacy prefPane's.
    static func openNotificationSettings() {
        open("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
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
    public enum Reason: String, Codable, Sendable, Equatable, Hashable {
        case needsFullDiskAccess, activeSystemExtension, noPermission, systemRefused
        /// The volume is mounted read-only — a disk image, a locked backup, a
        /// share. Nothing about permissions will help, and the person can see
        /// the cause the moment it is named.
        case readOnlyVolume
        /// No room left. It reads as nonsense until you know the Trash is a
        /// folder on the same volume, so moving something there writes.
        case diskFull
        /// Helm itself refused: the path is not inside a folder an app may
        /// leave things in. Not a macOS error — nothing was attempted.
        case outOfScope
        /// Helm itself refused, again, and for the other reason it ever does:
        /// the file is no longer what the scan said it was. Read again just
        /// before the move, the pair no longer matches — edited since, or a
        /// hard link, or one of them gone. Nothing was attempted.
        case changedSinceScan
    }

    /// Cocoa's "you may not write here" error.
    private static let noPermissionCode = 513   // NSFileWriteNoPermissionError
    /// The two other Cocoa codes a move to the Trash actually produces, and
    /// which used to arrive as the general refusal — a sentence with no cause
    /// in it and no step out.
    private static let readOnlyVolumeCode = 642 // NSFileWriteVolumeReadOnlyError
    private static let outOfSpaceCode = 640     // NSFileWriteOutOfSpaceError

    /// Classifies using the error macOS returned, not the shape of the path:
    /// blaming Full Disk Access for every container failure sent users to a
    /// setting they had already granted.
    public static func reason(path: String, errorCode: Int, hasSystemExtension: Bool) -> Reason {
        if hasSystemExtension, path.hasSuffix(".app") { return .activeSystemExtension }
        if errorCode == readOnlyVolumeCode { return .readOnlyVolume }
        if errorCode == outOfSpaceCode { return .diskFull }
        guard errorCode == noPermissionCode else { return .systemRefused }
        let protected = path.contains("/Library/Containers/")
            || path.contains("/Library/Group Containers/")
        return protected ? .needsFullDiskAccess : .noPermission
    }
}
