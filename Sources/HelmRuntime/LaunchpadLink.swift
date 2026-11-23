import Foundation

/// The one URL that opens the Launchpad window: `helm-launchpad://toggle`, sent by the Dock helper.
///
/// **Input from outside the process.** Any program can open any URL at Helm, so the parse is exact and
/// everything the helper never sends is refused, by comparing the spelling `URL` gives back: another scheme or host, a
/// path (even `/`), a query, a fragment, a user, a port (even an empty one). `URL(string:)` drops invisible characters
/// of the host (zero-width, soft hyphen, byte-order mark) and folds fullwidth ones before the compare, so a link that
/// looks like the exact one after that normalising is accepted; the result is still only the toggle, which any
/// process can already press. The scheme is the caller's, because Helm
/// and Helm Dev answer on different ones (`AppBuild.pairedLaunchpadLinkScheme`).
public enum LaunchpadLink {
    public static func accepts(_ url: URL, scheme: String) -> Bool {
        url.absoluteString == "\(scheme)://toggle"
    }

    /// Links closer together than this are one press: a double click on the Dock icon must not open the
    /// window and close it again. The same interval spaces the `link refused` log line
    /// (`ModuleHost.refusalLogThrottle`), so a loop of bad links writes one line per interval.
    public static let throttleInterval: TimeInterval = 0.5

    /// Whether an event at `now` (seconds on a monotonic clock) counts, remembering it when it does. `ModuleHost`
    /// holds two: `linkThrottle` for accepted links (the toggle) and `refusalLogThrottle` for the refusal log line.
    public struct Throttle {
        private var last: TimeInterval?
        public init() {}
        public mutating func admits(at now: TimeInterval) -> Bool {
            if let last, now - last < LaunchpadLink.throttleInterval { return false }
            last = now
            return true
        }
    }
}
