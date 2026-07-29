import AppKit
import HelmContract
import HelmRuntime
import HelmUI

/// Checks what Helm needs from macOS the first time it runs, and says so once.
/// Discovered the hard way: without Full Disk Access an uninstall silently
/// leaves app containers on disk.
@MainActor enum PermissionAudit {
    /// Set by the app delegate so the audit can ask which modules are on.
    static var host: ModuleHost!

    /// Holds the version that last showed the notice, not a bare flag.
    private static let seenKey = "permissionAuditVersion"

    static func run() {
        Task {
            let fullDisk = PermissionCheck.currentFullDiskAccess()
            let accessibility = PermissionCheck.currentAccessibility()
            // Logged every launch, not only the first: "it was granted
            // yesterday and is denied today" is the shape of the ad-hoc
            // signing problem, and only a line per launch shows it.
            HelmLog.shared.info("permissions",
                                "full disk access: \(fullDisk.rawValue), "
                                + "accessibility: \(accessibility.rawValue)")

            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let lastSeen = AppSettings.store.string(seenKey, default: "")
            guard PermissionAuditPlan.shouldSpeak(
                lastSeenVersion: lastSeen, current: version) else { return }
            // An empty `lastSeen` is the first launch, and telling someone that
            // permissions must be granted "again" for something they have never
            // granted is the app's first sentence being wrong.
            let firstRun = lastSeen.isEmpty

            // Asked for only what an enabled module actually uses: a permission
            // request with no reason behind it is one people deny.
            let needs = ModuleRegistry.all
                .filter { host.isEnabled($0) }
                .flatMap { $0.moduleMetadata.permissions }
            let missing = PermissionAuditPlan.missing(
                fullDisk: fullDisk, accessibility: accessibility,
                needsFullDisk: needs.contains(.fullDisk),
                needsAccessibility: needs.contains(.accessibility))

            AppSettings.store.set(version, for: seenKey)
            guard !missing.isEmpty else { return }
            present(missing, firstRun: firstRun)
        }
    }

    /// One sheet naming everything that stopped working, and a button per
    /// pane. Two separate alerts in a row is how a person learns to dismiss
    /// them without reading.
    private static func present(_ missing: [PermissionNeed], firstRun: Bool) {
        let alert = NSAlert()
        // Named for the situation, not for one permission: the sheet is shown
        // for whichever ones lapsed, and titling it after Full Disk Access read
        // as nonsense when the missing one was Accessibility.
        alert.messageText = firstRun ? AppStr.permissionsNeeded : AppStr.permissionsChanged
        alert.informativeText = missing.map(AppStr.permissionReason).joined(separator: "\n\n")
        for need in missing { alert.addButton(withTitle: AppStr.openPane(need)) }
        alert.addButton(withTitle: AppStr.later)
        alert.alertStyle = .informational
        NSApp.activate()
        let chosen = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard chosen >= 0, chosen < missing.count else { return }
        missing[chosen].openSettings()
    }
}
