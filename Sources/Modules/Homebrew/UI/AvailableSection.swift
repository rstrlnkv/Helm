import Foundation
import Module_Homebrew_Engine

/// What the "Available to install" section under a filtered list says.
///
/// nil is "draw nothing here": no needle, nothing asked for this word yet, or
/// an answer that belongs to a word since typed over. Erasing `wget` to `wg`
/// shows nothing until `wg` is asked, while `wget`'s hits stay held in
/// `HomebrewViewModel.searchHits` for when it is typed again.
enum AvailableSection: Equatable {
    case searching
    case found
    case nothingFound
    case unanswerable

    static func of(query: String, searchedQuery: String?, reading: ListReading,
                   available: [SearchHit]) -> AvailableSection? {
        guard let needle = ListFilter.needle(query), needle == searchedQuery else { return nil }
        switch reading {
        case .notAsked: return nil
        case .waiting: return .searching
        case .answered: return available.isEmpty ? .nothingFound : .found
        case .unanswerable: return .unanswerable
        }
    }
}
