import Foundation

/// One aggregated entry in the scanned tree. Reference type: a scan of a
/// large volume produces hundreds of thousands of these, and value-copying
/// whole subtrees on every mutation would dominate the scan.
///
/// **It holds the name, not the path.** A path is long enough to miss Swift's
/// small-string optimisation, so every node would pay a heap allocation for a
/// string it shares almost entirely with its parent.
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
    /// A flag, not the name `"…"`, which a person can give a real file. The gate
    /// judges no names; the bucket is kept out of the basket by this flag at the
    /// row, in `toggleBasket` and in `DiskRemovalPlan.question`, the last point
    /// before the paths are strings.
    public let isFolded: Bool
    /// Modification time as epoch seconds; 0 when the scanner had no date.
    public let modified: TimeInterval

    public init(name: String, bytes: Int, isDirectory: Bool,
                children: [DiskNode] = [], modified: TimeInterval = 0,
                isFolded: Bool = false, noAccess: Bool = false) {
        self.isFolded = isFolded
        self.noAccess = noAccess
        self.name = name
        self.bytes = bytes
        self.isDirectory = isDirectory
        self.children = children
        self.modified = modified
    }
}
