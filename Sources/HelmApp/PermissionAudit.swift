import AppKit
import HelmRuntime

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
            // This `Task` inherits the main actor from the enclosing type, so
            // the four blocking reads happened on the thread that draws, at
            // launch. `currentAccessibility` stays as it is: `AXIsProcessTrusted`
            // answers from a cache and touches no file.
            let fullDisk = await PermissionCheck.fullDiskAccess()
            let accessibility = PermissionCheck.currentAccessibility()
            // Logged every launch, not only the first: "it was granted
            // yesterday and is denied today" is the shape of the ad-hoc
            // signing problem, and only a line per launch shows it.
            HelmLog.shared.info("permissions",
                                "full disk access: \(fullDisk.rawValue), "
                                + "accessibility: \(accessibility.rawValue)")

            let version = AppBuild.shortVersion ?? ""
            let lastSeen = AppSettings.store.string(seenKey, default: "")
            // Recorded unconditionally, including on a first run: the audit
            // has nothing to compare against yet, but the second run needs
            // this as its baseline.
            AppSettings.store.set(version, for: seenKey)
            guard PermissionAuditPlan.shouldSpeak(
                lastSeenVersion: lastSeen, current: version) else { return }

            // Asked for only what an enabled module actually uses: a permission
            // request with no reason behind it is one people deny.
            let needs = ModuleRegistry.all
                .filter { host.isEnabled($0) }
                .flatMap { $0.currentPermissions() }
            let missing = PermissionAuditPlan.missing(
                fullDisk: fullDisk, accessibility: accessibility,
                needsFullDisk: needs.contains(.fullDisk),
                needsAccessibility: needs.contains(.accessibility))

            guard !missing.isEmpty else { return }
            present(missing)
        }
    }

    /// One sheet naming everything that stopped working, and a button per
    /// pane. Two separate alerts in a row is how a person learns to dismiss
    /// them without reading.
    private static func present(_ missing: [PermissionNeed]) {
        let alert = NSAlert()
        // Named for the situation, not for one permission: the sheet is shown
        // for whichever ones lapsed, and titling it after Full Disk Access read
        // as nonsense when the missing one was Accessibility.
        alert.messageText = AppStr.permissionsChanged
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
