import Foundation

/// **What happened to the query behind one of this module's lists.**
///
/// Not a `Bool`: a refusal is neither "loaded" nor "not loaded yet", and a
/// flag would leave the page spinning over it for ever. `DoctorReading`'s shape
/// for the package lists.
enum ListReading: Equatable {
    /// Nobody has asked yet: the search's ordinary state, and the lists'
    /// before their first ask.
    case notAsked
    /// A query is out and nothing has come back.
    case waiting
    /// **There is an answer to draw**, and the list beside this reading is it.
    ///
    /// A refusal over a list that already has rows leaves this reading where
    /// it is: the kept answer is drawn and the log names the refusal.
    case answered
    /// **The question could not be put, and there is no earlier answer behind
    /// it.** Not an empty list: an unread one.
    case unanswerable
}

/// **What a list pane puts on screen — five drawings.**
///
/// Waiting *moves*; the two answers do not, and they are not the same
/// sentence: an empty answer, a refusal and a wait are three drawings.
enum ListScreen: Equatable {
    /// There are rows, whatever the reading: rows are an answer somebody got.
    case rows
    /// Something is on its way. The one drawing with a spinner in it.
    case waiting
    /// The query answered, and answered nothing.
    case nothing
    /// The query could not be put. Its own sentence, and nothing moving —
    /// there is nothing to wait for.
    case unanswerable
    /// **There are rows, and a query hides every one of them.** Neither
    /// `.nothing` nor `.rows`: its own sentence.
    case noMatches

    /// `isEmpty` is the underlying list `brew` answered with; `shownIsEmpty`
    /// is what a filter leaves of it. The two differ only when there are rows
    /// to filter, which is the one case `.noMatches` exists for.
    static func of(isEmpty: Bool, shownIsEmpty: Bool, reading: ListReading) -> ListScreen {
        guard isEmpty else { return shownIsEmpty ? .noMatches : .rows }
        switch reading {
        case .notAsked, .waiting: return .waiting
        case .answered: return .nothing
        case .unanswerable: return .unanswerable
        }
    }

    /// Whether a package list's own section is drawn as a `List` row rather
    /// than as a single centred sentence — the section forces the shape even
    /// over a state that would otherwise be centred.
    static func forcesListShape(section: AvailableSection?, screen: ListScreen) -> Bool {
        section != nil || screen == .rows || screen == .noMatches
    }
}
