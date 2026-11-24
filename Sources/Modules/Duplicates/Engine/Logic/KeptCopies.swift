import Foundation

/// The batch read against itself: what a plan promises to keep, no other plan
/// in the same batch may take.
///
/// **The gates beside this one answer about a path or about a pair, and neither
/// can see this.** `UserFileScope.partition` asks whether a path belongs to the
/// person; `DuplicateVerification` asks whether one pair is still what the scan
/// said it was. Both say yes to each half of `[a→keep b, b→keep a]`: two plans
/// each valid alone that together take every copy of the content.
///
/// **The view model does not build such a batch; the check is here because the
/// engine takes the list and acts on it.** A view model is the wrong place for
/// the last word (`RemovableScope` reasons the same way). A batch whose
/// survivors sit in its own removal set is content removed unchecked.
///
/// Nothing here reads a disk. It is arithmetic over the batch, so a contradiction
/// is refused before the verification spends minutes reading the pair it is
/// about (Architecture/Duplicates.md § Duplicates).
enum KeptCopies {

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
    static func partition(_ plans: [DuplicatePlan])
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
