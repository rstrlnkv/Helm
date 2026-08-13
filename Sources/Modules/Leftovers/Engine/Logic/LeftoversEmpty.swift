import Foundation

/// Why the list has no rows, in the page's own terms — or nothing, when it has.
///
/// **The page asked the wrong question.** Its empty state branched on «the scan
/// found nothing» while the `List` under it was built from what the filters leave,
/// and those are different facts on almost any Mac: `LeftoversScanner.preferences`
/// returns every plist in `~/Library/Preferences` and nearly all of them are
/// `.inUse`. So an ordinary first scan drew «Found: 542 items», the sentence about
/// nothing being ticked by default, and 515 pt of nothing under the two of them.
///
/// Here rather than in the view, and over counts rather than over `[StaleItem]`,
/// because it is the module's rule about what its screen means and not a shape a
/// row happens to have.
public enum LeftoversEmpty {

    /// Three, not two. «Nothing is left over» is a fact about the Mac; «all of it
    /// is hidden by the filter» is a fact about a menu that is on screen directly
    /// above the message, and only the second one tells the person what to do
    /// next. Answering the first for both would be the page claiming a clean Mac
    /// while holding rows it has been told to hide.
    public enum Reason: Equatable, Sendable {
        case notScanned, nothingFound, hiddenByFilter
    }

    /// Whether this screen is an **invitation** — nothing here yet, and something
    /// to do about it — or a statement of what was found.
    ///
    /// `HelmEmptyState` splits its arguments along exactly this line, so the
    /// answer belongs beside the reason rather than inside a view: a button on a
    /// statement offers to repeat the scan that has just answered, and on the
    /// filtered list it offers to rescan a Mac when the verb the person wants is
    /// in the menu directly above the message.
    ///
    /// Exhaustive on purpose. A `default` here is how a fourth state would come to
    /// be given a verb, or lose one, without anybody deciding.
    public static func invites(_ reason: Reason) -> Bool {
        switch reason {
        case .notScanned: true
        case .nothingFound, .hiddenByFilter: false
        }
    }

    /// - Parameters:
    ///   - scanned: whether this session has asked the engine at all.
    ///   - visible: rows the list would draw — after both filters.
    ///   - hiddenByKind: rows the status filter keeps and the kind filter hides.
    public static func reason(scanned: Bool, visible: Int, hiddenByKind: Int) -> Reason? {
        // Before anything has been asked, counts left over from a previous state
        // are not an answer about this Mac.
        guard scanned else { return .notScanned }
        guard visible == 0 else { return nil }
        return hiddenByKind > 0 ? .hiddenByFilter : .nothingFound
    }
}
