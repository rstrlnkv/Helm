import Foundation

/// How the panel's tabs are labelled.
///
/// Three answers to one question — how much of a tab is worth its row — and the
/// right one depends on things the app cannot see: how many tabs there are, how
/// long their names came out, and whether the person named them at all. A tab
/// called «Главная» needs no glyph; four tabs on a 300 pt strip need nothing
/// else.
public enum TabLabelStyle: String, CaseIterable, Sendable {
    case text
    case glyphAndText
    case glyph

    public var showsText: Bool { self != .glyph }
    public var showsGlyph: Bool { self != .text }

    /// A value written by a build that had a fourth case reads as the one
    /// everybody starts with, rather than as a crash.
    public init(stored: String) {
        self = TabLabelStyle(rawValue: stored) ?? .text
    }
}
