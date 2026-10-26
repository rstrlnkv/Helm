import CoreGraphics

/// **The three widths `SettingsToolbar` lays its search item out by.** `actionsToSearch` and
/// `searchWidth` are readings of Helm's own toolbar in a 1060-point window; `searchFloor` is Helm's
/// choice, not a reading.
enum ShellBarLayout {

    /// The space between the actions and the search, measured.
    nonisolated static let actionsToSearch: CGFloat = 4

    /// The search field's width when it has all the room it wants, measured.
    nonisolated static let searchWidth: CGFloat = 283

    /// The narrowest an open search field is made. Helm's choice, not a
    /// reading.
    nonisolated static let searchFloor: CGFloat = 120
}
