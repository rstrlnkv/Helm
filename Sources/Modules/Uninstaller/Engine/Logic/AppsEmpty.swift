import Foundation

/// Why the Apps tab has no rows on it — or nothing, when it has some.
///
/// **The page branched on `loading` alone.** A search that matched nothing, a
/// list the engine never answered and a Mac whose app folders really came back
/// empty all drew the same empty inset `List`, under a footer still counting
/// apps. Three facts, one picture — and one of them, the unanswered list, is
/// the state `UninstallerViewModel.appCount` already refuses to fold, so the
/// body was undoing the footer's honesty.
///
/// Here rather than in the view, and over counts rather than over the rows, for
/// the reason `DuplicatesEmpty` and `HistoryEmpty` give: it is the module's
/// rule about what its own empty screen means.
public enum AppsEmpty {

    /// Exhaustive on purpose, like `DuplicatesEmpty.Reason`: a `default` at the
    /// caller is how a fourth state would come to be drawn as one of these
    /// three, which is the defect this type exists for.
    public enum Reason: Equatable, Sendable {
        /// The request went out and nothing came back — an engine that is gone,
        /// or a reply that was lost. Not a claim about the Mac.
        case neverAnswered
        /// The engine answered, and the app folders held nothing to list.
        case noApps
        /// There is a list; the search hid every row of it. The sentence
        /// belongs to the search field, not to the Mac.
        case searchHidesAll
    }

    /// Whether this screen is an **invitation** — nothing here, and something to
    /// do about it — or a statement of what was found.
    ///
    /// `HelmEmptyState` splits its arguments along exactly this line, and
    /// `LeftoversEmpty.invites` is the same answer one module over: a verb on the
    /// answered-and-empty screen offers to repeat a question that has just been
    /// answered, and on the filtered one it offers to reload the Mac when what
    /// the person wants is the search field directly above the message.
    ///
    /// The unanswered list is the one dead end of the three — nothing came back,
    /// and the toolbar's Refresh is the only way out of it — so it is the one
    /// that gets the verb.
    ///
    /// Exhaustive on purpose. A `default` here is how a fourth state would come
    /// to be given a verb, or lose one, without anybody deciding.
    public static func invites(_ reason: Reason) -> Bool {
        switch reason {
        case .neverAnswered: true
        case .noApps, .searchHidesAll: false
        }
    }

    /// - Parameters:
    ///   - answered: whether the list has ever been answered — the view model's
    ///     flag, not `apps.isEmpty`, for the reason `appCount` gives.
    ///   - apps: what the module holds.
    ///   - shown: what survives the search filter. Any at all and this screen
    ///     is a list, not a statement.
    public static func reason(answered: Bool, apps: Int, shown: Int) -> Reason? {
        guard shown == 0 else { return nil }
        // Rows behind the filter first: a hidden list is a fact about the
        // search whatever the engine did or did not say since.
        if apps > 0 { return .searchHidesAll }
        return answered ? .noApps : .neverAnswered
    }
}
