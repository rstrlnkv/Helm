// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// What "reset everything" is allowed to remove, and the gate that says so.
///
/// This is the one feature in Helm whose whole purpose is deletion, and what it
/// produces goes straight to `HelmTrash`. So the plan is the gate's own root
/// list: `mayRemove` reads `removablePaths`, and `ResetPlanTests` pins that
/// list literally, so a plan the gate would refuse cannot exist.
///
/// **Only Helm's own two directories.** Not `~/Library/Application Support`,
/// not `~/Library/Logs`, not a sibling whose name merely starts the same way —
/// `mayRemove` requires the path to be one of the two roots or to sit beneath
/// one, compared against a standardized path so `Helm/../../Documents` cannot
/// walk out.
///
/// Preferences are not here: they live in `UserDefaults` and are removed by
/// domain, which is exact and has no path to get wrong.
public enum ResetPlan {

    /// What a reset does. Every case is a thing the promise «Helm returns to how
    /// it was just after installing» covers, and the enum is switched over
    /// exhaustively where it is carried out — a case added without an arm is a
    /// build error, never a step that silently never happens.
    public enum Step: CaseIterable, Sendable {
        /// **The part that is not a path.** The passwordless `pmset` rule Keep
        /// Awake's closed-lid option installs in `/etc/sudoers.d` is root's. It
        /// comes out silently when the rule permits its own withdrawal, and
        /// otherwise only through an administrator dialog. A reset that
        /// taught itself that filename would be the rule in the wrong place; it
        /// asks the engines instead, through the one call that means «the
        /// person is here and this is the last moment to ask»
        /// (`ModuleEngine.willDisable`). Asking is not being given — a declined
        /// dialog leaves the rule exactly where it was — which is why this is
        /// asked rather than assumed, and why it is asked **first**, while the
        /// settings an engine decides with are still there.
        case handBackWhatIsOutsideHelm

        /// **Registered by the application, not by a module.** `SMAppService`
        /// keeps the registration in a system database outside both of Helm's
        /// folders, so trashing folders and forgetting preferences leaves Helm
        /// opening at login — which is the one thing a person resetting an app
        /// notices the next morning. `ModuleEngine` has no channel to it and
        /// should not grow one: nothing a module owns registered this.
        ///
        /// Before `.forgetPreferences`, because unregistering reads
        /// `Bundle.main` and reports through the log, and after the engines,
        /// because their dialog is the step that needs the person.
        case giveBackTheLoginItem

        /// Every live module stopped, deactivated and its menu-bar item taken
        /// away, **before** the folders go to the Trash and the preferences are
        /// forgotten. A model stopping writes (the Screenshots bar's place), and
        /// a write after `.forgetPreferences` survives the reset: the quit's
        /// `shutdown()` used to be the one that ran it, too late.
        case stopEveryModule
        case trashHelmsOwnFolders

        /// The trash took the log folder, and the latch that says its purge
        /// already ran went with it. Written again before the relaunch so the
        /// next launch does not delete the log holding this reset's own line.
        case relatchTheLogPurge
        case forgetPreferences
        case relaunch
    }

    /// The order, as a value. It was the shape of a function body, and what was
    /// missing from it was invisible for exactly that reason.
    public static let order: [Step] = [
        .handBackWhatIsOutsideHelm,
        .giveBackTheLoginItem,
        .stopEveryModule,
        .trashHelmsOwnFolders,
        .relatchTheLogPurge,
        .forgetPreferences,
        .relaunch,
    ]

    /// What a reset removes, and the roots `mayRemove` judges against.
    /// `HelmTrash.remove` takes the shortest path first, so the logs folder goes
    /// before Application Support.
    /// `folder` is the build's own (`AppBuild.dataFolder`), so Helm Dev's reset
    /// can only reach Helm Dev's folders and never the real Helm's.
    static func removablePaths(home: String, folder: DataFolder) -> [String] {
        [HelmSupport.path(home: home, folder: folder),
         "\(home)/\(LogDestination.relativePath(folder: folder))"]
    }

    /// What a reset hands to the Trash for the process whose bundle id is
    /// `identifier`: its own build's paths, each through the gate. The one place the
    /// app layer gets them from, so a test with Helm Dev's id sees what Dev's reset does.
    public static func trashPaths(home: String, identifier: String?) -> [String] {
        let folder = DataFolder.of(identifier: identifier)
        return removablePaths(home: home, folder: folder)
            .filter { mayRemove($0, home: home, folder: folder) }
    }

    /// Whether a reset may touch this path at all.
    static func mayRemove(_ path: String, home: String, folder: DataFolder) -> Bool {
        let standardized = (path as NSString).standardizingPath
        return removablePaths(home: home, folder: folder).contains {
            standardized == $0 || standardized.hasPrefix($0 + "/")
        }
    }
}
