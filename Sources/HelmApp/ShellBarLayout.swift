import CoreGraphics
import HelmUI

/// **The five numbers `SettingsToolbar` lays the actions and the search item out by.** `actionsToSearch` and
/// `searchWidth` are readings of Helm's own toolbar in a 1060-point window; `itemGap` is the Figma Kit's,
/// `actionsSearchPad` follows from it and `actionsToSearch`, and `searchFloor` is Helm's choice, not a reading.
enum ShellBarLayout {

    /// The space between items, the Figma Kit's: 8. What the actions and the search are laid out to
    /// stand apart (`actionsSearchPad`); the tabs' distance from the actions is `SettingsToolbar.tabsToActions`,
    /// a reading of its own that happens to be 8 too. Read at 1060 in both looks the actions to the search
    /// stood 7.5, not 8 (tester), the half point unexplained.
    nonisolated static let itemGap: CGFloat = HelmSpace.s4

    /// The space AppKit itself leaves between the actions and the search, measured.
    nonisolated static let actionsToSearch: CGFloat = 4

    /// What the hosted actions view adds on its trailing side to make `itemGap` of `actionsToSearch`.
    nonisolated static var actionsSearchPad: CGFloat { itemGap - actionsToSearch }

    /// The search field's width when it has all the room it wants, measured.
    nonisolated static let searchWidth: CGFloat = 283

    /// The narrowest an open search field is made. Helm's choice, not a
    /// reading.
    nonisolated static let searchFloor: CGFloat = 120
}
