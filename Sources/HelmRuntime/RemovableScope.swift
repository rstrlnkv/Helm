import Foundation

/// The paths an app-cleanup module is allowed to put in the Trash.
///
/// Every module already decides what to *offer* — `LeftoverActions`,
/// `UninstallPlan`, `StaleItem.removable`. Those gates live in view models, and
/// a view model is the wrong place for the last word: the engine takes a list
/// of strings and trashes them, so any defect upstream that produces a bad
/// string produces a deleted folder. The disk module learned this first and
/// re-checks `DiskSafety.isRemovable` inside the engine; this is the same
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
        // filesystem, which is what actually performs the removal.
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !resolved.hasSuffix("/"), resolved != "/" else { return false }
        for bad in forbidden where resolved == bad || resolved.hasPrefix(bad + "/") {
            return false
        }
        // An app bundle names itself: `.app` is a structure macOS defines, and
        // people keep apps in ~/Downloads, on external volumes and in Setapp's
        // folder as readily as in /Applications. Removing the bundle the user
        // pointed at is the module's entire job, so the rule is the forbidden
        // list above plus "not a top-level directory", not a fixed location.
        if resolved.hasSuffix(".app"),
           resolved.dropFirst().split(separator: "/").count >= 2 { return true }
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
