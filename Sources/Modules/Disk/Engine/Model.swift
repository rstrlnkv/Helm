import Foundation

/// A volume offered on the start screen.
public struct VolumeInfo: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let totalBytes: Int
    public let freeBytes: Int
    public var usedBytes: Int { max(totalBytes - freeBytes, 0) }

    public init(name: String, path: String, totalBytes: Int, freeBytes: Int) {
        self.name = name; self.path = path
        self.totalBytes = totalBytes; self.freeBytes = freeBytes
    }
}

/// A tree flattened for transport — DiskNode is a reference type built during
/// the scan; the UI receives this immutable snapshot instead.
public struct DiskEntry: Codable, Equatable, Sendable, Identifiable {
    /// The path, and whether this is the bucket. They share one: the bucket's
    /// path is the path a real file called `…` would have, so `ForEach` drew
    /// one row for the two of them however carefully the tree kept them apart.
    /// A NUL cannot appear in a filename, so nothing real can collide with it.
    public var id: String { isFolded ? path + "\u{0}folded" : path }
    public let name: String
    public let path: String
    public let bytes: Int
    public let isDirectory: Bool
    public let noAccess: Bool
    public let children: [DiskEntry]
    /// The per-directory bucket the small files fold into, rather than a file.
    ///
    /// `DiskNode` gained this flag so a real file named `…` would stop being
    /// mistaken for the bucket — and the flag stopped at the engine boundary.
    /// This is the value that crosses to the screen, `id` is `path`, and the
    /// bucket's path is the one a real `…` file would have, so the two rows
    /// collapsed into one again on the other side. Optional for decoding: a
    /// scan cached by an earlier build has no such key.
    public let isFolded: Bool

    public init(name: String, path: String, bytes: Int, isDirectory: Bool,
                noAccess: Bool, children: [DiskEntry], isFolded: Bool = false) {
        self.name = name; self.path = path; self.bytes = bytes
        self.isDirectory = isDirectory; self.noAccess = noAccess; self.children = children
        self.isFolded = isFolded
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        bytes = try c.decode(Int.self, forKey: .bytes)
        isDirectory = try c.decode(Bool.self, forKey: .isDirectory)
        noAccess = try c.decode(Bool.self, forKey: .noAccess)
        children = try c.decode([DiskEntry].self, forKey: .children)
        isFolded = try c.decodeIfPresent(Bool.self, forKey: .isFolded) ?? false
    }
}

public struct ScanResult: Codable, Equatable, Sendable {
    public let root: DiskEntry
    public let freeBytes: Int
    public let filesScanned: Int
    public let seconds: Double
    /// Reclaim suggestions; computed once, on the final result only.
    public let advice: [DiskAdvice]

    public init(root: DiskEntry, freeBytes: Int, filesScanned: Int, seconds: Double,
                advice: [DiskAdvice] = []) {
        self.root = root; self.freeBytes = freeBytes
        self.filesScanned = filesScanned; self.seconds = seconds
        self.advice = advice
    }
}

public extension DiskEntry {
    /// Depth-limited snapshot: the UI never draws more than a few rings, and
    /// encoding a million-node tree would cost more than the scan itself.
    ///
    /// `path` is the path of `node` itself, which the caller knows — the scan
    /// root at the top, and a composed child's path further down. `DiskNode`
    /// stopped storing one because a full path per node cost ~345 MB on a large
    /// volume; the depth limit is what makes composing them cheap here, since
    /// only the few hundred nodes that reach the screen ever get a string.
    init(_ node: DiskNode, depth: Int, path: String) {
        self.init(name: node.name, path: path, bytes: node.bytes,
                  isDirectory: node.isDirectory, noAccess: node.noAccess,
                  children: depth <= 0 ? [] : node.children
                      .sorted { $0.bytes > $1.bytes }
                      .prefix(200)
                      .map { DiskEntry($0, depth: depth - 1,
                                       path: ScanPath.child(of: path, name: $0.name)) },
                  isFolded: node.isFolded)
    }
}
