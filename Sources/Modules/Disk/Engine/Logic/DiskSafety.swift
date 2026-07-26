import Foundation

/// What the basket is allowed to hold. The ring happily shows system storage,
/// but nothing there may be trashed: removing it breaks the machine, and the
/// module's whole value is that it is safe to poke around in.
public enum DiskSafety {
    static let protectedPrefixes = [
        "/System", "/Library/Apple", "/usr", "/bin", "/sbin", "/private/var/db",
        "/Volumes/Recovery", "/cores", "/opt/homebrew/Cellar",
    ]

    private static let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    public static func isRemovable(_ path: String) -> Bool {
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
}
