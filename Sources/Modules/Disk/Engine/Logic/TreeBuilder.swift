import Foundation

/// Accumulates scan results into a DiskNode tree. Pure bookkeeping — the
/// scanner feeds it paths and sizes; nothing here touches the filesystem.
public final class TreeBuilder: @unchecked Sendable {
    private let rootPath: String
    private let rootNode: DiskNode
    /// Files below this many bytes fold into a per-directory "…" bucket so a
    /// million-file scan does not allocate a million nodes.
    private let foldThreshold: Int
    private var seenFileIDs: Set<UInt64> = []
    private var index: [String: DiskNode]

    public init(root: String, foldThreshold: Int) {
        self.rootPath = root
        self.foldThreshold = foldThreshold
        self.rootNode = DiskNode(name: (root as NSString).lastPathComponent,
                                 bytes: 0, isDirectory: true)
        self.index = [root: rootNode]
    }

    public func addFile(path: String, bytes: Int, fileID: UInt64, modified: TimeInterval = 0) {
        // A hard link's target is one allocation however many names it has.
        //
        // 0 is not an id — it is the absence of one. `DiskScanner.readDirectory`
        // leaves it there when the filesystem does not return `ATTR_CMN_FILEID`,
        // and treating that as an id like any other means the first such file is
        // counted and every later one is dropped from the tree *and* from the
        // totals. Nobody could name a volume that withholds the attribute, so
        // this is a guard rather than a fix: an unknown id deduplicates nothing.
        guard fileID != 0 else { insert(path: path, bytes: bytes, modified: modified); return }
        guard seenFileIDs.insert(fileID).inserted else { return }
        insert(path: path, bytes: bytes, modified: modified)
    }

    private func insert(path: String, bytes: Int, modified: TimeInterval) {
        let parentPath = (path as NSString).deletingLastPathComponent
        guard let parent = directory(for: parentPath) else { return }
        if bytes < foldThreshold {
            foldedBucket(of: parent).bytes += bytes
        } else {
            parent.children.append(DiskNode(name: (path as NSString).lastPathComponent,
                                            bytes: bytes, isDirectory: false,
                                            modified: modified))
        }
        charge(bytes, from: parentPath)
    }

    public func markNoAccess(path: String) {
        directory(for: path)?.noAccess = true
    }

    public func build() -> DiskNode { rootNode }

    // MARK: - Internals

    /// nil for a path that does not descend from the scan root.
    ///
    /// The walk up had no base case but finding the root in the index, and
    /// `/`'s parent is `/` — so one path from outside the root recursed until
    /// the stack was gone. Every caller descends from the root, which is why
    /// nobody has seen it. Nothing is invented on the way out either: charging
    /// a stray path to the root would trade the crash for a folder that was
    /// never scanned marking the whole volume unreadable.
    private func directory(for path: String) -> DiskNode? {
        if let hit = index[path] { return hit }
        let above = (path as NSString).deletingLastPathComponent
        guard above != path, !above.isEmpty, let parent = directory(for: above) else {
            return nil
        }
        let node = DiskNode(name: (path as NSString).lastPathComponent,
                            bytes: 0, isDirectory: true)
        parent.children.append(node)
        index[path] = node
        return node
    }

    private func foldedBucket(of parent: DiskNode) -> DiskNode {
        if let bucket = parent.children.first(where: \.isFolded) {
            return bucket
        }
        let bucket = DiskNode(name: "…", bytes: 0, isDirectory: false, isFolded: true)
        parent.children.append(bucket)
        return bucket
    }

    /// Walks up by trimming the path rather than by following a parent
    /// reference, which is what it always did — the index is keyed by path and
    /// holds directories only, so this never needed the node to know its own.
    private func charge(_ bytes: Int, from directoryPath: String) {
        var currentPath = directoryPath
        while let current = index[currentPath] {
            current.bytes += bytes
            if currentPath == rootPath { break }
            currentPath = (currentPath as NSString).deletingLastPathComponent
        }
    }
}
