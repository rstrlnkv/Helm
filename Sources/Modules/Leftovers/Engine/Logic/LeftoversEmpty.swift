import Foundation

/// Why the list has no rows, in the page's own terms — or nothing, when it has.
///
/// **Asked of what the filters leave, not of what the scan found.** Those are
/// different facts on almost any Mac: `LeftoversScanner.preferences` returns
/// every plist in `~/Library/Preferences` and nearly all of them are `.inUse`,
/// so a page asking «did the scan find nothing» would draw a count and an
/// empty area under it.
///
/// Here rather than in the view, and over counts rather than over `[StaleItem]`,
/// because it is the module's rule about what its screen means.
public enum LeftoversEmpty {

    /// Four, not two. «Nothing is left over» is a fact about the Mac; «all of it
    /// is hidden by the filter» is a fact about a menu that is on screen directly
    /// above the message, and only the second one tells the person what to do
    /// next. Answering the first for both would be the page claiming a clean Mac
    /// while holding rows it has been told to hide.
    ///
    /// The fourth is a fact about the scan rather than about the Mac: some items
    /// were never judged (`ItemStatus.judged`), so «no leftovers found» is a
    /// claim this scan cannot back. **It carries its own count**, because the
    /// sentence interpolates one — a reason without it would have the page fetch
    /// the number from somewhere else, which is one question with two answers.
    public enum Reason: Equatable, Sendable {
        case notScanned, nothingFound, hiddenByFilter
        case notEverythingChecked(Int)
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
    /// **And the fourth invites.** It says Helm did not finish, and the verb that
    /// answers that is the Scan button; a screen reporting an unfinished scan with
    /// no way to run it again is a dead end.
    ///
    /// Exhaustive on purpose: a fifth state cannot gain or lose a verb without
    /// anybody deciding.
    public static func invites(_ reason: Reason) -> Bool {
        switch reason {
        case .notScanned, .notEverythingChecked: true
        case .nothingFound, .hiddenByFilter: false
        }
    }

    /// - Parameters:
    ///   - scanned: whether this session has asked the engine at all.
    ///   - visible: rows the list would draw — after both filters.
    ///   - hiddenByKind: rows the status filter keeps and the kind filter hides.
    ///   - unchecked: rows the scan never reached a verdict on, over the whole
    ///     scan and not over the list: none is `.judged` (an unreadable or undetermined
    ///     file, or a source row), so the default filter is exactly what hides them, and counting them
    ///     over what is drawn would answer zero in the state this exists for.
    public static func reason(scanned: Bool, visible: Int, hiddenByKind: Int,
                              unchecked: Int) -> Reason? {
        // Before anything has been asked, counts left over from a previous state
        // are not an answer about this Mac.
        guard scanned else { return .notScanned }
        guard visible == 0 else { return nil }
        // The filter keeps its precedence: that message claims nothing about the
        // Mac, so the unjudged items contradict nothing in it, and the menu that
        // caused it is on screen directly above.
        if hiddenByKind > 0 { return .hiddenByFilter }
        return unchecked > 0 ? .notEverythingChecked(unchecked) : .nothingFound
    }
}
