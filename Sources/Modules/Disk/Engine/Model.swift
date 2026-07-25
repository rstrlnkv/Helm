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
    public var id: String { path }
    public let name: String
    public let path: String
    public let bytes: Int
    public let isDirectory: Bool
    public let noAccess: Bool
    public let children: [DiskEntry]

    public init(name: String, path: String, bytes: Int, isDirectory: Bool,
                noAccess: Bool, children: [DiskEntry]) {
        self.name = name; self.path = path; self.bytes = bytes
        self.isDirectory = isDirectory; self.noAccess = noAccess; self.children = children
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
    init(_ node: DiskNode, depth: Int) {
        self.init(name: node.name, path: node.path, bytes: node.bytes,
                  isDirectory: node.isDirectory, noAccess: node.noAccess,
                  children: depth <= 0 ? [] : node.children
                      .sorted { $0.bytes > $1.bytes }
                      .prefix(200)
                      .map { DiskEntry($0, depth: depth - 1) })
    }
}
