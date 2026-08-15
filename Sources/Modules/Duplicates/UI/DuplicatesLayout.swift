import CoreGraphics
import HelmUI
import Module_Duplicates_Engine

/// What fits in the duplicates toolbar, at the width there actually is.
///
/// The row wants four things: the folder it searched and **three** controls —
/// choose, search, and mark every extra copy. Measured by drawing the real row
/// offscreen in each of the eight languages and finding the narrowest pane it
/// draws whole in, then again by summing real AppKit control metrics; the two
/// agree within 4 pt, and `DuplicatesBarWidthTests` keeps the second one
/// running against the shipped strings:
///
/// | row                                       | needs   | widest |
/// |-------------------------------------------|---------|--------|
/// | path + three labelled controls            |  721 pt | fr     |
/// | ditto, mark-all as a symbol               |  607 pt | fr     |
/// | ditto, search as a symbol too             |  502 pt | fr     |
///
/// The pane is the window's content less the fixed 250 pt sidebar — 810 pt at
/// the default window and 610 at the minimum.
///
/// **The count is not a toolbar item any more.** `showsCount` gated the one
/// clone-corrected figure on the page behind 1040 pt of pane — measured
/// correctly, and first reached at a 1290 pt window, wider than the app ever
/// opens. The total lives under the floor note now, drawn at every width
/// (`DuplicatesSettingsPage`), and the threshold, its constant and its rung of
/// the ladder went with it.
///
/// The path is the piece that truncates, but only down to a floor: `/…re` is
/// not a location, and a path that says nothing costs the row its whole point.
/// So the row gives up, in this order, what repeats what is already on screen —
/// and gives up a label before it gives up a control:
///
/// 1. **the mark-all label**: every group header already reads `Mark the extra
///    copies`, so the words are the redundant part — but on twenty groups the
///    button itself saves nineteen clicks, so it stays as `checklist` (35 pt
///    against 175);
/// 2. **the search label**, `arrow.clockwise` (31 pt against 137).
///
/// Nothing disappears. At the narrowest window the row is a path, one labelled
/// control and two symbols, and that is 502 pt inside a 610 pt pane.
///
/// This table used to say "both controls | 266 pt" for a row that has three,
/// because the measuring script summed two of them.
struct DuplicatesLayout {
    let availableWidth: CGFloat

    /// The two widths. Not private: `DuplicatesBarWidthTests` holds *these*
    /// numbers against the shipped strings, and a guard that reads its own copy
    /// of the thing it guards goes on passing whatever the thing becomes.
    ///
    /// 721.0 measured in French, plus slack.
    static let barWithMarkAllLabel: CGFloat = 760
    /// 607.0 measured in French, plus slack.
    static let barWithSearchLabel: CGFloat = 660

    /// How wide the keep-policy pop-up has to be to say what it is set to.
    ///
    /// Measured rather than written down, for the reason `HelmPickerWidth`
    /// exists: the labels are whole clauses, and they name folders macOS
    /// translates — so the widest of them is not a number anybody can know in
    /// advance. The floor is only there to keep the control from collapsing
    /// where a language is unusually terse.
    ///
    /// Static and language-taking, so the page and `ThePolicyRowFitsThePaneTests`
    /// read one arithmetic: a width test holding its own copy of the width goes
    /// on passing whatever the page starts drawing.
    static func policyPickerWidth(language: AppLanguage = AppLanguage.current) -> CGFloat {
        HelmPickerWidth.fitting(KeepPolicy.allCases.map { DupStr.policyName($0, language: language) },
                                minimum: 200)
    }

    /// The basket row's one rung: the count, the clear control and the
    /// prominent trash button. 587.3 measured in German with a real library's
    /// figures, plus slack — below this the clear control keeps its act as a
    /// symbol and gives up only its words, the same trade the toolbar's
    /// mark-all makes. `TheBasketRowFitsThePaneTests` holds it.
    static let basketWithClearLabel: CGFloat = 620

    var labelsMarkAll: Bool { availableWidth >= Self.barWithMarkAllLabel }
    var labelsSearch: Bool { availableWidth >= Self.barWithSearchLabel }
    var labelsClear: Bool { availableWidth >= Self.basketWithClearLabel }
}
