import AppKit
import HelmRuntime
import Module_Uninstaller_Engine

/// Checks what Helm needs from macOS the first time it runs, and says so once.
/// Discovered the hard way: without Full Disk Access an uninstall silently
/// leaves app containers on disk.
@MainActor enum PermissionAudit {
    /// Holds the version that last showed the notice, not a bare flag.
    private static let seenKey = "permissionAuditVersion"

    static func runOnFirstLaunch() {
        Task {
            let access = PermissionCheck.currentFullDiskAccess()
            // Logged every launch, not only the first: "it was granted
            // yesterday and is denied today" is the shape of the ad-hoc
            // signing problem, and only a line per launch shows it.
            HelmLog.shared.info("permissions",
                                "full disk access: \(access.rawValue), "
                                + "accessibility: \(PermissionCheck.currentAccessibility().rawValue)")
            // Re-arm on every build: an ad-hoc signature ties the grant to
            // one exact binary, so an update silently revokes it while the
            // checkbox stays ticked. Warning once per version, not once ever.
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            guard AppSettings.store.string(seenKey, default: "") != version else { return }
            guard access == .denied else { return }
            AppSettings.store.set(version, for: seenKey)
            present()
        }
    }

    private static func present() {
        let alert = NSAlert()
        alert.messageText = AppStr.permissionAuditTitle
        alert.informativeText = AppStr.permissionAuditBody
        alert.addButton(withTitle: AppStr.grant)
        alert.addButton(withTitle: AppStr.later)
        alert.alertStyle = .informational
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionCheck.openFullDiskAccessSettings()
        }
    }
}
