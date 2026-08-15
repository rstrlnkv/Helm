import CoreGraphics

/// The one width this module has to legislate rather than measure: a rule's
/// name is the person's own text with no bound, so the button that names it
/// («Turn off "…"») cannot be trusted to fit any pane at its natural size.
enum AutopilotLayout {
    /// The widest the turn-off button's label may ask for before it truncates.
    ///
    /// Set against the narrowest pane a page can be given — 540 pt, the
    /// smallest window with the sidebar dragged wide — less the form insets and
    /// the button's own bezel, with slack. `TheReturnBannerFoldsItsButtonsTests`
    /// holds the arithmetic; `HelmWrappingRow` measures children at their ideal
    /// width, so without this cap a long rule name would overflow the pane
    /// rather than wrap.
    static let turnOffButtonCap: CGFloat = 440
}
