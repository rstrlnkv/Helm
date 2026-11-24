import CoreGraphics
import HelmUI
import Module_Duplicates_Engine

/// The widths the page draws at. **There is no ladder**: no label turns into a
/// symbol and no control goes, because every width the page can have holds all
/// of them.
///
/// The settings window is 1207 pt wide at its minimum (`SettingsWindow`'s
/// `minSize`), and the card takes the window less the 200 pt sidebar
/// (`ShellGeometry.defaultSidebarWidth`) and a 4 pt inset
/// (`ShellGeometry.inset`): 1003 pt, the narrowest pane the page is given.
///
/// The toolbar is measured by drawing the real row offscreen in each of the
/// eight languages and by summing AppKit control metrics (the two agree within
/// 4 pt); the basket row by the drawing, in German with a real library's figures:
///
/// | row                                                   | needs     | widest |
/// |-------------------------------------------------------|-----------|--------|
/// | toolbar: path and three labelled controls             |  721 pt   | fr     |
/// | basket: count, labelled clear control, trash button   |  587.3 pt | de     |
///
/// Both fit in 1003 pt, so the toolbar's controls and the basket's keep their
/// words at every width, and the path is the one piece that truncates, down to
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
    /// Measured, for the reason `HelmPickerWidth` exists: the labels are whole
    /// clauses naming folders macOS translates, so the widest is not knowable in
    /// advance. The floor keeps the control from collapsing in a terse language.

    static func policyPickerWidth(language: AppLanguage = AppLanguage.current) -> CGFloat {
        HelmPickerWidth.fitting(KeepPolicy.allCases.map { DupStr.policyName($0, language: language) },
                                minimum: 200)
    }
}
