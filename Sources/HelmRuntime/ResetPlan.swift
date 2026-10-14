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
/// **Only Helm's own two folders, and the two the system keeps for it.** Its
/// Application Support directory and its `~/Library/Logs/Helm`, and the two
/// folders the system keeps for the running app under its bundle identifier:
/// `~/Library/Caches/<id>` and `~/Library/HTTPStorages/<id>`. Not
/// `~/Library/Application Support`, not `~/Library/Caches`, not a sibling whose
/// name merely starts the same way, and not the `Caches` or `HTTPStorages`
/// folder of another build: the identifier is the running app's, so Helm Dev
/// never names the real Helm's two. Helm's own two folders are not named by the
/// identifier and are the same folders for every build.
///
/// `mayRemove` judges the name the kernel gives what the path names
/// (`PathCanonical.readingForRemoval`) and requires it to be one of the four or
/// to sit beneath one, so `Helm/../../Documents` cannot walk out and a link on
/// the way is read where it leads. `gate` is the same judgement for
/// `HelmTrash.remove(gated:)`, which moves the name that was judged.
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
        /// Awake's closed-lid option installs in `/etc/sudoers.d` is root's and
        /// can only come out through an administrator dialog. A reset that
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
        case trashHelmsOwnFolders
        case forgetPreferences
        case relaunch
    }

    /// The order, as a value. It was the shape of a function body, and what was
    /// missing from it was invisible for exactly that reason.
    public static let order: [Step] = [
        .handBackWhatIsOutsideHelm,
        .giveBackTheLoginItem,
        .trashHelmsOwnFolders,
        .forgetPreferences,
        .relaunch,
    ]

    /// The folders a reset takes: Helm's two, and the two the system keeps for
    /// the app named by `bundleIdentifier`, which defaults to the running one.
    ///
    /// An identifier is one whole path component or it names nothing. A `nil`
    /// (a process with no bundle), an empty one, `.` and `..`, and one with a
    /// `/` byte or a byte below 0x20 or the byte 0x7f in it (NUL, a newline and
    /// DEL included) add no root: the plan is then Helm's two folders, and never
    /// `Caches` or `HTTPStorages` themselves, nor a folder that is not the one
    /// named.
    public static func roots(home: String,
                             bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> [String] {
        var roots = [HelmSupport.path(home: home),
                     "\(home)/Library/Logs/Helm"]
        if let id = bundleIdentifier, isOneComponent(id) {
            roots += ["\(home)/Library/Caches/\(id)",
                      "\(home)/Library/HTTPStorages/\(id)"]
        }
        return roots
    }

    /// What a reset hands the Trash: `roots`, with the same meaning of
    /// `bundleIdentifier`. The Trash moves a batch shortest name first, so this
    /// is not the order of the moves.
    public static func removablePaths(home: String,
                                      bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> [String] {
        roots(home: home, bundleIdentifier: bundleIdentifier)
    }

    /// Whether a reset may touch this path at all: whether the name the kernel
    /// gives it is one of `roots`, or below one. An identifier that names no
    /// folder (`roots` says which) leaves the answer to Helm's two.
    public static func mayRemove(_ path: String, home: String,
                                 bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> Bool {
        allows(PathCanonical.readingForRemoval(path),
               within: folders(home: home, bundleIdentifier: bundleIdentifier))
    }

    /// The same split `mayRemove` makes, answering what the gate read: for each
    /// path that may go, the `GatedPath` that `HelmTrash.remove(gated:)` moves,
    /// and for each that may not, the string asked with the reason
    /// (`GatedPath.gate`).
    static func gate(_ paths: [String], home: String,
                     bundleIdentifier: String? = Bundle.main.bundleIdentifier)
    -> (allowed: [GatedPath], refused: [HelmTrash.Refusal]) {
        let folders = folders(home: home, bundleIdentifier: bundleIdentifier)
        return GatedPath.gate(paths) { allows($0, within: folders) }
    }

    /// An identifier that is a single name in a folder: not empty, not `.` or
    /// `..`, no `/` byte, no byte below 0x20 and not the byte 0x7f, compared by
    /// bytes as the kernel reads a path (`PathCanonical.components` says why).
    private static func isOneComponent(_ id: String) -> Bool {
        !id.isEmpty && id != "." && id != ".."
            && !id.utf8.contains { $0 == PathCanonical.separator || $0 < 0x20 || $0 == 0x7f }
    }

    /// The roots as the kernel names them, once per question. A name the
    /// reading gives is the kernel's (`/private/var/…` for a home under `/var`),
    /// so the roots are named the same way and the two spellings of `/private`
    /// meet in one.
    private static func folders(home: String, bundleIdentifier: String?) -> [[Substring]] {
        roots(home: home, bundleIdentifier: bundleIdentifier)
            .map { PathCanonical.components(of: PathCanonical.reading(of: $0).name) }
    }

    private static func allows(_ reading: PathCanonical.Reading, within folders: [[Substring]]) -> Bool {
        guard let name = reading.judgedName else { return false }
        let parts = PathCanonical.components(of: name)
        return folders.contains { parts.starts(with: $0) }
    }
}
