import CoreGraphics

/// **Space has one ladder: 2 · 4 · 6 · 8 · 12 · 18 · 28 · 40 pt.**
///
/// Counted before it existed: twenty-four distinct padding values and thirteen
/// distinct gaps across the settings window, against three declared tokens
/// (`v3/audit.js`, check `space-off-the-ladder`). That is not a design with
/// twenty-four decisions in it — it is one decision taken twenty-four times by
/// eye, and nobody could see the difference between 10 and 12 pt anyway. The
/// same disease the type scale had.
///
/// The steps are close together where they are small, because 2 pt matters at
/// 4 pt and does not at 40, and above that each is about half again the one
/// below — near enough that a value chosen by eye has one obvious neighbour to
/// round to. A number off the ladder is a number somebody has to argue for,
/// which is the point. `LaddersAreTheStepsTheyClaimTests` holds both halves of
/// that shape, because nothing else can see a token leave its own step.
///
/// **Landing the ladder is not adopting it.** `SpaceLadderRatchetTests` counts
/// what the tree still spells by hand and only ever goes down; these constants
/// are what it goes down *to*. Nothing is swept here — the sweep is a change to
/// layout, and this is a change to vocabulary.
public enum HelmSpace {
    /// Hairline separation: a glyph from the word it belongs to.
    public static let s1: CGFloat = 2
    /// Inside a control: a badge's own padding.
    public static let s2: CGFloat = 4
    /// A label from its value.
    public static let s3: CGFloat = 6
    /// Between rows of one list.
    public static let s4: CGFloat = 8
    /// A card's inner padding, and the gap between two cards.
    public static let s5: CGFloat = 12
    /// Between the blocks of one section.
    public static let s6: CGFloat = 18
    /// Between sections of a page.
    public static let s7: CGFloat = 28
    /// A page's own margins, and the space under its header.
    public static let s8: CGFloat = 40
}

/// **A corner has one ladder: 4 · 6 · 10 · 14 · 26 pt.**
///
/// Sixteen distinct radii were counted against three declared tokens on the
/// mockup side, and the app's own reading is in `RadiusLadderRatchetTests` —
/// measured off the render rather than the source, because radius is the one
/// ladder that survives into `CALayer.cornerRadius` and can therefore be caught
/// even where nobody typed it.
///
/// Five steps, and each names the thing it belongs to rather than a size: the
/// call site should say what it is drawing, not how round it wants it.
///
/// **Two of the five are already what the app draws**, spelled as numbers: the
/// panel's glass is `.rect(cornerRadius: 26)` and the shape a panel card and a
/// panel well share is 14. Those literals are not swept here — this commit lands
/// the vocabulary — so until they are, `frame` and `panel` are names for numbers
/// typed somewhere else, which is the state a `periphery` run will report as
/// unused and which is not a defect.
public enum HelmRadius {
    /// A swatch, a tag, anything smaller than a control.
    public static let tiny: CGFloat = 4
    /// A control: a button, a field, a segment.
    public static let ctl: CGFloat = 6
    /// The one card. It replaces `HelmSurface.cardRadius`, which was 12 — on no
    /// step, and indistinguishable in the render from SwiftUI's own grouped-`Form`
    /// section card, which is 12 as well and is nobody here's to change.
    public static let card: CGFloat = 10
    /// A frame around cards: the panel's own card and the well inside it.
    public static let frame: CGFloat = 14
    /// The panel. Big because it hangs off the menu bar with nothing around it.
    public static let panel: CGFloat = 26
}
