import Foundation
import HelmRuntime
import HelmUI
import Module_Disk_Engine

// MARK: - Basket

/// The basket, and the removal it feeds. Same type as `DiskViewModel.swift`:
/// the fields this half writes are internal there for this reader, and `busy`
/// stays there because an extension cannot hold storage.
extension DiskViewModel {

    /// Whether the basket may hold this row.
    ///
    /// Here rather than in the page because the row draws its basket button from
    /// this and `toggleBasket` acts on it: two spellings is how a button comes to
    /// stand over a row the basket will quietly decline.
    ///
    /// **The folded bucket is refused by its flag.** It is the one row on the
    /// ring whose path names no file, an aggregate of the small files in a
    /// directory wearing the name `…`. A person's own file may carry that name;
    /// the flag cannot be typed into a filename.
    func canBasket(_ entry: DiskEntry) -> Bool {
        !entry.isFolded && UserFileScope.isRemovable(entry.path)
    }

    /// **The basket does not move while a removal is in flight.**
    ///
    /// `emptyBasket` sends what is ticked, waits, and then empties the basket
    /// wholesale, so a row ticked in between would be silently discarded, and
    /// one unticked would still be named in the report.
    ///
    /// The guard is here as well as on the button (`.disabled(dvm.busy)` in
    /// `DiskResultView`) because (Architecture/Removal.md § One removal at a time) asks
    /// for both: the page is a redraw away, and the bar's menu calls this too.
    func toggleBasket(_ entry: DiskEntry) {
        guard !busy else { return }
        if let index = basket.firstIndex(where: { $0.path == entry.path }) {
            basket.remove(at: index)
        } else if canBasket(entry) {
            basket.append(entry)
        }
    }

    func isBasketed(_ entry: DiskEntry) -> Bool {
        basket.contains { $0.path == entry.path }
    }

    /// What a press would really do — the list the engine is handed, its total,
    /// and the paths the confirmation names.
    ///
    /// One row in the basket is not always one removal: a cache row names a
    /// folder macOS will not part with and stands for everything inside it. The
    /// question the person answers is asked of *this*, not of the basket, so the
    /// dialog cannot describe a different act from the one it starts.
    var removalQuestion: DiskRemovalPlan.Question {
        DiskRemovalPlan.question(basket: basket, advice: result?.advice ?? [])
    }

    func emptyBasket() async {
        // The gate is unchanged — the engine partitions whatever comes out of
        // here and `HelmTrash` still has the last word.
        let paths = removalQuestion.paths
        guard !paths.isEmpty, !closed else { return }
        // **One removal at a time.** The basket is not emptied until the answer
        // comes back, so a second press would send the same paths again; it
        // would refuse each one and overwrite the report of the removal that worked.
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let removal = await work.trash(paths)
        failures = removal.refused
        removedCount = removal.removed.count
        banner = DkStr.movedToTrash(Bytes(removal.freedBytes))
        basket = []
        // The deletion is applied to the tree in hand: a re-walk to learn what
        // is already known costs a minute on a full volume.
        let removed = removal.removed
        guard let previous = result, !removed.isEmpty else { return }
        let pruned = DiskTreePrune.removing(paths: removed, from: previous.root)
        // Free space stays as measured: `HelmTrash` moved these paths to
        // `~/.Trash` on this same volume, so the disk gained nothing. What the
        // volume *uses* falls by what left, which pruning the tree shows.
        let updated = ScanResult(root: pruned, freeBytes: previous.freeBytes,
                                 filesScanned: previous.filesScanned, seconds: previous.seconds,
                                 advice: DiskRemovalPlan.remaining(previous.advice,
                                                                   after: removed))
        result = updated
        // An unfinished tree is not written down: every directory in it reports
        // a floor, and the store is what the module reopens on as "measured".
        if treeIsComplete {
            store.saveDetached(updated, at: completedAt ?? Date())
        }
        focusPath = DiskFocus.resolve(paths: focusPath.map(\.path), in: pruned)
        recomputeSegments()
    }
}
