import CoreGraphics

/// The sizes only Autopilot draws: the cap on a button that carries a rule's name, the rule editor sheet, and the
/// floors of its pickers, which `HelmPickerWidth.fitting` widens to the longest label in the current language.
enum AutopilotLayout {
    /// The widest the turn-off button's label may ask for before it truncates. A rule's name is the person's own text
    /// with no bound, and `HelmWrappingRow` measures children at their ideal width, so without a cap a long name would
    /// overflow the pane rather than wrap. 440 sits under the narrowest pane, `SettingsWindow.minSize`'s width less
    /// `ShellGeometry.sidebarRange`'s widest sidebar (the sum is on `DuplicatesLayout`), less the form insets.
    static let turnOffButtonCap: CGFloat = 440
    /// The rule editor sheet; the conditions, the action and the dry run scroll inside it.
    static let editorSize = CGSize(width: 640, height: 620)
    /// The module's plate beside the rule's name in the editor.
    static let editorPlate: CGFloat = 26
    static let fieldPicker: CGFloat = 150
    /// A comparison or a sort scheme: two to four short words.
    static let shortPicker: CGFloat = 140
    static let kindPicker: CGFloat = 160
    static let actionPicker: CGFloat = 200
    /// Days or megabytes, typed.
    static let numberField: CGFloat = 70
}
