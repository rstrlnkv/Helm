import Foundation

/// One thing a scan found, in the two facts every module can answer for.
///
/// Deliberately thin. A module's own result type knows about duplicate groups,
/// or app bundles, or directory trees; this is what the journal stores and what
/// two scans can be compared on. A richer per-module file lives beside it.
public struct ScanItem: Codable, Equatable, Hashable, Sendable {
    public let path: String
    /// What acting on this item would return.
    public let bytes: Int

    public init(path: String, bytes: Int) {
        self.path = path
        self.bytes = bytes
    }
}

/// What changed between two scans of the same module.
public struct ScanChange: Equatable, Sendable {
    /// In the newer list and not the older one, in the newer list's order.
    public let appeared: [ScanItem]
    /// In the older list and not the newer one.
    public let went: [ScanItem]
    /// In both, unchanged.
    public let stayed: [ScanItem]
    /// False when this is the first scan the module ever ran. A page must not
    /// draw "since last time" against a previous scan that does not exist.
    public let hadPrevious: Bool

    public var appearedBytes: Int { appeared.reduce(0) { $0 + $1.bytes } }
    public var wentBytes: Int { went.reduce(0) { $0 + $1.bytes } }
    public var stayedBytes: Int { stayed.reduce(0) { $0 + $1.bytes } }

    /// Whether there is anything to say. A journal row reading "nothing changed"
    /// is worth drawing; a *delta* reading "+0, −0" is noise.
    public var isSomething: Bool { !appeared.isEmpty || !went.isEmpty }
}

/// Comparing two lists of what a scan found.
///
/// Pure, so the interesting cases — a file that changed size, a first scan, a
/// list with a repeated path — are tested without a filesystem.
public enum ScanComparison {

    /// - Parameter previous: nil when the module has never scanned before, which
    ///   is a different thing from an empty list. An empty list means the scan
    ///   ran and found nothing, so something present now really did appear.
    ///
    /// **Identity is the path *and* the size.** A file whose size changed is
    /// reported as both gone and appeared rather than as unchanged: something
    /// happened to it, the old bytes leave the total and the new ones enter it,
    /// and calling that "stayed" would be wrong about the only quantity this
    /// measures.
    public static func between(previous: [ScanItem]?, current: [ScanItem]) -> ScanChange {
        let before = Set(previous ?? [])
        let after = Set(current)
        // Both sides de-duplicated, and by the same rule. `went` came from the
        // set and said so; `appeared` and `stayed` were plain filters over the
        // array, so one repeated entry in the newer list was counted twice in
        // `appearedBytes` while the identical shape in the older list was not.
        // One structure handled two ways is a rule somebody has to remember.
        //
        // The order of first appearance is kept: a page listing what appeared
        // must not reshuffle between two draws of the same data.
        var seen: Set<ScanItem> = []
        let once = current.filter { seen.insert($0).inserted }
        return ScanChange(
            appeared: once.filter { !before.contains($0) },
            // From the set, so a previous list carrying the same entry twice
            // does not report one departure twice. Sorted, because a set has no
            // order and a page redrawing the same data must not reshuffle it.
            went: before.subtracting(after).sorted { $0.path < $1.path },
            stayed: once.filter { before.contains($0) },
            hadPrevious: previous != nil)
    }
}
