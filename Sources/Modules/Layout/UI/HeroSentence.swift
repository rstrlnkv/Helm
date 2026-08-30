/// Which of four things the hero is saying, decided once for both its lines.
///
/// **The figure and the caption used to decide separately, and disagreed.** The
/// caption asked `watching`, then the count, then the pause — so `suspended`
/// was unreachable whenever the chosen period held nothing. The figure never
/// asked about the pause at all. On a default install the period is «today», so
/// a zero count is the whole of every morning before the first correction, and
/// that is exactly when a password sheet is most likely to be in front: the
/// module had dropped the buffer, the remembered word and the undo record, and
/// the page said «Watching your words».
///
/// The window header 56 pt above said «Paused» at that same instant, because
/// `LayoutDescriptor.activity` reads both flags.
/// `TheHeaderDoesNotContradictThePageTests` guards that function alone and never
/// mounted the hero, so the two halves of one sentence were checked apart.
///
/// A type rather than a reordering, because the ordering *is* the rule and a
/// rule spelled twice is a rule that drifts. It is also the only shape of this
/// decision a test can reach: offscreen accessibility answers nothing, so the
/// drawn words are not readable from a render.
///
/// `suspended` is deliberately not folded into `watching` by the caller —
/// `watching` also gates the period row, and five buttons vanishing and
/// returning as a password sheet opens and closes is motion about something the
/// person did not do.
enum HeroSentence: Equatable {
    /// macOS is not delivering keystrokes at all.
    case deaf
    /// Helm can hear and is refusing to listen: a secure field is in front.
    ///
    /// **Carries whether there is still a figure**, because the pause takes the
    /// caption and must not take the number with it. A password sheet is up for
    /// as long as it takes to type a password, and the count of what the module
    /// put right today does not stop being true while it is — a hero that
    /// blanked its own figure for those few seconds would be reporting the
    /// sheet, not the day.
    case paused(hasFigure: Bool)
    /// Watching, and nothing has needed putting right in the chosen period.
    case nothingYet
    /// Watching, with something to show.
    case counting

    init(watching: Bool, suspended: Bool, hasFigure: Bool) {
        if !watching { self = .deaf }
        else if suspended { self = .paused(hasFigure: hasFigure) }
        else if !hasFigure { self = .nothingYet }
        else { self = .counting }
    }

    /// Whether the big line is a number. The one thing both of the hero's lines
    /// have to agree about.
    var showsFigure: Bool {
        switch self {
        case .counting, .paused(hasFigure: true): return true
        case .deaf, .nothingYet, .paused(hasFigure: false): return false
        }
    }
}
