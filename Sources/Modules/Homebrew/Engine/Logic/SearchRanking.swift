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
/// Three groups, and inside each one brew's order is left alone — it is
/// alphabetical, and re-sorting it would only make the list harder to scan.
public enum SearchRanking {

    public static func rank(_ hits: [SearchHit], query: String) -> [SearchHit] {
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
        return exact + prefixed + rest
    }
}
