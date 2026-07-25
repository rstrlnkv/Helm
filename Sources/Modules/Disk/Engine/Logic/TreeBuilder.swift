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
                                 path: root, bytes: 0, isDirectory: true)
        self.index = [root: rootNode]
    }

    public func addFile(path: String, bytes: Int, fileID: UInt64, modified: TimeInterval = 0) {
        // A hard link's target is one allocation however many names it has.
        guard seenFileIDs.insert(fileID).inserted else { return }
        let parent = directory(for: (path as NSString).deletingLastPathComponent)
        if bytes < foldThreshold {
            foldedBucket(of: parent).bytes += bytes
        } else {
            parent.children.append(DiskNode(name: (path as NSString).lastPathComponent,
                                            path: path, bytes: bytes, isDirectory: false,
                                            modified: modified))
        }
        charge(bytes, upFrom: parent)
    }

    public func markNoAccess(path: String) {
        directory(for: path).noAccess = true
    }

    public func build() -> DiskNode { rootNode }

    // MARK: - Internals

    private func directory(for path: String) -> DiskNode {
        if let hit = index[path] { return hit }
        let parent = directory(for: (path as NSString).deletingLastPathComponent)
        let node = DiskNode(name: (path as NSString).lastPathComponent,
                            path: path, bytes: 0, isDirectory: true)
        parent.children.append(node)
        index[path] = node
        return node
    }

    private func foldedBucket(of parent: DiskNode) -> DiskNode {
        if let bucket = parent.children.first(where: { $0.name == "…" && !$0.isDirectory }) {
            return bucket
        }
        let bucket = DiskNode(name: "…", path: parent.path + "/…", bytes: 0, isDirectory: false)
        parent.children.append(bucket)
        return bucket
    }

    private func charge(_ bytes: Int, upFrom node: DiskNode) {
        var currentPath = node.path
        while let current = index[currentPath] {
            current.bytes += bytes
            if currentPath == rootPath { break }
            currentPath = (currentPath as NSString).deletingLastPathComponent
        }
    }
}
