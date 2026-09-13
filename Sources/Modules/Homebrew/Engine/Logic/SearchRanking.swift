import Foundation

/// Puts the package somebody actually named at the top of the results.
///
/// `brew search` answers alphabetically, and an alphabetical answer buries the
/// obvious one: searching `hello` on a real machine returned aws-shell,
/// cmdshelf and couchbase-shell first, with `hello` fourteenth, between
/// `helix-db` and `hellwal`. Typing a package's exact name is the clearest
/// statement of intent the search box can receive, and it was worth two
/// scrolls.
///
/// Three groups, and the groups themselves never move — what the person
/// typed beats any popularity figure. Inside a group, a package installed
/// more often comes first; brew's own alphabetical order is what is left to
/// break a tie, including the tie of "nobody has a reading for either one".
enum SearchRanking {

    static func rank(_ hits: [SearchHit], query: String,
                     formulae: InstallCounts = .none,
                     casks: InstallCounts = .none) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return hits }

        var exact: [SearchHit] = [], prefixed: [SearchHit] = [], rest: [SearchHit] = []
        for hit in hits {
            let name = hit.name.lowercased()
            if name == needle {
                // A formula and a cask can share a name; both are exact.
                exact.append(hit)
            } else if name.hasPrefix(needle) {
                prefixed.append(hit)
            } else {
                rest.append(hit)
            }
        }
        // Inside a group only. The groups are about what the person typed,
        // which is a better statement of intent than anything a popularity
        // figure can say.
        func byInstalls(_ group: [SearchHit]) -> [SearchHit] {
            // A cask's popularity comes from the cask document: the two files
            // are separate and a shared name — `docker` is both — would
            // otherwise be ranked by the wrong one.
            //
            // **The name as brew spelled it, and not the lowercased form the
            // grouping above compares with.** Homebrew keys both documents by
            // the package's own name, so this lookup is exact: a hit whose name
            // is not spelled the way the document spells it — a tap's `Foo`,
            // anything not already lowercase — finds no count and keeps brew's
            // own position inside its group. That is the degradation this
            // wants. Folding case to widen the match would let one package
            // collect a figure published for a differently-spelled one, and a
            // rank invented from somebody else's number is worse than no rank
            // at all, which costs nothing but the alphabetical order the
            // search box drew before any of this existed.
            func count(_ hit: SearchHit) -> Int? {
                (hit.isCask ? casks : formulae).counts[hit.name]
            }
            guard group.contains(where: { count($0) != nil }) else { return group }
            // `enumerated` keeps brew's alphabetical order as the tie-break, so
            // the sort is stable without depending on the sort being stable.
            return group.enumerated().sorted { a, b in
                let l = count(a.element), r = count(b.element)
                switch (l, r) {
                case let (l?, r?) where l != r: return l > r
                case (nil, .some): return false
                case (.some, nil): return true
                default: return a.offset < b.offset
                }
            }.map(\.element)
        }
        return byInstalls(exact) + byInstalls(prefixed) + byInstalls(rest)
    }
}
