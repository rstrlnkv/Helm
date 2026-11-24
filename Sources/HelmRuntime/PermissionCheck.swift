import AppKit
import ApplicationServices
import Foundation
import Security

/// What Helm needs from macOS, and why. Read on every launch, and the person is
/// told when the build's signature changed and a grant an enabled module needs is
/// denied, so they find out before a removal silently leaves files behind.
/// Architecture/TheGates.md § Permissions.
public enum PermissionState: String, Sendable, Equatable {
    case granted, denied
}

public enum PermissionCheck {
    /// Full Disk Access is the gate on `~/Library/Containers` and
    /// `~/Library/Group Containers`; without it those leftovers cannot move.
    static func state(canReadProtectedPath: Bool) -> PermissionState {
        canReadProtectedPath ? .granted : .denied
    }

    /// Files only readable with Full Disk Access. Detection has to be a READ:
    /// writing into ~/Library/Containers is refused even when access has been
    /// granted.
    ///
    /// **Files, and never a directory.** `FileHandle(forReadingFrom:)` throws on
    /// every directory, protected or not, so a directory here answers "denied"
    /// on a Mac that granted everything.
    ///
    /// **The system-wide `TCC.db` goes first**, which is why the list can be
    /// short: a plain file, on every Mac (the per-user one can be absent), gated
    /// by Full Disk Access and nothing else. The ordinary granted case then
    /// never opens anybody's Safari bookmarks or Messages database; those stay
    /// as the fallback.
    static var probeURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
            home.appendingPathComponent("Library/Messages/chat.db"),
        ]
    }

    /// Ad-hoc signed builds have no stable identity, so macOS ties a granted
    /// permission to the exact binary. Every new build is a different binary:
    /// the entry stays checked in System Settings while the grant no longer
    /// applies. Worth telling the user instead of letting them re-check a box
    /// that is already ticked.
    public static func isAdHocSigned(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        CodeIdentity.signingInformation(ofBundleAt: bundleURL).map { $0["teamid"] == nil } ?? false
    }

    /// Whether one probe path hands over a byte.
    ///
    /// Its own member so `TheProbeAsksPathsItCanAnswerFromTests` can check that
    /// every entry of `probeURLs` is a path it can answer from.
    static func canRead(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) != nil
    }

    public static func currentFullDiskAccess() -> PermissionState {
        state(canReadProtectedPath: probeURLs.contains(where: canRead))
    }

    /// The same answer, off the thread that draws — for the settings pages that
    /// ask for it as they appear, through `helmTracksFullDiskAccess`.
    ///
    /// Usually a millisecond or less, but with no ceiling: each probe is a
    /// synchronous `open` and `read`, and a blocking syscall answers when it
    /// answers. The withheld case pays for every entry.
    ///
    /// Off the **cooperative** pool, not merely off the main actor: a plain
    /// `async` body lands on the pool that has one thread per core, where a
    /// blocking read is what `offTheCooperativePool` keeps out.
    ///
    /// `probing` is a seam, so a test can see which thread the probe ran on.
    public static func fullDiskAccess(
        probing probe: @escaping @Sendable () -> PermissionState = { currentFullDiskAccess() }
    ) async -> PermissionState {
        await offTheCooperativePool(probe)
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

extension PermissionCheck {
    /// Screen Recording, read without asking.
    ///
    /// `CGPreflightScreenCaptureAccess` answers from the process's own grant and
    /// raises no dialog, which is what a settings page that reads a status must
    /// do. It is not the request: a process that has been refused is not shown
    /// the system prompt again (`CGWindow.h`), so asking is a separate act, made
    /// once by the capture port, and the person is sent to the pane from then on.
    public static func currentScreenRecording() -> PermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Opens the exact pane the user needs; deep links are the documented way
    /// to send someone to a privacy setting.
    public static func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
    }

    /// System Settings → Keyboard, where Keyboard Shortcuts → Screenshots holds the
    /// boxes Helm asks a person to untick. The pane is the extension's own
    /// identifier; nothing deeper is addressable.
    public static func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    /// System Settings → Trackpad, the extension's own identifier (`TrackpadExtension.appex`); More Gestures is a tab inside it, not addressable.
    public static func openTrackpadSettings() {
        open("x-apple.systempreferences:com.apple.Trackpad-Settings.extension")
    }

    /// System Settings → Network, the extension's own identifier.
    public static func openNetworkSettings() {
        open("x-apple.systempreferences:com.apple.Network-Settings.extension")
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// Notifications is not a Privacy & Security pane and not a `PermissionNeed`
    /// (macOS answers for this grant through its own API), so it is only a
    /// destination. The identifier is the settings extension's own
    /// (`NotificationsSettings.appex`), not the legacy prefPane's.
    public static func openNotificationSettings() {
        open("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    }

    public static func openExtensionSettings() {
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
        /// It is not there. Read again at the moment of the move, the path names
        /// nothing — deleted since the list was drawn, or renamed away.
        case missing
        /// Helm itself refused, again, and for the other reason it ever does:
        /// the file is no longer what the scan said it was. Read again just
        /// before the move, the pair no longer matches — edited since, or a
        /// hard link, or one of them gone. Nothing was attempted.
        case changedSinceScan
        /// Helm could not read the file (or, in Duplicates, the surviving copy
        /// it is compared against) at the moment of the move: a permission
        /// withdrawn, a volume gone, a file busy. **Not `changedSinceScan`:** a
        /// person told «it moved» looks for the file, a person told «it could
        /// not be read» checks the access. Nothing was attempted.
        case unreadable
    }

    /// Cocoa's "you may not write here" error.
    private static let noPermissionCode = 513   // NSFileWriteNoPermissionError
    /// Nothing at that path. The ordinary refusal wherever a list outlives the
    /// disk it describes: Caches, DerivedData and Downloads change under a
    /// tree that can be a day old.
    private static let noSuchFileCode = NSFileNoSuchFileError
    /// The two other Cocoa codes a move to the Trash produces, named so the
    /// person gets a cause and a step out rather than the general refusal.
    private static let readOnlyVolumeCode = 642 // NSFileWriteVolumeReadOnlyError
    private static let outOfSpaceCode = 640     // NSFileWriteOutOfSpaceError

    /// Classifies using the error macOS returned. The shape of the path decides
    /// two cases only: an `.app` with an active system extension, and code 513
    /// under a container folder. Blaming Full Disk Access for every container
    /// failure would send users to a setting they had already granted.
    public static func reason(path: String, errorCode: Int, hasSystemExtension: Bool) -> Reason {
        // **Before the extension**, which is a test of the path's *shape* while
        // this is what macOS answered: «turn off its system extension» is an
        // instruction about a bundle, and this bundle is not on the disk.
        if errorCode == noSuchFileCode { return .missing }
        if hasSystemExtension, path.hasSuffix(".app") { return .activeSystemExtension }
        if errorCode == readOnlyVolumeCode { return .readOnlyVolume }
        if errorCode == outOfSpaceCode { return .diskFull }
        guard errorCode == noPermissionCode else { return .systemRefused }
        let protected = path.contains("/Library/Containers/")
            || path.contains("/Library/Group Containers/")
        return protected ? .needsFullDiskAccess : .noPermission
    }
}
