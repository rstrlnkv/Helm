import Foundation
import HelmRuntime

/// The step between what the person picked and what the Trash is asked for.
///
/// A basket row is usually its own removal, and for a cache it is not: the row
/// names `~/Library/Caches` and the removal is everything inside it. The
/// expansion happens **here** and not in `DiskEngine.trash`, because it keeps
/// the claim the advice made; a folder picked off the ring means the folder.
///
/// The gate is untouched by this. `DiskEngine.trash` still runs
/// `UserFileScope.partition` over whatever comes out of here (Architecture/Removal.md § Removal), and
/// `HelmTrash` still re-reads the path before each move (Architecture/TheGates.md § The gates).
public enum DiskRemovalPlan {

    /// What the confirmation is about.
    ///
    /// **Taken from the plan, never from the basket.** The two differ for a
    /// cache row by design (one row, everything inside the folder it names), and
    /// a confirmation must not misstate its own act.
    public struct Question: Equatable, Sendable {
        /// Exactly what the engine will be handed, in the order it will be.
        public let paths: [String]
        public let bytes: Int
        public var count: Int { paths.count }

        /// The paths as the dialog lists them: the home prefix shortened the way
        /// AppKit does it, capped, and an ellipsis only when something is really
        /// left out.
        ///
        /// Paths rather than the names the ring shows, and the reason is at the
        /// call site: "Library" alone could equally be `/Library` or `~/Library`,
        /// and one of those is the system's.
        public func named(limit: Int = 4) -> String {
            paths.prefix(limit).map { ($0 as NSString).abbreviatingWithTildeInPath }
                .joined(separator: "\n")
                + (paths.count > limit ? "\n…" : "")
        }
    }

    /// The question the person is answering.
    ///
    /// The paths are `targets` itself, the very list the press hands over. The
    /// size comes from the advice's own total, which `DiskAdvice` derives from
    /// those same targets.
    ///
    /// **A folded bucket never leaves here**, the last place that can tell:
    /// past this point is strings, and `UserFileScope` and `HelmTrash` see the
    /// path a real file named `…` would have. The row and the basket refuse it
    /// first.
    public static func question(basket: [DiskEntry], advice: [DiskAdvice]) -> Question {
        let named = basket.filter { !$0.isFolded }
        return Question(paths: targets(basket: named.map(\.path), advice: advice),
                        bytes: named.map { entry in
                            advice.first { $0.path == entry.path }?.bytes ?? entry.bytes
                        }.saturatingSum())
    }

    /// The paths a basket really hands to the Trash, in the order it holds them.
    ///
    /// Duplicates are the engine's business — it already takes `Array(Set(…))`,
    /// and `HelmTrash` de-duplicates again for its own reasons.
    static func targets(basket: [String], advice: [DiskAdvice]) -> [String] {
        basket.flatMap { path in
            advice.first { $0.path == path }?.targets.map(\.path) ?? [path]
        }
    }

    /// The advice that survives a removal, each shrunk to what is left of it.
    ///
    /// `~/Library/Caches` has hundreds of children and some belong to running
    /// applications, so a cache emptied *in part* is the normal outcome, and
    /// the row that stays behind says what is still there.
    ///
    /// One rule covers both shapes: an advice is spent when every target is.
    /// For everything but a cache that is the single target `path`.
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
