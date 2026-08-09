import Foundation

/// The step between what the person picked and what the Trash is asked for.
///
/// A basket row is usually its own removal, and for a cache it is not: the row
/// names `~/Library/Caches` and the removal is everything inside it. The
/// expansion happens **here**, at the last moment before the engine, and not in
/// `DiskEngine.trash`, because it is the claim the advice made that is being
/// kept — an engine that expanded every basketed folder into its children would
/// be inventing an intention for somebody who picked a folder off the ring.
///
/// The gate is untouched by any of this. `DiskEngine.trash` still runs
/// `UserFileScope.partition` over whatever comes out of here, and `HelmTrash`
/// still has the last word (ARCHITECTURE.md § Removal scope).
public enum DiskRemovalPlan {

    /// The paths a basket really hands to the Trash, in the order it holds them.
    ///
    /// Duplicates are the engine's business — it already takes `Array(Set(…))`,
    /// and `HelmTrash` de-duplicates again for its own reasons.
    public static func targets(basket: [String], advice: [DiskAdvice]) -> [String] {
        basket.flatMap { path in
            advice.first { $0.path == path }?.targets.map(\.path) ?? [path]
        }
    }

    /// The advice that survives a removal, each shrunk to what is left of it.
    ///
    /// `~/Library/Caches` has hundreds of children and some belong to running
    /// applications, so a cache emptied *in part* is the normal outcome rather
    /// than the exception — and the row that stays behind has to say what is
    /// still there. An advice whose targets are all gone goes with them.
    ///
    /// One rule covers both shapes: an advice is spent when every target is.
    /// For everything but a cache that is the single target `path`, which is
    /// the rule the view model carried before targets existed.
    public static func remaining(_ advice: [DiskAdvice], after removed: [String]) -> [DiskAdvice] {
        guard !removed.isEmpty else { return advice }
        return advice.compactMap { item in
            let left = item.targets.filter { !isGone($0.path, removed) }
            guard !left.isEmpty else { return nil }
            return DiskAdvice(name: item.name, path: item.path, kind: item.kind,
                              modified: item.modified, targets: left)
        }
    }

    /// Gone with the batch: taken itself, or taken along with a folder above it.
    private static func isGone(_ path: String, _ removed: [String]) -> Bool {
        removed.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
