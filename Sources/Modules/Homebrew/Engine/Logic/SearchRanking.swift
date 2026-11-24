import Foundation

/// Puts the package somebody actually named at the top of the results.
///
/// `brew search` answers alphabetically, which buries the obvious one:
/// `hello` lands behind every `*shell*`. Typing a package's exact name is the
/// clearest statement of intent the search box can receive.
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
        // Inside a group only: what the person typed beats any figure.
        func byInstalls(_ group: [SearchHit]) -> [SearchHit] {
            // A cask's popularity comes from the cask document: the two files
            // are separate and a shared name — `docker` is both — would
            // otherwise be ranked by the wrong one.
            //
            // **The name as brew spelled it, not the lowercased form the
            // grouping compares with.** A hit spelled otherwise (a tap's `Foo`)
            // finds no count and keeps brew's position in its group. Folding
            // case would let one package collect another's figure, and a rank
            // from somebody else's number is worse than no rank.
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
