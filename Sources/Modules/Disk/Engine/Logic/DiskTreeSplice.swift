import Foundation

/// Puts a freshly measured subtree back where it belongs.
///
/// A scan stops at a fixed depth — six levels, because the whole tree is held
/// in memory and written to a cache file, and depth costs both. Past it a
/// folder has no children, and a folder with no children cannot be opened: the
/// ring simply stopped six levels down, with no way to say so.
///
/// So the sixth level is measured on demand and grafted in here, and the path
/// the user was looking at stays valid.
public enum DiskTreeSplice {
    public static func replacing(_ path: String, with subtree: DiskEntry,
                                 in root: DiskEntry) -> DiskEntry {
        guard path != root.path else { return subtree }
        // Only walk the branch that contains it: a volume has hundreds of
        // thousands of nodes and all but one branch is untouched.
        guard path.hasPrefix(root.path == "/" ? "/" : root.path + "/") else { return root }
        return DiskEntry(name: root.name, path: root.path, bytes: root.bytes,
                         isDirectory: root.isDirectory, noAccess: root.noAccess,
                         children: root.children.map { child in
                             child.path == path ? subtree
                                 : replacing(path, with: subtree, in: child)
                         })
    }
}
