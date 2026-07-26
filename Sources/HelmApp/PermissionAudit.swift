import AppKit
import HelmRuntime
import Module_Uninstaller_Engine

/// Checks what Helm needs from macOS the first time it runs, and says so once.
/// Discovered the hard way: without Full Disk Access an uninstall silently
/// leaves app containers on disk.
@MainActor enum PermissionAudit {
    private static let seenKey = "permissionAuditShown"

    static func runOnFirstLaunch() {
        Task {
            let access = PermissionCheck.currentFullDiskAccess()
            // Logged every launch, not only the first: "it was granted
            // yesterday and is denied today" is the shape of the ad-hoc
            // signing problem, and only a line per launch shows it.
            HelmLog.shared.info("permissions",
                                "full disk access: \(access.rawValue), "
                                + "accessibility: \(PermissionCheck.currentAccessibility().rawValue)")
            guard !AppSettings.store.bool(seenKey, default: false) else { return }
            AppSettings.store.set(true, for: seenKey)
            guard access == .denied else { return }
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
