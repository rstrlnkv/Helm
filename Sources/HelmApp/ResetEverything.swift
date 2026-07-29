// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import HelmRuntime

/// Returns Helm to the state it is in just after installation.
///
/// Three things go, in this order: the saved state on disk, the diagnostics
/// log, and every preference. The order matters only in that the log is worth
/// keeping until the last moment — if trashing the state fails, the reason is
/// in a file that still exists.
///
/// **To the Trash, not to `unlink`.** Everywhere else in Helm removal is
/// recoverable, and somebody who presses this by accident must be able to get
/// their Autopilot rules back. The one exception is preferences, which live in
/// `UserDefaults` and cannot be trashed — they are simply forgotten.
///
/// Helm does not and cannot revoke its own TCC grants; Full Disk Access and
/// Accessibility are macOS's to give and the person's to take back in System
/// Settings. Nothing here pretends otherwise.
@MainActor enum ResetEverything {
    static func run() {
        let home = NSHomeDirectory()
        let paths = ResetPlan.removablePaths(home: home)
            .filter { ResetPlan.mayRemove($0, home: home) }
            .filter { FileManager.default.fileExists(atPath: $0) }

        let result = HelmTrash.remove(allowed: paths, module: "reset")
        HelmLog.shared.info("reset",
                            "removed \(result.removed.count), refused \(result.refused.count)")

        // Last, because until now the log was worth having.
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }

        relaunch()
    }

    /// A fresh process, because half of what was just forgotten is held in
    /// memory by objects that read it once at launch — the module host, the
    /// status item, every view model. Reading them back would show the old
    /// state over the new nothing.
    private static func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
