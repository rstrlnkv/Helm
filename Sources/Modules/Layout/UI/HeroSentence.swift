/// Which of four things the hero is saying, decided once for both its lines.
///
/// One type decides the figure and the caption, because the ordering is the rule and a rule spelled
/// twice drifts. `suspended` is not folded into `watching` by the caller: `watching` also gates the
/// period row, and five buttons leaving and returning as a password sheet opens and closes would be
/// motion about something the person did not do. The window header reads the same two flags through
/// `LayoutDescriptor.activity`.
enum HeroSentence: Equatable {
    /// macOS is not delivering keystrokes at all.
    case deaf
    /// Helm can hear and is refusing to listen: a secure field is in front.
    ///
    /// Carries whether there is still a figure: the pause takes the caption and not the number, which
    /// stays true while a password sheet is up.
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
