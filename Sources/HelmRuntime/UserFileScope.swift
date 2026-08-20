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
        // Judge the resolved path, not the spelling. "/Users/me/Documents/.."
        // is the home directory however it is written, and every check below
        // is a string test — RemovableScope standardizes for exactly this
        // reason, and this gate is the last word on deletion for Disk, Duplicates and Autopilot.
        //
        // The absolute-path guard comes FIRST, before any resolution: every
        // resolver here builds a `URL(fileURLWithPath:)`, which resolves a
        // relative path against the process's working directory and hands back
        // something absolute. Canonicalizing before the guard therefore turned
        // "" and "relative/path" into paths this gate approved — the guard was
        // asking a question that had already been answered for it.
        let standardized = (rawPath as NSString).standardizingPath
        guard standardized.hasPrefix("/"), standardized != "/" else { return false }
        // Then symlinks, which `standardizingPath` does not resolve while
        // `trashItem` follows them: a link in an ordinary user folder pointing
        // at `/System/Library` made a protected path wear a permitted spelling.
        // Only ancestors are resolved — trashing a stale alias must still be
        // allowed to remove the alias (PathCanonical says why).
        let path = PathCanonical.resolvingAncestors(standardized)
        guard path.hasPrefix("/"), path != "/" else { return false }
        // **The bucket is a flag, never a name.** This used to refuse any path
        // ending in `/…`, because that was once the only way to recognise the
        // disk module's folded aggregate — and `…` is a name a person can type
        // and Finder accepts. Their own file was then drawn as a system item
        // with no basket button and no sentence saying why, in a gate whose
        // whole question is «does this belong to the user». The bucket is
        // `DiskNode.isFolded` now, all the way to `DiskEntry.isFolded` on the
        // wire, and it is told apart by the flag at the row, in the basket and
        // in `DiskRemovalPlan` — none of which can be typed into a filename.
        // Both spellings. `standardizingPath` does more than drop `.` and `..`:
        // for a path that **exists on disk** it rewrites `/private/var/…` to
        // `/var/…`. So `/private/var/db` — the entry on the list — was rewritten
        // out from under its own prefix and let through, while
        // `/private/var/db/does-not-exist` was refused, because nothing rewrote
        // it. The old test used a path that does not exist and passed.
        //
        // `/private` is not a firmlink, `/` and `/private/var/db` share a
        // device, so a scan of the volume walks it and the row reaches the
        // basket. This is the disk module's last word on deletion.
        //
        // Folded, too: the boot volume is case-insensitive and
        // `standardizingPath` resolves `..`, `~` and `/private` but never case,
        // so `/USR/bin` and `/system/Library/CoreServices` are those
        // directories to the filesystem and strangers to a prefix test.
        let lowered = path.lowercased()
        let spellings = [lowered, lowered.hasPrefix("/private/") ? String(lowered.dropFirst("/private".count)) : "/private" + lowered]
        guard !loweredPrefixes.contains(where: { prefix in
            spellings.contains { $0 == prefix || $0.hasPrefix(prefix + "/") }
        }) else { return false }
        // Never the user's whole home or a volume root.
        guard lowered != loweredHome,
              !lowered.hasPrefix("/volumes/") || path.split(separator: "/").count > 2
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
