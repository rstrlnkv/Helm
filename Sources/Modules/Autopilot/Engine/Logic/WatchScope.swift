import Foundation

/// Where a rule may watch, and where it may put things.
///
/// The module's own gate, and it exists because the shared ones answer a
/// different question. `RemovableScope` asks what belongs to an application;
/// `UserFileScope` asks what may be *trashed* without breaking the machine, and
/// that is a blocklist — it says yes to `~/Library/Safari`, to
/// `~/Library/LaunchAgents`, to `/Library/Preferences`, to another account's
/// home. For a module that trashes what a person selected on screen, that is
/// the right answer. For this one it is not, for two reasons:
///
/// **Helm holds Full Disk Access and the rules do not come from a person.**
/// They are JSON in `UserDefaults`, which any process running as the user can
/// write. Under `UserFileScope` a planted rule turns Helm into a file mover
/// with FDA: point a watched folder at `~/Library/Messages`, move to
/// `~/Downloads`, and the hourly sweep carries protected data out to where the
/// planter can read it — with nobody present, and without the Rules page ever
/// having been opened.
///
/// **`~/Library/LaunchAgents` is the user's own folder and is also arbitrary
/// code at login.** A rule that moves `.plist` files there is the script action
/// this module deliberately does not have. No gate that reasons only about
/// ownership can refuse it; this one refuses `~/Library` entirely.
///
/// So the rule here is positional and narrow: inside the home directory but not
/// the home directory itself, never inside `~/Library`, or inside a volume
/// under `/Volumes` — people do keep the folders they sort on an external disk.
/// Everything else is refused whether or not anyone thought to name it.
///
/// Symlinks are resolved first. A destination the person chose through the
/// panel can be replaced by a link afterwards, and the check has to be about
/// where a path *leads* rather than how it is spelled.
public enum WatchScope {

    public static func allows(_ rawPath: String,
                              home: String = NSHomeDirectory()) -> Bool {
        // Absolute first, before any resolution — the same opening guard, for
        // the same reason, as `UserFileScope.isRemovable` and
        // `ScanRoot.resolve`. `canonical` below builds a
        // `URL(fileURLWithPath:)`, which resolves a relative path against the
        // **process's working directory** and hands back something absolute, so
        // canonicalizing first answers the question this guard is asking:
        // measured with the working directory inside the home, `relative/path`
        // and `""` were both allowed, and with it at `/` both were refused. A
        // bundle launched by LaunchServices or launchd has `/`, which is why
        // this was latent rather than live — and a gate whose verdict depends on
        // how the program was started is not a gate.
        let standardized = (rawPath as NSString).standardizingPath
        guard standardized.hasPrefix("/"), standardized != "/" else { return false }

        let path = canonical(standardized)
        let home = canonical(home)

        guard path != "/", !path.hasSuffix("/") else { return false }

        if path.hasPrefix(home + "/") {
            // `~/Library` is where an application's own belongings live and
            // where login items are declared. Neither is anything a folder rule
            // should be reaching into.
            //
            // Without case, and that is the second guard rather than the first:
            // `canonical` fixes the spelling of every component that exists,
            // which on a real Mac is `Library` itself. It cannot fix one that
            // does not, and the deny side of a gate must not be the side that
            // depends on the filesystem happening to hold the folder.
            let library = home + "/Library"
            return !path.hasPrefix(library + "/", caseInsensitive: true)
                && path.compare(library, options: .caseInsensitive) != .orderedSame
        }

        // An external volume: `/Volumes/Disk` itself is the volume, so a rule
        // needs to name something inside it.
        if path.hasPrefix("/Volumes/") {
            return path.dropFirst("/Volumes/".count).contains("/")
        }

        return false
    }

    /// A path canonicalized as far as the filesystem can take it, including the
    /// part of it that does not exist yet.
    ///
    /// `resolvingSymlinksInPath` gives up on the *whole* path the moment one
    /// component is missing: it stops following links and stops fixing case for
    /// the components that do exist, not merely for the missing tail. A rule's
    /// destination is precisely the path that does not exist — "a rule that
    /// names a folder is asking for that folder to exist" — so the gate was
    /// reading destinations exactly as the plist spelled them, and the plist is
    /// writable by any process running as the user.
    ///
    /// What that cost: `~/library/Application Support/Sorted` passed the home
    /// test, missed `~/Library/` on case alone, and was allowed; the runner's
    /// `createDirectory(withIntermediateDirectories:)` then put it inside the
    /// real `~/Library` on a case-insensitive volume.
    ///
    /// So the deepest ancestor that does exist is resolved and the missing tail
    /// is put back on it.
    private static func canonical(_ rawPath: String) -> String {
        var url = URL(fileURLWithPath: rawPath).standardizedFileURL
        var missing: [String] = []
        while url.path != "/", !FileManager.default.fileExists(atPath: url.path) {
            missing.append(url.lastPathComponent)
            url = url.deletingLastPathComponent()
        }
        var resolved = url.resolvingSymlinksInPath().standardizedFileURL
        for component in missing.reversed() { resolved.appendPathComponent(component) }
        return resolved.path
    }
}

private extension String {
    /// `hasPrefix` that can be asked to ignore case. `lowercased()` on a path is
    /// not the same question — full Unicode case folding changes the length of
    /// some strings, and a prefix test on a different string is not a prefix
    /// test.
    func hasPrefix(_ prefix: String, caseInsensitive: Bool) -> Bool {
        range(of: prefix, options: caseInsensitive ? [.caseInsensitive, .anchored] : [.anchored])
            != nil
    }
}
