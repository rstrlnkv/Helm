// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import HelmRuntime

/// Returns Helm to the state it is in just after installation.
///
/// The steps and their order are `ResetPlan.order`, and the first of them is not
/// a deletion: **Helm changes one thing outside its own two folders**, and the
/// only code that can take it back is the module that put it there. So the
/// engines are asked first, while their settings still exist and while there is
/// somebody at the screen to answer what the asking can raise. Then the saved
/// state on disk, then the diagnostics log, then every preference — the log is
/// worth keeping until the last moment, because if trashing the state fails the
/// reason is in a file that still exists.
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

    /// The steps are `ResetPlan.order` and the switch is exhaustive: a step
    /// added to the plan and not carried out here is a build error rather than
    /// a promise nothing keeps.
    static func run() {
        for step in ResetPlan.order {
            switch step {
            case .handBackWhatIsOutsideHelm: ModuleHost.shared.handBackSystemState()
            case .trashHelmsOwnFolders: trashHelmsOwnFolders()
            case .forgetPreferences: forgetPreferences()
            case .relaunch: relaunch()
            }
        }
    }

    private static func trashHelmsOwnFolders() {
        let home = NSHomeDirectory()
        let paths = ResetPlan.removablePaths(home: home)
            .filter { ResetPlan.mayRemove($0, home: home) }
            .filter { FileManager.default.fileExists(atPath: $0) }

        let result = HelmTrash.remove(allowed: paths, module: "reset")
        HelmLog.shared.info("reset",
                            "removed \(result.removed.count), refused \(result.refused.count)")
    }

    /// Last of the removals, because until now the log was worth having.
    private static func forgetPreferences() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
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
