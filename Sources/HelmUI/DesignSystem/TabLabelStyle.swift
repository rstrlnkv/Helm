import Foundation

/// How the panel's tabs are labelled — the question, as it is asked on the
/// settings page.
///
/// Four answers, and `automatic` is the one that is not a taste: it hands the
/// question to `TabStripFit`, which measures the names against the panel's width
/// and answers for the strip that is actually there. The other three are the
/// person's own answer, kept whatever the measurement would have said.
///
/// **The default is `text`**, which is what the panel has drawn since it
/// shipped. Automatic is offered, not assumed: a stored answer that was never
/// given is not an answer.
public enum TabLabelStyle: String, CaseIterable, Sendable {
    case automatic
    case text
    case glyphAndText
    case glyph

    /// A value written by a build that had a case this one does not reads as
    /// the one everybody starts with, rather than as a crash.
    public init(stored: String) {
        self = TabLabelStyle(rawValue: stored) ?? .text
    }
}

/// What a tab actually wears, which is what the strip draws from.
///
/// **Separate from the choice on purpose.** `automatic` is a question and not a
/// face, so a strip handed it would have to decide what to do with a value that
/// means «work it out» — and `glyph` is a face a strip is sometimes refused:
/// chosen for a strip where one tab has no glyph, that tab drew an empty padded
/// button, a control with nothing in it and nothing to read. `TabStripFit` is
/// the one place either of those is resolved, and a face is what it hands back,
/// so neither state can be reached from anywhere else.
public enum TabLabelFace: String, CaseIterable, Sendable {
    case text
    case glyphAndText
    case glyph

    public var showsText: Bool { self != .glyph }
    public var showsGlyph: Bool { self != .text }
}
