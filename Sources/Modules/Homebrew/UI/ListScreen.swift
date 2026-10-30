import Foundation

/// **What happened to the query behind one of this module's lists.**
///
/// A `Bool` per list can answer only two of the three things that happen to a
/// `brew` call: "loaded" and "not loaded yet". A refusal is neither: a `brew
/// list` that could not be put would leave the flag down for ever, and the page
/// would draw the waiting spinner over a question that will never be answered,
/// with no timeout anywhere in the UI to end it.
///
/// This is `DoctorReading`'s shape for the package lists, for the rule that type
/// carries and `refreshDoctor`'s own doc comment states: "no issues" and "the
/// question could not be put" are the same empty array and must never be one
/// sentence on screen.
enum ListReading: Equatable {
    /// Nobody has asked yet. The "Available to install" section's ordinary
    /// state — no query is out for brew, whether because the field is empty
    /// or because the local filter still has something to show — and the
    /// frame or two the other lists spend between mounting and their first
    /// ask.
    case notAsked
    /// A query is out and nothing has come back.
    case waiting
    /// **There is an answer to draw**, and the list beside this reading is it.
    ///
    /// A refusal landing on top of a list that already has rows leaves this
    /// reading where it is, which is the module's own rule for the three
    /// package lists ("no `?? []` on any list reply" — a hung `brew` cut off at
    /// the runner's deadline must not replace a real list with an empty one).
    /// The kept answer is still the newest thing there is to draw, so the page
    /// draws it and the log names the outcome.
    case answered
    /// **The question could not be put, and there is no earlier answer behind
    /// it.** Not an empty list: an unread one. A separate case from `answered`
    /// for exactly the reason `DoctorReading.refused` is separate from an
    /// `.examined([])` — the sentence a person reads is the one they decide
    /// whether to trust the app on.
    case unanswerable
}

/// **What a list pane puts on screen — five drawings.**
///
/// `AvailableSection` and `HealthScreen` are the shape this follows, for the
/// reason those files give: which sentence stands over which state is the whole
/// of the decision.
///
/// Waiting *moves*; the two answers do not, and they are not the same sentence.
/// Drawn as one — which is what a single `empty:` string and a `Bool` amounted
/// to — «Нет установленных пакетов.» stands over a Mac with fifty-three
/// packages on it whose `brew list` refused, and «Ничего не найдено.» stands
/// over however long a `brew search` takes.
enum ListScreen: Equatable {
    /// There are rows. What the reading says is beside the point: rows on
    /// screen are an answer somebody got.
    case rows
    /// Something is on its way. The one drawing with a spinner in it.
    case waiting
    /// The query answered, and answered nothing.
    case nothing
    /// The query could not be put. Its own sentence, and nothing moving —
    /// there is nothing to wait for.
    case unanswerable
    /// **There are rows, and a query hides every one of them.** A list that
    /// answered with rows and a filter that shows none of them is neither `.nothing`
    /// (brew answered "no packages") nor `.rows` (there is nothing to draw) —
    /// it is its own sentence, over the same list underneath.
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
