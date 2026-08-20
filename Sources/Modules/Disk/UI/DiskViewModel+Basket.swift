import Foundation
import HelmRuntime
import HelmUI
import Module_Disk_Engine

// MARK: - Basket

/// The basket, and the removal it feeds — split from `DiskViewModel.swift`
/// when that file reached the linter's length limit. Same type, one file over:
/// the fields this half writes are `internal(set)` there for exactly this
/// reader, and `busy` stays there because an extension cannot hold storage.
extension DiskViewModel {

    /// Whether the basket may hold this row.
    ///
    /// Here rather than in the page because the row draws its basket button from
    /// this and `toggleBasket` acts on it: two spellings is how a button comes to
    /// stand over a row the basket will quietly decline.
    ///
    /// **The folded bucket is refused by its flag.** It is the one row on the
    /// ring whose path names no file — an aggregate of the small files in a
    /// directory, wearing the name `…` — and the gate used to keep it out by
    /// refusing that name, which refused the person's own file of the same name
    /// with it, drawn as a system item with nothing saying why. The flag is what
    /// the two differ by, and it cannot be typed into a filename.
    func canBasket(_ entry: DiskEntry) -> Bool {
        !entry.isFolded && UserFileScope.isRemovable(entry.path)
    }

    /// **The basket does not move while a removal is in flight.**
    ///
    /// `emptyBasket` sends what is ticked, waits, and then empties the basket
    /// wholesale — so a row ticked in between was accepted and then discarded:
    /// never sent, never refused, never mentioned, and still sitting on the ring
    /// afterwards. Unticking one in the meantime is the mirror image, and worse
    /// to read: the report then names a folder the person had just withdrawn.
    ///
    /// The guard is here as well as on the button (`.disabled(dvm.busy)` in
    /// `DiskResultView`) because ARCHITECTURE.md § One removal at a time asks
    /// for both — the page is a redraw away, and this method is also what the
    /// bar's menu calls.
    public func toggleBasket(_ entry: DiskEntry) {
        guard !busy else { return }
        if let index = basket.firstIndex(where: { $0.path == entry.path }) {
            basket.remove(at: index)
        } else if canBasket(entry) {
            basket.append(entry)
        }
    }

    public func isBasketed(_ entry: DiskEntry) -> Bool {
        basket.contains { $0.path == entry.path }
    }

    /// What a press would really do — the list the engine is handed, its total,
    /// and the paths the confirmation names.
    ///
    /// One row in the basket is not always one removal: a cache row names a
    /// folder macOS will not part with and stands for everything inside it. The
    /// question the person answers is asked of *this*, not of the basket, so the
    /// dialog cannot describe a different act from the one it starts.
    public var removalQuestion: DiskRemovalPlan.Question {
        DiskRemovalPlan.question(basket: basket, advice: result?.advice ?? [])
    }

    public func emptyBasket() async {
        // The gate is unchanged — the engine partitions whatever comes out of
        // here and `HelmTrash` still has the last word.
        let paths = removalQuestion.paths
        guard !paths.isEmpty else { return }
        // **One removal at a time**, the rule `UninstallerViewModel` already
        // follows. The basket is not emptied until the answer comes back, so
        // between the press and that moment the button is live and the same
        // paths are still in it. The second round is not a second deletion —
        // the files are already in the Trash — it is a refusal per path, and
        // the lines below overwrite the report of the removal that worked.
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let removal: DiskRemoval? = await client.request(DiskCommand.trash, encoding: paths)
        // **A batch nobody answered is not a batch that moved nothing.** Folded
        // with `??`, this stood «Moved to the Trash — 0 bytes» over folders that
        // are exactly where they were — and never even drew it, because
        // `HelmRemovalOutcome.verdict(removed: 0, failed: 0)` is `.silent`. Nor
        // is it a batch that failed: the engine may have moved everything and
        // the reply been lost.
        //
        // **So the basket stays.** It is the one piece of state in this module
        // that nothing can reconstruct — folders picked across several drills
        // into a tree that took a minute to walk — and emptying it on the
        // strength of an answer nobody received left the person with no sentence,
        // no list, and nothing to press again.
        guard let removal else {
            clearRemovalReport()
            replyLost = true
            // Counts and outcomes are free; nothing here names a path. It was the
            // one branch in this module that reached the screen without reaching
            // the file a person attaches to a bug report.
            HelmLog.shared.info(DiskEngine.moduleID, "trash reply lost")
            return
        }
        // The four fields are one report, so a round that *was* answered puts the
        // previous round's «no answer» down as well — otherwise the sentence
        // outlives the press it was about.
        replyLost = false
        failures = removal.refused
        removedCount = removal.removed.count
        banner = DkStr.movedToTrash(Bytes(removal.freedBytes))
        basket = []
        // Re-walking the disk to learn what we already know — those paths are
        // gone, and by how much — costs a minute on a full volume. Apply the
        // deletion to the tree in hand instead.
        let removed = removal.removed
        guard let previous = result, !removed.isEmpty else { return }
        let pruned = DiskTreePrune.removing(paths: removed, from: previous.root)
        // Free space stays as measured: `HelmTrash` moved these paths to
        // `~/.Trash`, a folder on this same volume, so the disk gained nothing
        // and crediting `freed` to it invented space until the next real scan —
        // and past it, since the figure is saved and restored. Pruning the tree
        // is the true half: what the volume *uses* falls by what left.
        let updated = ScanResult(root: pruned, freeBytes: previous.freeBytes,
                                 filesScanned: previous.filesScanned, seconds: previous.seconds,
                                 advice: DiskRemovalPlan.remaining(previous.advice,
                                                                   after: removed))
        result = updated
        // An unfinished tree is not written down. Every directory in it reports a
        // floor rather than a total, and the store is what the module reopens on
        // and labels "measured N minutes ago" — so saving one turns a tree the
        // person was told is incomplete into a measurement they are not.
        if treeIsComplete {
            store.saveDetached(updated, at: completedAt ?? Date())
        }
        focusPath = DiskFocus.resolve(paths: focusPath.map(\.path), in: pruned)
        recomputeSegments()
    }
}
