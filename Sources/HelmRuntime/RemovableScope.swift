import Foundation

/// The paths an app-cleanup module is allowed to put in the Trash.
///
/// Every module already decides what to *offer* — `LeftoverActions`,
/// `UninstallPlan`, `StaleItem.removable`. Those gates live in view models, and
/// a view model is the wrong place for the last word: the engine takes a list
/// of strings and trashes them, so any defect upstream that produces a bad
/// string produces a deleted folder. The disk module learned this first and
/// re-checks `UserFileScope.isRemovable` inside the engine; this is the same
/// discipline for the modules that remove an app's belongings.
///
/// The rule is positional, not a blocklist: a path is removable only if it sits
/// strictly inside one of the folders an app is allowed to leave things in.
/// Anything else — `~/Documents`, a home directory, a volume root, `/System` —
/// is refused whether or not anyone thought to name it.
public enum RemovableScope {
    /// Directories whose *contents* belong to individual apps. The directory
    /// itself is never removable, only something inside it.
    private static func roots(home: String) -> [String] {
        [
            home + "/Library",
            home + "/Applications",
            "/Applications",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/Application Support",
            "/Library/Caches",
            "/Library/Logs",
            "/Library/Preferences",
            "/Library/PrivilegedHelperTools",
            "/Library/Extensions",
            "/Library/Internet Plug-Ins",
            "/Library/Audio/Plug-Ins",
        ]
    }

    /// Inside an allowed root but still off-limits: Apple's own files, which no
    /// third-party uninstall has any business touching.
    private static let forbidden = [
        "/Library/Apple",
        "/System",
        "/Applications/Utilities",
    ]

    public static func isRemovable(_ path: String,
                                   home: String = NSHomeDirectory()) -> Bool {
        // Resolve first: `..` is invisible to a prefix test but not to the
        // filesystem, which is what actually performs the removal — and neither
        // is a symlinked ancestor, which `standardizedFileURL` alone leaves in
        // place while `trashItem` follows it (PathCanonical says what that cost).
        let resolved = PathCanonical.resolvingAncestors(path)
        guard !resolved.hasSuffix("/"), resolved != "/" else { return false }
        for bad in forbidden where resolved == bad || resolved.hasPrefix(bad + "/") {
            return false
        }
        // **The positional refusals come first, above the `.app` clause.** That
        // clause returns `true` before any other test can run, so where it sits
        // decides what it exempts a path from: below these two it relaxes the
        // *roots list*, above them it relaxed the whole rule — and the rule this
        // gate states about itself is positional, not a blocklist. Measured
        // while it sat above: `/Volumes/Ext.app` was removable here and refused
        // by `UserFileScope`, which guards volume roots by name. Two gates
        // disagreeing about volume roots is the shape that once let Duplicates
        // offer every copy of a file.
        //
        // The first component is compared rather than the string folded:
        // `lowercased()` is full Unicode case folding, which changes the length
        // of some strings, and a prefix test against a different string is not a
        // prefix test.
        let parts = resolved.split(separator: "/")
        // Nothing at the top level of the boot volume is a file somebody means
        // to remove — their contents still are.
        guard parts.count > 1 else { return false }
        // A mounted volume's own root is the volume, not something on it.
        if parts.count == 2,
           parts[0].compare("Volumes", options: .caseInsensitive) == .orderedSame {
            return false
        }
        // An app bundle names itself: `.app` is a structure macOS defines, and
        // people keep apps in ~/Downloads, on external volumes and in Setapp's
        // folder as readily as in /Applications. Removing the bundle the user
        // pointed at is the module's entire job, so the rule is everything above
        // this line plus "it is a bundle", not a fixed location. It carried its
        // own copy of the depth test until the positional refusals moved above
        // it; one rule spelled twice is two rules waiting to disagree.
        if resolved.hasSuffix(".app") { return true }
        // `~/Library`'s own children are the shared folders — `Caches`,
        // `Application Support`, `Containers` — and an app owns something
        // *inside* one of them, never one of them. So that root needs two
        // components, the same depth `LeftoverMatcher` requires: the gate that
        // exists to survive a defect upstream must not be looser than the code
        // it is guarding. Every other root already names the shared folder, and
        // its children are the per-app files themselves.
        if resolved.hasPrefix(home + "/Library/") {
            return resolved.dropFirst(home.count + "/Library/".count).contains("/")
        }
        return roots(home: home).contains { resolved.hasPrefix($0 + "/") }
    }

    /// Splits a batch into what may be removed and what may not, so a caller can
    /// report the refusals rather than silently dropping them.
    public static func partition(_ paths: [String],
                                 home: String = NSHomeDirectory())
    -> (allowed: [String], refused: [String]) {
        var allowed: [String] = [], refused: [String] = []
        for path in paths {
            if isRemovable(path, home: home) { allowed.append(path) } else { refused.append(path) }
        }
        return (allowed, refused)
    }
}
