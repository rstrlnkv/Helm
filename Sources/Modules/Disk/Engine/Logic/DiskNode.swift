import Foundation

/// One aggregated entry in the scanned tree. Reference type: a scan of a
/// large volume produces hundreds of thousands of these, and value-copying
/// whole subtrees on every mutation would dominate the scan.
///
/// **It holds the name, not the path.** Measured over 1.5M nodes with realistic
/// paths, the name alone cost 92 MB against 437.6 MB for the pair — a path is
/// long enough to miss Swift's small-string optimisation, so every node paid a
/// heap allocation for a string it shares almost entirely with its parent.
///
/// The path is composed by whoever needs one, on the way down: `DiskEntry`'s
/// snapshot, `DiskAdvisor`'s sweep and `RingLayout` all descend from a known
/// root and hand each child `ScanPath.child(of:name:)`. That keeps live path
/// strings proportional to the depth of the walk rather than the size of the
/// tree, and it is why those traversals recurse instead of holding a stack of
/// pending siblings. `DerivedPathTests` pins the strings that come out.
public final class DiskNode: @unchecked Sendable {
    public let name: String
    public internal(set) var bytes: Int
    public let isDirectory: Bool
    public internal(set) var children: [DiskNode]
    /// Set when unreadable (no permission): counted at zero, shown flagged.
    public internal(set) var noAccess = false
    /// The per-directory bucket the small files fold into, rather than a file.
    ///
    /// It used to be recognised by its name — `"…"` and not a directory — which
    /// is also a description of a file somebody can create. That file then
    /// absorbed every small file beside it, showed a size that was not its own,
    /// and could not be selected, because `UserFileScope` refuses a path ending
    /// in `/…`. A flag cannot be typed into a filename.
    public let isFolded: Bool
    /// Modification time as epoch seconds; 0 when the scanner had no date.
    public let modified: TimeInterval

    public init(name: String, bytes: Int, isDirectory: Bool,
                children: [DiskNode] = [], modified: TimeInterval = 0,
                isFolded: Bool = false) {
        self.isFolded = isFolded
        self.name = name
        self.bytes = bytes
        self.isDirectory = isDirectory
        self.children = children
        self.modified = modified
    }
}
