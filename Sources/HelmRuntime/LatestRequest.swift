import Foundation

/// Which request a reply belongs to, so an older one can be dropped rather than
/// land on top of a newer answer.
///
/// **A counter, not a latch, and the difference is the whole point.** A latch —
/// «refuse a second request while the first runs» — is right for an *act*
/// (`guard !busy` before a removal) and wrong for a *reading*: the second request
/// exists because something changed, and refusing it leaves the screen showing
/// what was true before. Leftovers is the case that made it plain: `setDisabled`
/// rescans so the row shows what launchd actually did, so a latch there would drop
/// the one scan that tells the truth. What has to be dropped is the older
/// *answer*.
///
/// Written out by hand in two view models before it was named — the family
/// CLAUDE.md calls «last writer wins by scheduling», and Autopilot's tampered-rule
/// verdict is the same shape one target over. Held by value on a `@MainActor`
/// object: the arithmetic is never concurrent, only the awaits between it are.
///
///     latest = LatestRequest()   // stored on the view model
///     let mine = latest.take()
///     let found = await client.request(…)
///     guard latest.isLatest(mine) else { return }
public struct LatestRequest: Sendable {
    /// Zero is «nothing has been asked for», and no token can equal it: `take`
    /// hands out 1 first, so an uninitialized `Int` is never mistaken for a live
    /// request.
    private var latest = 0

    public init() {}

    /// The token for a request being made now. Every token taken before this one
    /// is stale from here on — which is also how work in flight is abandoned
    /// wholesale: take a token and drop it.
    public mutating func take() -> Int {
        latest += 1
        return latest
    }

    /// Zero is never the latest, however fresh the counter: a caller holding an
    /// `Int` it has not taken yet must not read as the request in flight.
    public func isLatest(_ token: Int) -> Bool { token != 0 && token == latest }
}
