import Foundation

/// Re-finds a drill-down path inside a fresh tree. Partial snapshots and
/// rescans replace the whole tree; without this the user is yanked back to
/// the root every 0.35s while the ring grows under them.
public enum DiskFocus {
    public static func resolve(paths: [String], in root: DiskEntry) -> [DiskEntry] {
        var out = [root]
        for path in paths.dropFirst() {
            guard let next = out.last?.children.first(where: { $0.path == path })
            else { break }
            out.append(next)
        }
        return out
    }

    /// The chain from `focus` down to `path`, excluding the focus itself.
    ///
    /// The ring draws three levels at once, so a click can land on a grandchild
    /// — and drilling used to accept only a direct child, which meant those
    /// outer arcs were painted, hoverable, and did nothing. Returning the whole
    /// chain keeps the breadcrumbs honest: jumping two levels still passes
    /// through the level in between.
    public static func chain(from focus: DiskEntry, to path: String) -> [DiskEntry] {
        guard path != focus.path else { return [] }
        for child in focus.children {
            if child.path == path { return [child] }
            // A prefix test alone would follow "/a/bc" into "/a/b"; the
            // separator is what makes it a descendant rather than a namesake.
            guard path.hasPrefix(child.path + "/") else { continue }
            let rest = chain(from: child, to: path)
            if !rest.isEmpty { return [child] + rest }
        }
        return []
    }
}
