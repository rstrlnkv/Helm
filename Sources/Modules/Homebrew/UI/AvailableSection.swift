import Foundation
import Module_Homebrew_Engine

/// What the "Available to install" section under a filtered list says —
/// **replaces `SearchDisplay`**, retired 2026-09-24 with the Search tab it
/// belonged to. That type decided between a prompt and a results list filling
/// a whole segment of its own; this decides whether a *second* section
/// belongs under whichever list the segment already draws, now that search is
/// a field every tab carries rather than a tab in itself.
///
/// `SearchDisplay`'s own lesson carries over unchanged: nil is "draw nothing
/// here", and it covers three cases the four that follow do not — no needle,
/// nothing asked for this word yet, and an answer on hand that belongs to a
/// word the person has since typed over. That last one is what keeps a
/// refined query from flashing a stale answer: erasing `wget` down to `wg`
/// shows nothing here until `wg` itself has been asked, even while `wget`'s
/// hits are still held in `HomebrewViewModel.searchHits` against the day the
/// person types `wget` again.
///
/// A value type rather than a decision inside `body`, for the reason
/// `InspectorState` and `HealthScreen` give at their own top: which sentence
/// stands over which state is the whole of the decision, and a `body` is
/// nowhere a test can reach.
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
