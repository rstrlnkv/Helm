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
    public static func roots(home: String) -> [String] {
        ["\(home)/Library/Application Support/Helm",
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
