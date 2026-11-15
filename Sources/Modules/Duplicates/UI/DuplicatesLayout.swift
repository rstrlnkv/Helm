import CoreGraphics
import HelmUI
import Module_Duplicates_Engine

/// The widths the page draws at. **There is no ladder**: no label turns into a
/// symbol and no control goes, because every width the page can have holds all
/// of them.
///
/// The settings window is 1096 pt wide at its minimum (`SettingsWindow`'s
/// `minSize`), and the card takes the window less the sidebar and a 4 pt inset
/// (`ShellGeometry.inset`). A sidebar stored at its widest, 320
/// (`ShellGeometry.sidebarRange`), leaves 1096 − 320 − 4 = 772 pt, the narrowest
/// pane the page is ever given.
///
/// What the page needs is under that. The toolbar was measured by drawing the
/// real row offscreen in each of the eight languages and by summing real AppKit
/// control metrics (the two agree within 4 pt); the basket row only by the
/// drawing, in German with a real library's figures. Measured before the
/// strings moved into the module's catalog; the layout metrics did not change:
///
/// | row                                                   | needs     | widest |
/// |-------------------------------------------------------|-----------|--------|
/// | toolbar: path and three labelled controls             |  721 pt   | fr     |
/// | basket: count, labelled clear control, trash button   |  587.3 pt | de     |
///
/// Both fit in 772 pt, so the toolbar's controls and the basket's keep their
/// words at every width, and the path is the one piece that truncates — down to
/// `pathWidth`'s floor, because `/…re` is not a location.
enum DuplicatesLayout {

    /// How wide the folder's path is drawn in the toolbar: it truncates in the
    /// middle between these, and no further.
    static let pathWidth: ClosedRange<CGFloat> = 180...260

    /// The widest the outcome of a removal grows, so a named failure's Reveal
    /// button does not run to the right edge and sit under the Close button.
    static let outcomeWidth: CGFloat = 520

    /// How wide the keep-policy pop-up has to be to say what it is set to.
    ///
    /// Measured rather than written down, for the reason `HelmPickerWidth`
    /// exists: the labels are whole clauses, and they name folders macOS
    /// translates — so the widest of them is not a number anybody can know in
    /// advance. The floor is only there to keep the control from collapsing
    /// where a language is unusually terse.
    static func policyPickerWidth(language: AppLanguage = AppLanguage.current) -> CGFloat {
        HelmPickerWidth.fitting(KeepPolicy.allCases.map { DupStr.policyName($0, language: language) },
                                minimum: 200)
    }
}
