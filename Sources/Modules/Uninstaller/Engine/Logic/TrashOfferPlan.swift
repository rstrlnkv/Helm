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

    /// The size under the list, counting what `paths` would send.
    public static func totalBytes(_ groups: [TrashedAppLeftovers], selected: Set<String>) -> Int {
        var seen: Set<String> = []
        return groups.flatMap(\.leftovers)
            .filter { selected.contains($0.path) && seen.insert($0.path).inserted }
            .reduce(0) { $0 + $1.sizeBytes }
    }
}
