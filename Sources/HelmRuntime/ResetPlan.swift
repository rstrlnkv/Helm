// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// What "reset everything" is allowed to remove, and the gate that says so.
///
/// This is the one feature in Helm whose whole purpose is deletion, and what it
/// produces goes straight to `HelmTrash`. So the list and the gate are separate
/// and a test asserts they agree: a plan that named something its own gate
/// would refuse is the failure this pair exists to prevent.
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
        /// **The part that is not a path.** Helm changes exactly one thing
        /// outside its own two folders: the passwordless `pmset` rule Keep
        /// Awake's closed-lid option installs in `/etc/sudoers.d`, which is
        /// root's and can only come out through an administrator dialog. A reset
        /// that taught itself that filename would be the rule in the wrong
        /// place; it asks the engines instead, through the one call that means
        /// «the person is here and this is the last moment to ask»
        /// (`ModuleEngine.willDisable`). The answer can be *no* — a declined
        /// dialog leaves the rule exactly where it was — which is why this is
        /// asked rather than assumed, and why it is asked **first**, while the
        /// settings an engine decides with are still there.
        case handBackWhatIsOutsideHelm
        case trashHelmsOwnFolders
        case forgetPreferences
        case relaunch
    }

    /// The order, as a value. It was the shape of a function body, and what was
    /// missing from it was invisible for exactly that reason.
    public static let order: [Step] = [
        .handBackWhatIsOutsideHelm,
        .trashHelmsOwnFolders,
        .forgetPreferences,
        .relaunch,
    ]

    public static func roots(home: String) -> [String] {
        [HelmSupport.path(home: home),
         "\(home)/Library/Logs/Helm"]
    }

    /// What a reset removes, in the order it removes them.
    public static func removablePaths(home: String) -> [String] { roots(home: home) }

    /// Whether a reset may touch this path at all.
    public static func mayRemove(_ path: String, home: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        return roots(home: home).contains {
            standardized == $0 || standardized.hasPrefix($0 + "/")
        }
    }
}
