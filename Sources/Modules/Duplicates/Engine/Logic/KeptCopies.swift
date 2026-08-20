import Foundation

/// The batch read against itself: what a plan promises to keep, no other plan
/// in the same batch may take.
///
/// **The gates beside this one answer about a path or about a pair, and neither
/// can see this.** `UserFileScope.partition` asks whether a path belongs to the
/// person; `DuplicateVerification` asks whether one pair is still what the scan
/// said it was. Both say yes to each half of `[a→keep b, b→keep a]` — two plans
/// that are each perfectly valid, and that together take every copy of the
/// content. The reply had nowhere to say so either: both paths came back under
/// `removed`, no refusal beside them, and the banner reported a clean removal.
///
/// **The view model cannot build that batch today, which is the argument for
/// checking it here rather than there.** `RemovableScope`'s own reasoning is
/// that a view model is the wrong place for the last word, because the engine
/// takes the list and acts on it — and this module made the same argument to
/// itself when it deleted its bare-paths entrance: a caller sending something
/// unverifiable gets nothing removed rather than something removed unchecked.
/// A batch whose survivors sit in its own removal set is the one remaining
/// shape of "removed unchecked", and what it costs is the content.
///
/// Nothing here reads a disk. It is arithmetic over the batch, so a contradiction
/// is refused before the verification spends minutes reading the pair it is
/// about (ARCHITECTURE.md § Duplicates).
public enum KeptCopies {

    /// The plans that may be acted on, and the copies refused for contradicting
    /// them.
    ///
    /// **Decided in the order the batch arrived**, which is what makes the
    /// answer the same twice: whichever copy of a contradiction survives is a
    /// person's file, and a rule that read the batch out of a `Set` or a
    /// `Dictionary` would take `/a/1` on one run and `/a/2` on the next from the
    /// identical screen. The first plan to name a copy wins, and every later
    /// plan that would break that promise is refused.
    ///
    /// Three ways a batch contradicts itself, and they are one question asked of
    /// both ends of a plan:
    /// - it removes what it also keeps (`remove == keep`) — a pair check reads
    ///   that file twice and calls it identical, because it is;
    /// - it removes a copy an earlier plan is keeping;
    /// - it keeps a copy an earlier plan is removing, which is the same promise
    ///   broken from the other side: the survivor this plan is measured against
    ///   is on its way to the Trash.
    public static func partition(_ plans: [DuplicatePlan])
    -> (honoured: [DuplicatePlan], contradicted: [String]) {
        var going: Set<String> = []
        var staying: Set<String> = []
        var honoured: [DuplicatePlan] = []
        var contradicted: [String] = []

        for plan in plans {
            guard plan.remove != plan.keep,
                  !staying.contains(plan.remove),
                  !going.contains(plan.keep)
            else {
                contradicted.append(plan.remove)
                continue
            }
            going.insert(plan.remove)
            staying.insert(plan.keep)
            honoured.append(plan)
        }
        return (honoured, contradicted)
    }
}
