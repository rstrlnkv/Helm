import Foundation

/// What the person is told about the reads nobody is watching, and how their
/// answer is written down.
///
/// `AppSettings.disabledScans` decides whether `ScanCoordinator` walks the
/// volume while the Mac is idle; this is the arithmetic behind the screen that
/// writes it (which rows there are, what an answer does to the stored list),
/// beside `ScanRunner` and `ScanSchedule` rather than in the view, so it is
/// testable.
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
    /// sealed, so reading it can raise a keychain dialog on an ad-hoc build, and
    /// it is not read on the path that builds the screen
    /// (`MenuBarSettingsView`). Nil is "not read yet" and draws nothing; the
    /// empty set would mean *every* scan is on. Nil is also not `[]` on the way
    /// out: the screen draws its heading over "nothing to ask about" and not
    /// over "nothing to say yet".
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
