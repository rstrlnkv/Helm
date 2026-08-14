import Foundation

/// What the page says about a request nobody answered — once, whichever of the
/// two went unanswered.
///
/// `TransportClient.request` answers nil for a request that threw and for a reply
/// that would not decode, and this module reaches the second in the tree:
/// `LeftoversEngine.wireTransport` returns empty `Data` when the engine has gone
/// under a page that is still up. Two of this page's requests can end that way —
/// the removal and the scan — and `LeftoversViewModel.trash` makes the second one
/// itself, on the path where the first was already lost. So the two meet on the
/// first press that fails.
///
/// Here rather than in the view for the reason `LeftoversEmpty` is: it is the
/// module's rule about what its screen may claim, and a `switch` inside a `body`
/// is a rule no test can reach.
public enum LeftoversSilence {

    /// Which sentence the foot of the page owes.
    ///
    /// Three, not two flags read separately: the pair «the removal was lost» and
    /// «the rescan was lost» has a state where both are true, and drawing both
    /// sentences there is one machine fact announced twice — the removal's own
    /// wording then promising a list the rescan never delivered.
    public enum Note: Equatable, Sendable {
        /// The removal's reply was lost and the rescan answered: the list under
        /// the sentence is current, so the sentence may point at it.
        case removalLost
        /// Both were lost. The list is from before the press, and the removal's
        /// sentence is the one that says so — it covers this silence whole.
        case removalAndListLost
        /// A rescan nobody answered, with no removal behind it: the list on
        /// screen is the previous scan's, and the page changed in no other way.
        case listLost
    }

    /// - Parameters:
    ///   - removalUnanswered: the last removal's reply never came back.
    ///   - rescanUnanswered: the last scan's reply never came back.
    ///   - scanned: whether a list has ever been drawn. A first scan that was
    ///     lost leaves the page on its invitation, where «the list above is still
    ///     from the previous scan» names a list nobody has seen.
    public static func note(removalUnanswered: Bool, rescanUnanswered: Bool,
                            scanned: Bool) -> Note? {
        if removalUnanswered { return rescanUnanswered ? .removalAndListLost : .removalLost }
        guard rescanUnanswered, scanned else { return nil }
        return .listLost
    }
}
