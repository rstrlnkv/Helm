import Foundation

/// What the unprompted Trash window may act on.
///
/// The review screen's rules with one difference that changes all of them: nobody
/// asked for this window. It opened because an app reached the Trash, so what it
/// arrives with ticked has to be defensible before a single path has been read —
/// and what one press sends has to be exactly what was listed above it.
///
/// `UninstallPlan` is the same argument for the flow the person started, and the
/// two are deliberately not merged: that one always sends the app bundle, and this
/// one must never send it.
public enum TrashOfferPlan {

    /// Ticked when the window opens.
    ///
    /// The same default as `UninstallPlan.defaultSelection` and for the same
    /// reason: a path under the app's *bundle id* is that app's, near enough to
    /// certain, and a path under its *display name* is a guess. Names collide —
    /// "Mail", "Notes", "Player" — and a guess arriving pre-ticked means somebody
    /// has to notice it to keep their data.
    public static func defaultSelection(_ groups: [TrashedAppLeftovers]) -> [String] {
        var seen: Set<String> = []
        return groups.flatMap(\.leftovers)
            .filter { !$0.matchedByName }
            .map(\.path)
            // Two apps in the Trash can list one path — a group container under a
            // suite id both of them declare.
            .filter { seen.insert($0).inserted }
    }

    /// What Move to Trash sends: the ticked paths, in the order they were drawn,
    /// each one once.
    ///
    /// Built from what the window listed rather than from the ticks alone, which
    /// is what keeps two promises the window makes. The app bundle sitting in the
    /// Trash is never among them — Helm cleans up around the person's decision and
    /// does not touch the thing they already moved — and neither is a path the
    /// window never showed.
    public static func paths(_ groups: [TrashedAppLeftovers], selected: Set<String>) -> [String] {
        var seen: Set<String> = []
        return groups.flatMap(\.leftovers)
            .map(\.path)
            .filter { selected.contains($0) && seen.insert($0).inserted }
    }

    /// What stays ticked when a second app lands in the Trash and the window
    /// takes it in.
    ///
    /// Two apps dropped together are one gesture to the person and two arrivals
    /// to the app, so the window has to grow. Rebuilding the selection from the
    /// default would be the cheap way to do it and it would quietly undo a
    /// decision: somebody who unticked a folder and then dropped another app
    /// would find it ticked again, next to a button that removes it.
    ///
    /// So: a path that was already on screen keeps whatever the person left it
    /// as, a path that was not gets the default for its own group, and a path
    /// that is gone — its app put back — takes itself out of the selection.
    public static func selectionAfterRefresh(previous: [TrashedAppLeftovers],
                                             selected: Set<String>,
                                             current: [TrashedAppLeftovers]) -> Set<String> {
        let seenBefore = Set(previous.flatMap(\.leftovers).map(\.path))
        let defaults = Set(defaultSelection(current))
        var out: Set<String> = []
        for path in current.flatMap(\.leftovers).map(\.path) {
            if seenBefore.contains(path) {
                if selected.contains(path) { out.insert(path) }
            } else if defaults.contains(path) {
                out.insert(path)
            }
        }
        return out
    }

    /// Which apps a removal has actually answered for, and may therefore be
    /// remembered as declined.
    ///
    /// Not the ones whose files macOS refused. A refusal is not a decision — the
    /// person can grant Full Disk Access, unlock the file, quit whatever was
    /// holding it — and the record is otherwise final for as long as the app sits
    /// in the Trash. That matters more here than anywhere else in the module,
    /// because this window is the only place some of these files are ever
    /// offered: the Leftovers tab lists bundle-id-named entries in nine folders,
    /// so a refused Group Container or a name-matched folder is on no other
    /// screen Helm has.
    ///
    /// A path the person simply left unticked is a different thing and does not
    /// hold the group open: they were shown it and left it alone.
    public static func answered(_ groups: [TrashedAppLeftovers],
                                failed: Set<String>) -> [TrashedAppLeftovers] {
        groups.filter { group in !group.leftovers.contains { failed.contains($0.path) } }
    }

    /// The size under the list, counting what `paths` would send.
    public static func totalBytes(_ groups: [TrashedAppLeftovers], selected: Set<String>) -> Int {
        var seen: Set<String> = []
        return groups.flatMap(\.leftovers)
            .filter { selected.contains($0.path) && seen.insert($0.path).inserted }
            .reduce(0) { $0 + $1.sizeBytes }
    }
}
