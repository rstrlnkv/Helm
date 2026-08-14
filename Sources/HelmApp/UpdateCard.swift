import Foundation

/// Which arm of the About page's update card is drawn.
///
/// **The order these facts are read in was the defect.** The card asked about
/// an offer before it asked about the note beside it, so the sentence written
/// for «this release published no digest — install it yourself» could not be
/// reached: the offer was still there. Written as a chain of `else if`s inside a
/// `@ViewBuilder`, that order was a thing to be read rather than a thing to be
/// asked about, and reading it is what shipped the unreachable branch.
///
/// So the decision is a value now, and the view switches over it exhaustively —
/// no `default`, so a state the updater learns to write is a build error here
/// rather than a card that draws the wrong thing.
enum UpdateCard: Equatable {
    case downloading
    case installing
    /// The download is not what the release published.
    case digestMismatch
    case failed
    case checking
    /// An installable release, and the button that takes it.
    case ready
    /// A release Helm will not swap in silently; the browser has the page.
    case manualInstall
    case checkFailed
    /// This build is a prerelease ahead of the channel it follows.
    case ahead
    case upToDate
    /// Nothing was decided this session: say when the last check was instead of
    /// claiming to be current.
    case lastChecked

    /// The card, from the facts that decide it.
    ///
    /// Booleans rather than the values themselves: what is being decided is
    /// which arm draws, and the release and the version string are the view's
    /// to read once it knows.
    static func drawn(installState: UpdateService.InstallState, checking: Bool,
                      hasRelease: Bool, hasAhead: Bool,
                      note: UpdateService.Note?) -> UpdateCard {
        if let inFlight = drawnFor(installState) { return inFlight }
        // A check in flight is newer than whatever it is about to replace.
        if checking { return .checking }
        // An offer outranks the notes below it, which is right and is exactly
        // why a refused install has to take the offer away rather than write a
        // note underneath one.
        if hasRelease { return .ready }
        switch note {
        case .manualInstall: return .manualInstall
        case .checkFailed: return .checkFailed
        case .upToDate, nil: break
        }
        // Before "up to date", which this state used to be read as: the check
        // reports both, and being ahead is the more specific answer.
        if hasAhead { return .ahead }
        return note == .upToDate ? .upToDate : .lastChecked
    }

    /// The half of the decision an install in flight settles on its own; nil
    /// when nothing is in flight and the notes below get their turn.
    private static func drawnFor(_ installState: UpdateService.InstallState) -> UpdateCard? {
        switch installState {
        case .downloading: return .downloading
        case .installing: return .installing
        case .digestMismatch: return .digestMismatch
        case .failed: return .failed
        case .idle: return nil
        }
    }
}
