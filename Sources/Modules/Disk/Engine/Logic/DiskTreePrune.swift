import Foundation

/// Applies a deletion to a scanned tree instead of re-measuring the disk.
/// A whole-volume scan takes a minute; the one thing a trash operation
/// changes is already known exactly — which paths went away and how big they
/// were — so the tree is rebuilt without them and the ancestors shrink by the
/// same amount.
public enum DiskTreePrune {
    public static func removing(paths: [String], from root: DiskEntry) -> DiskEntry {
        let gone = Set(paths)
        guard !gone.isEmpty, !gone.contains(root.path) else { return root }
        return prune(root, gone) ?? root
    }

    private static func prune(_ node: DiskEntry, _ gone: Set<String>) -> DiskEntry? {
        if gone.contains(node.path) { return nil }
        guard !node.children.isEmpty else { return node }
        let children = node.children.compactMap { prune($0, gone) }
        // Compare by value, not by count: a child can be rewritten (something
        // deeper inside it went away) while the count stays the same.
        guard children != node.children else { return node }
        // Only the removed children's bytes leave; whatever the parent held
        // beyond its listed children (folded buckets, unlisted remainder)
        // stays charged to it.
        let lost = node.children.reduce(0) { $0 + $1.bytes }
            - children.reduce(0) { $0 + $1.bytes }
        return DiskEntry(name: node.name, path: node.path, bytes: max(node.bytes - lost, 0),
                         isDirectory: node.isDirectory, noAccess: node.noAccess,
                         children: children)
    }
}
