import AppKit
import HelmRuntime

/// Checks what Helm needs from macOS the first time it runs, and says so once.
/// Discovered the hard way: without Full Disk Access an uninstall silently
/// leaves app containers on disk.
@MainActor enum PermissionAudit {
    /// Set by the app delegate so the audit can ask which modules are on.
    static var host: ModuleHost!

    /// Holds the **identity** of the build that last showed the notice — not a
    /// bare flag, and no longer its marketing version.
    ///
    /// **The key string is historical and must not be renamed.** A fresh key
    /// reads as an empty last-seen value, `PermissionAuditPlan.shouldSpeak` is
    /// silent on a first run by design, and the run that needs this audit most
    /// is the first one after an update — so a rename would switch the audit off
    /// on exactly the launch it exists for, and nothing would report it. What
    /// changes is the value's shape, from `0.11.1-dev.5` to a cdhash: those
    /// compare unequal once, on the first launch of the first build that reads
    /// it, and that launch really is a different binary, so speaking then is
    /// correct rather than a glitch. `ThePermissionAuditAsksTheSignatureTests`
    /// holds the spelling and the fact that it is not on
    /// `ObsoleteDefaults.retired`, which really deletes.
    static let identityKey = "permissionAuditVersion"

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

            // The cdhash, not `AppBuild.shortVersion`: TCC ties an ad-hoc
            // grant to the bytes, and two builds of one version are two
            // programs to it and one program to the string.
            let identity = AppBuild.codeFingerprint ?? ""
            if identity.isEmpty, AppBuild.isBundledApp {
                // Silence with a reason. Without a signature there is nothing
                // to compare, so this audit can never speak on this bundle —
                // which is a thing to be able to read in the log rather than
                // to deduce from an alert that never came.
                HelmLog.shared.info("permissions",
                                    "no code signature to compare: the audit stays silent")
            }
            let lastSeen = AppSettings.store.string(identityKey, default: "")
            // Recorded on a first run too: the audit has nothing to compare
            // against yet, but the second run needs this as its baseline. Not
            // recorded when it could not be read — see `baseline`.
            if let record = PermissionAuditPlan.baseline(current: identity) {
                AppSettings.store.set(record, for: identityKey)
            }
            guard PermissionAuditPlan.shouldSpeak(
                lastSeenIdentity: lastSeen, current: identity) else { return }

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
