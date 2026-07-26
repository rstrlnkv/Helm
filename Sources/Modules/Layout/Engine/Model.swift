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

    public init(before: String, after: String, app: String) {
        self.before = before
        self.after = after
        self.app = app
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
    public let conversionsToday: Int

    public init(enabled: Bool, automatic: Bool, suspended: Bool,
                lastConversion: ConversionEvent?, conversionsToday: Int) {
        self.enabled = enabled
        self.automatic = automatic
        self.suspended = suspended
        self.lastConversion = lastConversion
        self.conversionsToday = conversionsToday
    }
}
