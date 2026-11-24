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

    /// Folded once, not per row: `isRemovable` runs on every frame the disk
    /// list redraws.
    private static let loweredPrefixes = protectedPrefixes.map { $0.lowercased() }
    private static let loweredHome = homePath.lowercased()

    public static func isRemovable(_ rawPath: String) -> Bool {
        // Judge the resolved path, not the spelling: "/Users/me/Documents/.."
        // is the home directory however it is written, and every check below
        // is a string test. This gate is the last word on deletion for Disk,
        // Duplicates and Autopilot, and on the one file Screenshots replaces.
        //
        // The absolute-path guard comes FIRST: `URL(fileURLWithPath:)` resolves
        // a relative path against the working directory, so resolving first
        // would turn "" and "relative/path" into paths this gate approves.
        let standardized = (rawPath as NSString).standardizingPath
        guard standardized.hasPrefix("/"), standardized != "/" else { return false }
        // Then symlinks, which `standardizingPath` does not resolve while
        // `trashItem` follows them: a link in an ordinary user folder pointing
        // at `/System/Library` gives a protected path a permitted spelling.
        // Only ancestors are resolved: trashing a stale alias must still
        // remove the alias (`PathCanonical`).
        let path = PathCanonical.resolvingAncestors(standardized)
        guard path.hasPrefix("/"), path != "/" else { return false }
        // The disk module's folded aggregate is told apart by a flag
        // (`DiskNode.isFolded`), never by a name here: `…` is a name a person
        // can type.
        //
        // Both spellings. For a path that **exists on disk**
        // `standardizingPath` rewrites `/private/var/…` to `/var/…`, which
        // would take `/private/var/db` out from under its own prefix; a test
        // with a path that does not exist cannot see it. `/private` is not a
        // firmlink, so a scan of the volume walks it and the row reaches the
        // basket.
        //
        // Folded, too: the boot volume is case-insensitive and
        // `standardizingPath` resolves `..`, `~` and `/private` but never case,
        // so `/USR/bin` and `/system/Library/CoreServices` are those
        // directories to the filesystem and strangers to a prefix test.
        let lowered = path.lowercased()
        let bare = PathCanonical.withoutPrivate(lowered)
        let spellings = [bare, "/private" + bare]
        guard !loweredPrefixes.contains(where: { prefix in
            spellings.contains { $0 == prefix || $0.hasPrefix(prefix + "/") }
        }) else { return false }
        // Never the user's whole home or a volume root.
        guard lowered != loweredHome,
              !lowered.hasPrefix("/volumes/") || path.split(separator: "/").count > 2
        else { return false }
        // Never a top-level directory of the boot volume either: the named list
        // above cannot keep up (`/Users`), and nothing at the root of a volume
        // is a file someone means to delete. Their contents still are.
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
