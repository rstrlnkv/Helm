import CoreGraphics
import HelmUI

/// **The seven numbers `SettingsToolbar` lays the actions and the search item out by.** `actionsToSearch` and
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

    /// The magnifier a Flat search folds to: its width and, as the plate holding the field, its height. The Figma
    /// Kit's 36.
    nonisolated static let searchCollapsedWidth: CGFloat = 36

    /// The plate's height under Flat, the same 36.
    nonisolated static let searchPlateHeight: CGFloat = 36

    /// What the Flat search item and the tabs are set to: whether the tabs fold, how wide the plate is, whether it
    /// shows the magnifier.
    struct SearchPlan: Equatable {
        let tabsFolded: Bool
        let width: CGFloat
        let collapsed: Bool
    }

    /// **The one rule for a Flat bar's search and tabs, from the room Helm itself lays out** (`SettingsToolbar
    /// .settleFlat`), never from the field's own frame, so a plan does not depend on its own last output and
    /// needs no margin against flicker. The order is the plan's. On the shown window (build 1701) the tabs were seen folding
    /// early and staying folded, from `checkOverflow` folding them itself; under Flat that now asks for a settle
    /// instead, and a shown window, after this fix, kept the tabs whole while the field
    /// went from an AX frame of 285 at 1060 to 192 at 860 (the plate itself was measured only at 1060, 283, and the AX
    /// frame was 2 over it at 1060, the only width where both were read); the field down
    /// to 120, the magnifier and the fold are not yet seen there. `roomWholeTabs` and `roomFoldedTabs` are what is left of the bar for the
    /// search with the tabs whole and with them folded. Magnifier first: the field gives way from `searchWidth` to
    /// `searchFloor`, then collapses to the magnifier, and the tabs fold only when they still do not fit beside the
    /// magnifier.
    ///
    /// `editing` is a press, ⌘F or a VoiceOver press that opened the field, or its editor being up. `hasQuery` is
    /// a query left in the field, which counts as editing: **a query is never hidden behind a glyph** (the rule
    /// `restSearch` holds under Glass). An editing field keeps the floor even where it overflows.
    /// `alwaysCollapse` is the setting Always Collapse Search: with an empty, idle field the magnifier wherever the
    /// room. A room that is not finite (NaN or ±∞) or below 0 reads as 0.
    nonisolated static func searchPlan(roomWholeTabs: CGFloat, roomFoldedTabs: CGFloat,
                                       editing isOpen: Bool, hasQuery: Bool, alwaysCollapse: Bool) -> SearchPlan {
        let editing = isOpen || hasQuery
        let rests = alwaysCollapse && !editing
        func room(_ value: CGFloat) -> CGFloat { value.isFinite ? max(0, value) : 0 }
        let whole = room(roomWholeTabs), folded = room(roomFoldedTabs)
        let floor = searchFloor, widest = searchWidth, magnifier = searchCollapsedWidth
        if editing {
            if whole >= floor { return SearchPlan(tabsFolded: false, width: min(widest, whole), collapsed: false) }
            return SearchPlan(tabsFolded: true, width: min(max(folded, floor), widest), collapsed: false)
        }
        if !rests, whole >= floor {
            return SearchPlan(tabsFolded: false, width: min(widest, whole), collapsed: false)
        }
        if whole >= magnifier { return SearchPlan(tabsFolded: false, width: magnifier, collapsed: true) }
        if !rests, folded >= floor { return SearchPlan(tabsFolded: true, width: min(widest, folded), collapsed: false) }
        return SearchPlan(tabsFolded: true, width: magnifier, collapsed: true)
    }
}
