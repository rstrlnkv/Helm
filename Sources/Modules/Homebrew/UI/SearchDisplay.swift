import Foundation

/// Which of the search tab's two areas is on screen.
///
/// The decision used to be inline in `body` as
/// `query.isEmpty && hb.searchHits.isEmpty` — so once one search had answered,
/// erasing the field could never bring the prompt back: the old hits pinned the
/// results list over an empty query. And it hung on a private `@State`, where
/// no test could pin it. The results belong to a query; no query, no results.
enum SearchDisplay: Equatable {
    case prompt
    case results

    /// Trimmed, because the engine trims: `search` refuses a whitespace-only
    /// query, so results shown over one are results no query owns.
    static func state(query: String, hasHits: Bool) -> SearchDisplay {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? .prompt : .results
    }
}
