import Foundation

/// One conversion, as it happened.
///
/// The words live here and in memory and nowhere else: they are never logged
/// and never written to disk. A key tap sees passwords typed into fields an app
/// forgot to mark secure, and the only safe place for that is somewhere already
/// gone.
public struct ConversionEvent: Codable, Equatable, Sendable {
    public let before: String
    public let after: String
    /// Bundle id of the app it happened in, so an undo cannot land elsewhere.
    public let app: String
    /// The character that ended the word — it was deleted and retyped with the
    /// replacement, so undoing has to do the same or it eats one character too
    /// few. Empty when the conversion came from the hotkey mid-word.
    public let trailing: String
    /// True when the gesture asked for this word by name, past the dictionary.
    /// The words in an automatic conversion were vouched for; a forced one is
    /// arbitrary typed text — possibly a field nothing recognised as secure —
    /// and the page must not offer to write it to disk («Never this word»).
    public let forced: Bool

    public init(before: String, after: String, app: String, trailing: String = "",
                forced: Bool = false) {
        self.before = before
        self.after = after
        self.app = app
        self.trailing = trailing
        self.forced = forced
    }
}

/// What the settings page shows.
public struct LayoutState: Codable, Equatable, Sendable {
    public let enabled: Bool
    public let automatic: Bool
    /// True while secure input is on: the module is deliberately silent, and
    /// silence needs a visible reason.
    public let suspended: Bool
    public let lastConversion: ConversionEvent?
    /// True when `lastConversion` was taken back. The record and the right to a
    /// blind undo are different things: the undo dies with the caret's next
    /// move, but the row on the page — and its «Never this word» button — must
    /// outlive it, or the button is reachable only for changes nobody rejected.
    public let lastConversionUndone: Bool
    public let conversionsToday: Int
    /// Installed layouts macOS has no spelling dictionary for, by source id.
    ///
    /// Empty on most Macs. When it is not, «Fix as I type» is dead for every
    /// pair that includes one of these and nothing on the page said so — the
    /// switch stayed on and the badge stayed green. The ids travel rather than
    /// the names: naming an input source is the UI's job (`InputSourceInfo`),
    /// and the engine may not import `HelmUI`.
    public let noDictionary: [String]

    public init(enabled: Bool, automatic: Bool, suspended: Bool,
                lastConversion: ConversionEvent?, lastConversionUndone: Bool,
                conversionsToday: Int, noDictionary: [String] = []) {
        self.enabled = enabled
        self.automatic = automatic
        self.suspended = suspended
        self.lastConversion = lastConversion
        self.lastConversionUndone = lastConversionUndone
        self.conversionsToday = conversionsToday
        self.noDictionary = noDictionary
    }
}
