import Foundation

/// One aggregated entry in the scanned tree. Reference type: a scan of a
/// large volume produces hundreds of thousands of these, and value-copying
/// whole subtrees on every mutation would dominate the scan.
public final class DiskNode: @unchecked Sendable {
    public let name: String
    public let path: String
    public internal(set) var bytes: Int
    public let isDirectory: Bool
    public internal(set) var children: [DiskNode]
    /// Set when unreadable (no permission): counted at zero, shown flagged.
    public internal(set) var noAccess = false
    /// Modification time as epoch seconds; 0 when the scanner had no date.
    public let modified: TimeInterval

    public init(name: String, path: String, bytes: Int, isDirectory: Bool,
                children: [DiskNode] = [], modified: TimeInterval = 0) {
        self.name = name
        self.path = path
        self.bytes = bytes
        self.isDirectory = isDirectory
        self.children = children
        self.modified = modified
    }
}
