import Foundation

/// Which copy of identical content stays, and in what order the rest follow.
///
/// The module baskets every copy but the first in one click, so this is the
/// decision the whole screen rests on. It used to be alphabetical — not a
/// belief about anything, just the order the list happened to be sorted in for
/// display — which meant `~/Desktop/photo.jpg` beat
/// `~/Documents/Archive/2019/photo.jpg` and Helm offered to delete the filed
/// original while keeping the clutter.
///
/// It then became the date added, which was a belief — «the original is the one
/// that has been there longest» — held silently and wrong often enough to matter:
/// a file downloaded and *then* filed keeps the download. `KeepPolicy` is that
/// belief made a question the person answers, and this is where the answer is
/// applied. The rungs and their order belong to the policy; what is left here is
/// what each rung reads.
///
/// **A rung that cannot tell hands on rather than deciding.** An unknown date is
/// the case that matters: a volume that does not record when a file was added
/// reports nothing, and nothing is evidence for neither copy. Read as a loss it
/// handed the whole decision to a fact the filesystem happened to keep, skipping
/// every rung below.
enum SurvivingCopy {

    /// The group's copies, the survivor first.
    ///
    /// Returns the copies rather than their paths: the caller wants the whole of
    /// each one — its size, its clone family, its date — and a list of paths
    /// made it look them up again in a table built for the purpose, which is one
    /// ordering of an array joined to another by a dictionary.
    static func order<T: KeepCandidate>(_ files: [T], by rule: KeepRule) -> [T] {
        files.sorted { decide($0, over: $1, by: rule).keepsFirst }
    }

    /// Why the survivor of these copies is the one that stays — the rung that
    /// separated it from the copy that came closest.
    ///
    /// Nil when there is nothing to compare it against. Not «the reason it beat
    /// the worst of them», which would be the rung that separates the group's
    /// two extremes and says nothing about the choice actually made.
    static func reason<T: KeepCandidate>(among files: [T], by rule: KeepRule) -> KeepReason? {
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
        case .date:
            // Two dates decide; one date and one blank decide nothing.
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
