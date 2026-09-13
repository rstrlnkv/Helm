import Foundation

/// When Homebrew's install counts are worth asking for again, how much of an
/// answer this module is willing to read, and what an answer means once it is
/// here.
///
/// The asking itself lives in `FilePopularityStore`; everything it *decides*
/// lives here, so the decisions can be tested without a network. That split is
/// `UpdateService`'s — the request is four lines there too, and
/// `UpdateCheck.evaluate` is what says what came back.
enum PopularityRefresh {
    /// The counts cover a thirty-day window and are republished daily. Asking
    /// oftener spends somebody's bandwidth on a figure that has not moved, and
    /// the only thing it buys is a search result in a different order.
    static let interval: TimeInterval = 24 * 60 * 60

    /// Measured 2026-09-13: the two documents are 453,903 and 399,502 bytes. Ten
    /// times the larger leaves room for the catalogue to grow for years and
    /// still refuses whatever a moved endpoint might be serving instead.
    ///
    /// **What this bounds is the parse and the file, not the download.**
    /// `URLSession.data(for:)` hands over a body it has already buffered, so by
    /// the time the count can be read the bytes are here. What bounds the wire
    /// is `FilePopularityStore`'s `wireDeadline`, on the session rather than on
    /// the request, because a request's own timeout is an *idle* one and
    /// restarts on every packet; this is what keeps whatever arrived out of
    /// `JSONSerialization` and off the disk.
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
    /// Three things collapse into "no new reading" and the store does something
    /// different about each, so they are three cases rather than one optional
    /// read two ways: `unchanged` keeps the reading *and* stamps the clock,
    /// `refused` keeps the reading and leaves the clock alone so the next
    /// launch tries again, and `use` is the only one that writes anything.
    enum Answer: Equatable {
        /// A document this build could read. The only case that replaces a
        /// reading — including the degenerate document, `{"formulae":{}}`,
        /// which `InstallCounts.parse` answers with no counts in it rather
        /// than with nil. That is the endpoint saying "nobody installed
        /// anything", which is a thing it is entitled to say and which search
        /// then ranks by exactly as it ranks with no reading at all: brew's own
        /// order. What must never become that value is `refused`.
        case use(InstallCounts)
        /// A 304: what is already stored is current.
        case unchanged
        /// The reason, for the log. Never an empty reading — a refusal that
        /// became `[:]` would announce a world in which nobody installs
        /// anything, and search would rank against it.
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
