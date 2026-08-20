import Foundation

/// How the panel's tabs are labelled.
///
/// **The answer to a measurement, not a setting.** It was three cases behind a
/// pop-up on the settings page, and the pop-up is gone: `TabStripFit` measures
/// the names against the panel's width and answers with one of these. The third
/// case went with it — «glyph and text» is what a strip does when it has room
/// for both, which is the case where it also has room for the names alone.
///
/// `glyph` is only ever chosen for a strip where **every** tab has one. Set by
/// hand it could be chosen for a strip where one did not, and that tab drew an
/// empty padded button.
public enum TabLabelStyle: String, CaseIterable, Sendable {
    case text
    case glyph

    public var showsText: Bool { self == .text }
    public var showsGlyph: Bool { self == .glyph }
}
