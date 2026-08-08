import Foundation

/// Where a path *leads*, which is the only thing a removal gate may judge.
///
/// `URL.standardizedFileURL` and `NSString.standardizingPath` collapse `.` and
/// `..` and stop there — they do not resolve symbolic links. `FileManager`'s
/// `trashItem` does follow them. That gap let a path be approved as
/// `~/Library/Caches/com.evil.app/taxes.pdf` and executed as
/// `~/Documents/taxes.pdf`: any process running as the user can create one of
/// the plug-in directories the leftovers scan enumerates — none of them exist
/// on a stock install — as a link to somewhere protected, and wait.
///
/// The **leaf is deliberately not resolved.** Trashing a symlink removes the
/// link and leaves its target alone, which is exactly what a person clearing a
/// stale alias asks for. It is an *ancestor* that redirects that makes the
/// spelling a lie, so only the parent chain is resolved.
///
/// This is the rule `WatchScope.canonical` already applies inside Autopilot,
/// written once here now that a second and third gate need it.
///
/// The trailing separator below is the same subject one layer down — not where
/// a path leads but which of several strings names the same place.
public enum PathCanonical {

    /// One folder, one spelling. `…/Ghost`, `…/Ghost/` and `…/Ghost//` are one
    /// place and three strings, and a batch that treats them as three answers
    /// three times for one folder.
    ///
    /// **Every** separator: a path joined onto a root that already ended in one
    /// carries two, and stripping a single one left `p` and `p//` different.
    /// The root is the one path that is nothing but a separator, and it keeps
    /// its own.
    public static func withoutTrailingSeparators(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    /// The path with every symlink in its parent chain resolved, and its last
    /// component put back untouched.
    ///
    /// A path that does not exist yet is still answered — the scan and the
    /// click are separated by however long the user takes — by resolving the
    /// deepest ancestor that does exist and re-appending the missing tail.
    public static func resolvingAncestors(_ path: String) -> String {
        // A relative path is handed back untouched. `URL(fileURLWithPath:)`
        // resolves one against the process's working directory, so resolving
        // first and validating afterwards silently promotes `""` and
        // `relative/path` to absolute paths a gate then approves — which is
        // exactly what happened the first time this was wired in. "Where does
        // it lead" is not a question a relative path has an answer to.
        guard path.hasPrefix("/") else { return path }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL
        guard standardized.path != "/" else { return standardized.path }

        let leaf = standardized.lastPathComponent
        var parent = standardized.deletingLastPathComponent()
        var missing: [String] = []
        while parent.path != "/", !FileManager.default.fileExists(atPath: parent.path) {
            missing.append(parent.lastPathComponent)
            parent = parent.deletingLastPathComponent()
        }
        var resolved = parent.resolvingSymlinksInPath().standardizedFileURL
        for component in missing.reversed() { resolved.appendPathComponent(component) }
        resolved.appendPathComponent(leaf)
        return resolved.path
    }
}
