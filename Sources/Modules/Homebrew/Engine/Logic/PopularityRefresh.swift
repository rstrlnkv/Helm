import Foundation

/// When Homebrew's install counts are worth asking for again, how much of an
/// answer this module is willing to read, and what an answer means once it is
/// here.
///
/// The asking itself lives in `FilePopularityStore`; everything it *decides*
/// lives here, so the decisions can be tested without a network (the split
/// `UpdateService` and `UpdateCheck.evaluate` make).
enum PopularityRefresh {
    /// The counts cover a thirty-day window and are republished daily. Asking
    /// oftener spends somebody's bandwidth on a figure that has not moved, and
    /// the only thing it buys is a search result in a different order.
    static let interval: TimeInterval = 24 * 60 * 60

    /// The two documents are under half a megabyte each; 5 MiB leaves room to
    /// grow for years and still refuses whatever a moved endpoint might serve.
    ///
    /// **What this bounds is what came back over the wire, and only that**: the
    /// body is already buffered, so the ceiling keeps it from
    /// `JSONSerialization` and the support folder. The wire itself is bounded
    /// by `FilePopularityStore.wireDeadline`.
    ///
    /// **It does not bound the cached document**, which `load` parses with no
    /// size check: the file is one Helm wrote itself, 0600 through
    /// `PrivateFile`, and anything able to rewrite it can rewrite the rest of
    /// the support folder.
    static let sizeCeiling = 5 * 1024 * 1024

    /// A reading dated in the future is due too: a Mac whose clock was wrong
    /// and has since been corrected would otherwise never ask again.
    static func isDue(lastWritten: Date?, now: Date) -> Bool {
        guard let lastWritten else { return true }
        let age = now.timeIntervalSince(lastWritten)
        return age >= interval || age < 0
    }

    static func isWithinCeiling(_ byteCount: Int) -> Bool { byteCount <= sizeCeiling }

    /// What a response means, with each refusal naming itself.
    ///
    /// Three cases rather than one optional: `unchanged` keeps the reading
    /// *and* stamps the clock, `refused` leaves the clock alone so the next
    /// launch tries again, and `use` is the only one that writes anything.
    enum Answer: Equatable {
        /// A document this build could read, the only case that replaces a
        /// reading, including `{"formulae":{}}`: the endpoint is entitled to
        /// say "nobody installed anything", and search then keeps brew's own
        /// order. What must never become that value is `refused`.
        case use(InstallCounts)
        /// A 304: what is already stored is current.
        case unchanged
        /// The reason, for the log. Never an empty reading.
        case refused(String)
    }

    static func answer(statusCode: Int, data: Data) -> Answer {
        if statusCode == 304 { return .unchanged }
        guard (200..<300).contains(statusCode) else {
            return .refused("install counts refused, HTTP \(statusCode) — keeping the last reading")
        }
        guard isWithinCeiling(data.count) else {
            return .refused("install counts came back at \(data.count) bytes — refused")
        }
        guard let counts = InstallCounts.parse(data) else {
            return .refused("install counts came back in a shape this build cannot read")
        }
        return .use(counts)
    }
}
