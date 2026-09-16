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
    ///
    /// **And a word typed with Return not yet pressed is still the prompt.**
    /// The second argument was `hasHits`, which this never read — a vestige of
    /// the `@State` this replaced. What it has to know instead is whether any
    /// query is out or answered, because the results area is now three
    /// drawings: a search really running says so and moves, and a search that
    /// has not been *started* must not draw either that or «No results.» over
    /// a word the person is still typing. `ListReading.notAsked` is exactly
    /// that person.
    static func state(query: String, reading: ListReading) -> SearchDisplay {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return .prompt }
        return reading == .notAsked ? .prompt : .results
    }
}
