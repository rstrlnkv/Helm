import Foundation

/// Which copy of identical content stays, and in what order the rest follow.
///
/// The module baskets every copy but the first in one click, so this is the
/// decision the whole screen rests on. `KeepPolicy` is the belief about which
/// copy is the original, made a question the person answers; this is where the
/// answer is applied. The rungs and their order belong to the policy; what is
/// left here is what each rung reads.
///
/// **A rung that cannot tell hands on rather than deciding.** That holds only
/// while a rung is silent about *every* pair it compares or about none;
/// `KeepPolicy.ladder` and `KeepReason.undated` say why the missing date is a
/// rung of its own (`TheSurvivorDoesNotDependOnWalkOrderTests`).
public enum SurvivingCopy {

    /// The group's copies, the survivor first.
    ///
    /// Returns the copies rather than their paths: the caller wants the whole of
    /// each one (its size, its clone family, its date), not a second lookup.
    public static func order<T: KeepCandidate>(_ files: [T], by rule: KeepRule) -> [T] {
        files.sorted { decide($0, over: $1, by: rule).keepsFirst }
    }

    /// Why the survivor of these copies is the one that stays — the rung that
    /// separated it from the copy that came closest.
    ///
    /// Nil when there is nothing to compare it against. Not «the reason it beat
    /// the worst of them», which would be the rung that separates the group's
    /// two extremes and says nothing about the choice actually made.
    public static func reason<T: KeepCandidate>(among files: [T], by rule: KeepRule) -> KeepReason? {
        let ordered = order(files, by: rule)
        guard ordered.count > 1 else { return nil }
        return decide(ordered[0], over: ordered[1], by: rule).reason
    }

    /// Which of two copies stays, and which rung said so — one answer, because
    /// the order and the explanation must not be able to disagree.
    private static func decide(_ a: some KeepCandidate, over b: some KeepCandidate,
                               by rule: KeepRule) -> (keepsFirst: Bool, reason: KeepReason) {
        for rung in rule.policy.ladder {
            if let verdict = separates(rung, a, b, rule.transit) { return (verdict, rung) }
        }
        // Alike on every rung, which for distinct paths cannot happen: `.name`
        // is the last one and two paths in a group are two different strings.
        // The same file listed twice lands here, and either answer orders it.
        return (false, .name)
    }

    /// True when `a` stays, false when `b` does, nil when this rung cannot tell
    /// them apart.
    private static func separates(_ rung: KeepReason,
                                  _ a: some KeepCandidate, _ b: some KeepCandidate,
                                  _ transit: TransitFolders) -> Bool? {
        switch rung {
        case .place:
            let (transitA, transitB) = (transit.holds(a.path), transit.holds(b.path))
            // Both landed in the same kind of place, or neither did: the tier
            // knows nothing about which of them somebody meant to keep.
            guard transitA != transitB else { return nil }
            return transitB
        case .undated:
            // Asked before the date it is about, so the rung below it never sees
            // a pair it can only half answer.
            let (datedA, datedB) = (a.added != nil, b.added != nil)
            guard datedA != datedB else { return nil }
            return !datedA
        case .date:
            // Two dates decide, and by `.undated` above there is no other kind of
            // pair left: either both are known or neither is.
            guard let dateA = a.added, let dateB = b.added, dateA != dateB else { return nil }
            return dateA < dateB
        case .depth:
            // Filesystems batch the date for files that arrived together, so it
            // ties often. A file four folders down was put there by somebody; a
            // file at the top of the folder is where things land.
            let (depthA, depthB) = (depth(a.path), depth(b.path))
            guard depthA != depthB else { return nil }
            return depthA < depthB
        case .name:
            // So two copies alike in every way the rule can see still come back
            // in one fixed order and the row does not move between scans.
            guard a.path != b.path else { return nil }
            return a.path < b.path
        }
    }

    private static func depth(_ path: String) -> Int {
        path.split(separator: "/").count
    }
}
