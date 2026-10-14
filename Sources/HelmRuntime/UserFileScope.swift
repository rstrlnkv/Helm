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

    /// Split once, not per row: `isRemovable` runs on every frame the disk
    /// list redraws.
    private static let protectedFolders = protectedPrefixes.map { PathCanonical.components(of: $0) }
    private static let homeFolder = PathCanonical.components(of: homePath)

    public static func isRemovable(_ rawPath: String) -> Bool {
        allows(PathCanonical.readingForRemoval(rawPath))
    }

    private static func allows(_ reading: PathCanonical.Reading) -> Bool {
        // Judge the one name the kernel gives what the string names, not the
        // spelling: a protected place is that place however it is written,
        // every check below is a string test, and this gate is the last word
        // on deletion for Disk, Duplicates and Autopilot, and on the one file
        // Screenshots replaces.
        //
        // The string goes to the reading as it came in. Nothing expands `~` or
        // folds `..` first, so a string that does not start at `/` has no name
        // and is refused, and so has one that begins with a prefix the kernel
        // answers itself, one whose way cannot be read, and one that ends in
        // `.` or `..`. A path through a link in an ordinary user folder that
        // points at `/System/Library` is named by where it leads; the link
        // itself is not followed — trashing a stale alias must still be allowed
        // to remove the alias (`PathCanonical.Reading` says what is asked, and
        // `readingForRemoval` in what order).
        guard let path = reading.judgedName else { return false }
        // **The bucket is a flag, never a name.** This used to refuse any path
        // ending in `/…`, because that was once the only way to recognise the
        // disk module's folded aggregate — and `…` is a name a person can type
        // and Finder accepts. Their own file was then drawn as a system item
        // with no basket button and no sentence saying why, in a gate whose
        // whole question is «does this belong to the user». The bucket is
        // `DiskNode.isFolded` now, all the way to `DiskEntry.isFolded` on the
        // wire, and it is told apart by the flag at the row, in the basket and
        // in `DiskRemovalPlan` — none of which can be typed into a filename.
        // Both spellings. The kernel names what is under `/var` with `/private`
        // in front, and the list holds `/private/var/db` beside `/usr`, so a
        // name is tested with the `/private` and without it and neither the
        // list nor the name has to be spelled one way.
        //
        // `/private` is not a firmlink, `/` and `/private/var/db` share a
        // device, so a scan of the volume walks it and the row reaches the
        // basket. This is the disk module's last word on deletion.
        //
        // Compared without regard to case, too, by component and not on a
        // lowered string: the name has the disk's case only for the levels
        // that are there, a tail that is not there and a last component that is
        // no directory keep the case they were typed in, and a place on the
        // list need not be on this Mac; `lowercased()` leaves a long s, U+017F,
        // alone, which the volume reads as `s` (`PathCanonical.isAtOrBelow`
        // says what is compared).
        //
        // Cut at the `/` byte (`PathCanonical.components` says why).
        let parts = PathCanonical.components(of: path)
        // `withoutPrivate` looks for `/private/` in that exact case, and that is
        // enough: the reading has given every level that is there the case the
        // disk holds, and `/private` is there, so `/PRIVATE/usr/bin` arrives
        // here as `/private/usr/bin`; a bare `/PRIVATE` has no component after
        // it to strip.
        let bare = PathCanonical.withoutPrivate(path)
        let spellings = [bare, "/private" + bare].map { PathCanonical.components(of: $0) }
        guard !protectedFolders.contains(where: { folder in
            spellings.contains { PathCanonical.isAtOrBelow($0, folder) }
        }) else { return false }
        // Never the user's whole home or a volume root.
        guard !(parts.count == homeFolder.count && PathCanonical.isAtOrBelow(parts, homeFolder)),
              !(parts.count == 2 && PathCanonical.isAtOrBelow(parts, ["Volumes"]))
        else { return false }
        // Never a top-level directory of the boot volume either. The named list
        // above cannot keep up: scan `/`, click the second-largest arc, and
        // `/Users` went into the basket. Nothing at the root of a volume is a
        // file someone means to delete — their contents still are.
        //
        // Counted without the `/private`: `/private/var` is where `/var`
        // leads, a top-level directory under the name the kernel gives it.
        guard spellings[0].count > 1 else { return false }
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

    /// The same split, answering what the gate read: for each path that may go,
    /// the `GatedPath` that `HelmTrash.remove(gated:)` moves, and for each that
    /// may not, the string asked with the reason (`GatedPath.gate`).
    static func gate(_ paths: [String])
    -> (allowed: [GatedPath], refused: [HelmTrash.Refusal]) {
        GatedPath.gate(paths, allowing: allows)
    }
}
