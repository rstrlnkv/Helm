import Foundation

/// What the unprompted Trash window may act on.
///
/// The review screen's rules, except nobody asked for this window: what it
/// arrives with ticked has to be defensible before a path is read, and one
/// press sends exactly what was listed.
///
/// Not merged with `UninstallPlan`: that one always sends the app bundle, and
/// this one must never send it.
public enum TrashOfferPlan {

    /// Ticked when the window opens.
    ///
    /// The same default as `UninstallPlan.defaultSelection`, for the same
    /// reason. Two apps in the Trash can list one path (a group container under
    /// a shared suite id), and `ownLeftovers` counts it once.
    public static func defaultSelection(_ groups: [TrashedAppLeftovers]) -> [String] {
        UninstallPlan.ownLeftovers(groups.flatMap(\.leftovers)).map(\.path)
    }

    /// What Move to Trash sends: the ticked paths, in the order they were drawn,
    /// each one once.
    ///
    /// Built from what the window listed, not from the ticks alone, so neither
    /// the app bundle in the Trash nor a path the window never showed is sent.
    public static func paths(_ groups: [TrashedAppLeftovers], selected: Set<String>) -> [String] {
        selectedLeftovers(groups, selected).map(\.path)
    }

    /// The ticked leftovers, each path once, in the order drawn.
    private static func selectedLeftovers(_ groups: [TrashedAppLeftovers],
                                          _ selected: Set<String>) -> [Leftover] {
        var seen: Set<String> = []
        return groups.flatMap(\.leftovers)
            .filter { selected.contains($0.path) && seen.insert($0.path).inserted }
    }

    /// What stays ticked when a second app lands in the Trash and the window
    /// takes it in.
    ///
    /// Rebuilding from the default would retick a folder the person unticked.
    /// So a path already on screen keeps what the person left it as, a new path
    /// gets its group's default, and a path that is gone (its app put back)
    /// leaves the selection.
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
    /// Not the ones whose files macOS refused. A refusal is not a decision (the
    /// person can grant access, unlock the file, quit its holder), and the
    /// record is final while the app sits in the Trash. Some of these files, a
    /// Group Container or a name-matched folder, are offered on no other screen.
    ///
    /// A path left unticked does not hold the group open: the person was shown it.
    ///
    /// It takes the result, not a set of failed paths, so a batch the engine
    /// held cannot read as "no path failed".
    public static func answered(_ groups: [TrashedAppLeftovers],
                                to result: UninstallResult) -> [TrashedAppLeftovers] {
        // A batch held for a running application moved nothing and answers nothing.
        guard result.stillRunning.isEmpty else { return [] }
        let failed = Set(result.failed)
        return groups.filter { group in !group.leftovers.contains { failed.contains($0.path) } }
    }

    /// The size under the list, counting what `paths` would send.
    public static func totalBytes(_ groups: [TrashedAppLeftovers], selected: Set<String>) -> Int {
        selectedLeftovers(groups, selected).reduce(0) { $0 + $1.sizeBytes }
    }
}
