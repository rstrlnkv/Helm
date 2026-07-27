import Foundation

/// What the basket is allowed to hold. The ring happily shows system storage,
/// but nothing there may be trashed: removing it breaks the machine, and the
/// module's whole value is that it is safe to poke around in.
public enum UserFileScope {
    static let protectedPrefixes = [
        "/System", "/Library/Apple", "/usr", "/bin", "/sbin", "/private/var/db",
        "/Volumes/Recovery", "/cores", "/opt/homebrew/Cellar",
    ]

    private static let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    public static func isRemovable(_ rawPath: String) -> Bool {
        // Judge the resolved path, not the spelling. "/Users/me/Documents/.."
        // is the home directory however it is written, and every check below
        // is a string test — RemovableScope standardizes for exactly this
        // reason, and this gate is the disk module's last word on deletion.
        let path = (rawPath as NSString).standardizingPath
        guard path.hasPrefix("/"), path != "/" else { return false }
        // A folded "…" bucket is an aggregate, not a real path.
        guard !path.hasSuffix("/…") else { return false }
        guard !protectedPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") })
        else { return false }
        // Never the user's whole home or a volume root. Resolved once — this
        // runs per row on every frame the disk list redraws.
        let home = homePath
        guard path != home, !path.hasPrefix("/Volumes/") || path.split(separator: "/").count > 2
        else { return false }
        // Never a top-level directory of the boot volume either. The named list
        // above cannot keep up: scan `/`, click the second-largest arc, and
        // `/Users` went into the basket. Nothing at the root of a volume is a
        // file someone means to delete — their contents still are.
        guard path.split(separator: "/").count > 1 else { return false }
        return true
    }

    /// Splits a batch into what may be trashed and what may not, so the caller
    /// reports the refusals instead of silently dropping them. Same shape as
    /// `RemovableScope.partition`, which guards a different question: that one
    /// asks what belongs to an app, this one what belongs to the user.
    public static func partition(_ paths: [String]) -> (allowed: [String], refused: [String]) {
        var allowed: [String] = [], refused: [String] = []
        for path in paths {
            if isRemovable(path) { allowed.append(path) } else { refused.append(path) }
        }
        return (allowed, refused)
    }
}
