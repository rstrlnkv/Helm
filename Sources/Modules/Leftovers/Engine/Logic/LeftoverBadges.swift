import Foundation

/// One mark beside a row's name: what the row *is*, and the one qualifier that
/// may follow it.
public enum RowBadge: Hashable, Sendable {
    /// Why the row is in this list — and, for a leftover, what the colour of
    /// «Select all» is about. Drawn for every row.
    case status(ItemStatus)
    /// Switched off in launchd's disabled list. A qualifier on the status, not a
    /// replacement for it.
    case runsAtLogin
    case disabled
}

/// What a row wears beside its name.
///
/// **Disabled is a qualifier and it was standing in for the status.** The page
/// wrote `if item.disabled { … } else { statusBadge(…) }`, so the one mark that
/// says why a row is in this list disappeared for exactly the rows somebody had
/// already switched off — and `runAtLoad` was appended regardless, in the same
/// orange the leftover pill wears. launchd's disabled list overrides the plist's
/// `RunAtLoad`, so a switched-off job drew «Disabled» and «At login» side by side:
/// two badges asserting opposite things about the next login.
///
/// So the status is always first, and the slot after it holds one qualifier:
/// «Disabled» if the job is switched off, «At login» otherwise. Never both — the
/// one that gives way is the one that is false.
///
/// Pure, and in the engine rather than in the page, because it is a rule about
/// what is true of an item rather than about how a pill is drawn: the page turns
/// each mark into a word and a tint, exhaustively.
public enum LeftoverBadges {
    public static func on(_ item: StaleItem) -> [RowBadge] {
        var badges: [RowBadge] = [.status(item.status)]
        if item.disabled {
            badges.append(.disabled)
        } else if item.runAtLoad {
            badges.append(.runsAtLogin)
        }
        return badges
    }
}
