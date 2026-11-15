import Foundation

/// Why the Apps tab has no rows on it — or nothing, when it has some.
///
/// **The page branched on `loading` alone.** A search that matched nothing and a
/// Mac whose app folders really came back empty drew the same empty inset
/// `List`, under a footer still counting apps. Two facts, one picture.
///
/// Here rather than in the view, and over counts rather than over the rows, for
/// the reason `DuplicatesEmpty` and `HistoryEmpty` give: it is the module's
/// rule about what its own empty screen means.
public enum AppsEmpty {

    /// Exhaustive on purpose, like `DuplicatesEmpty.Reason`: a `default` at the
    /// caller is how a third state would come to be drawn as one of these two,
    /// which is the defect this type exists for.
    public enum Reason: Equatable, Sendable {
        /// The engine answered, and the app folders held nothing to list.
        case noApps
        /// There is a list; the search hid every row of it. The sentence
        /// belongs to the search field, not to the Mac.
        case searchHidesAll
    }

    /// What the footer's status line has to say.
    public enum Status: Equatable, Sendable {
        /// The list is still on its way, or has not been asked for yet.
        /// «Counting apps…», which is true.
        case counting
        /// Helm knows, and the number is it. An answer of «none» is an answer
        /// and reads as zero.
        case counted(Int)
    }

    /// **Not answered yet is «counting», not «0 apps».** The page draws its first
    /// frame before its `.task` has asked for the list, and `apps` is empty
    /// then; a count read off it would say «0 apps» about a Mac nobody has
    /// looked at. `answered` is the view model's `listAnswered`, the flag the body
    /// reads too, so the two cannot disagree.
    ///
    /// - Parameters:
    ///   - answered: whether the list has ever been answered.
    ///   - loading: whether the query is out now.
    ///   - apps: what the module holds.
    public static func status(answered: Bool, loading: Bool, apps: Int) -> Status {
        loading || !answered ? .counting : .counted(apps)
    }

    /// - Parameters:
    ///   - answered: whether the list has ever been answered — the view model's
    ///     flag, not `apps.isEmpty`: a Mac with no applications on it is an
    ///     answer and reads as «0 apps». Not answered yet is no empty screen:
    ///     the page draws its spinner.
    ///   - apps: what the module holds.
    ///   - shown: what survives the search filter. Any at all and this screen
    ///     is a list, not a statement.
    public static func reason(answered: Bool, apps: Int, shown: Int) -> Reason? {
        guard shown == 0 else { return nil }
        // Rows behind the filter first: a hidden list is a fact about the
        // search whatever the engine did or did not say since.
        if apps > 0 { return .searchHidesAll }
        return answered ? .noApps : nil
    }
}
