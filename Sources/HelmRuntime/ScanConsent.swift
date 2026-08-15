import Foundation

/// What the person is told about the reads nobody is watching, and how their
/// answer is written down.
///
/// **The switch existed and had no writer.** `AppSettings.disabledScans` decides
/// whether `ScanCoordinator` walks the volume while the Mac is idle, and until
/// this screen nothing in `Sources/` ever wrote it: the only way to learn that
/// Helm reads the disk twice a day was the log. This is the arithmetic behind
/// that screen — which rows there are and what an answer does to the stored
/// list — kept here beside `ScanRunner` and `ScanSchedule` rather than in the
/// view, for the reason those two give.
public enum ScanConsent {

    public struct Row: Equatable, Sendable {
        public let id: String
        /// Whether this scan may run. The stored value is an off-list, so the
        /// switch is its negation and is spelled once, here.
        public let isOn: Bool
        /// When it last came back with a report, if it ever has.
        public let lastRun: Date?
    }

    /// One row per background scan, in the order the scans are declared, or nil
    /// while the off-list has not been read.
    ///
    /// **Filtered to modules that are on.** `ScanCoordinator.run` starts with
    /// `host.liveModule(id)`, which a switched-off module has none of, so a row
    /// for it would be a switch over something that cannot happen either way.
    ///
    /// **`disabledScans` is optional because the read is not free.** The list is
    /// sealed, so getting it can reach the login keychain — and on an ad-hoc
    /// build that is an authorization dialog, which is why it cannot be read on
    /// the path that builds the screen (`MenuBarSettingsView`). Nil is "not read
    /// yet" and draws nothing. It is deliberately not the empty set: an empty
    /// off-list means *every* scan is on, so standing in for an unknown answer
    /// with it would show a whole-volume walk switched on to somebody who has
    /// never said so. Nil is also not `[]` on the way out — no rows because
    /// there is nothing to ask about is a different sentence from nothing to say
    /// yet, and the screen draws its heading over one and not the other.
    public static func rows(scannable: [String], enabled: Set<String>,
                            disabledScans: Set<String>?,
                            lastRun: [String: Date]) -> [Row]? {
        guard let disabledScans else { return nil }
        return scannable
            .filter(enabled.contains)
            .map { Row(id: $0, isOn: !disabledScans.contains($0), lastRun: lastRun[$0]) }
    }

    /// The off-list after one row is answered.
    ///
    /// Built from the stored list rather than from the rows on screen: a module
    /// that is switched off has no row and still has an answer stored against
    /// it, and rewriting the list from what the screen could see would switch
    /// that scan back on the moment its module returned.
    public static func toggling(_ id: String, to on: Bool,
                                in disabled: Set<String>) -> Set<String> {
        var next = disabled
        if on { next.remove(id) } else { next.insert(id) }
        return next
    }
}
