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
}
