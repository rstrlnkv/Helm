import AppKit
import HelmRuntime
import Module_Uninstaller_Engine

/// Checks what Helm needs from macOS the first time it runs, and says so once.
/// Discovered the hard way: without Full Disk Access an uninstall silently
/// leaves app containers on disk.
@MainActor enum PermissionAudit {
    private static let seenKey = "permissionAuditShown"

    static func runOnFirstLaunch() {
        guard !AppSettings.store.bool(seenKey, default: false) else { return }
        Task {
            let access = PermissionCheck.currentFullDiskAccess()
            let extensions = await SystemExtensionQuery.installed()
            HelmLog.shared.info("permissions",
                                "full disk access: \(access.rawValue), system extensions: \(extensions.count)")
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
