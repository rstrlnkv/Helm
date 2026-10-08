# The page header

In the settings window a page's header and its controls live in Helm's own page bar — one view at the top of the card's clip, built once by `SettingsWindow` and told what to show on every page change (`ShellPageBar`, `Sources/HelmApp/ShellPageBar.swift`; its class header holds the reasons: why a page that has declared before is shown the instant it is selected, the grace before a page with nothing declared falls back to the name, why a frozen page is remembered and shown without its closures). The window has no `NSToolbar`.

A page says what it wants — tabs, actions, search — through
`HelmWindowToolbarChannel` and `.helmWindowToolbar(_:token:)`
(`Sources/HelmUI/DesignSystem/HelmWindowToolbar.swift`), so a module's UI target
never imports `HelmApp`; that file's headers hold why content is kept per page
token and how a generation number keeps an outgoing mount's late write from
overwriting the page on screen. A page that never calls it shows the name, and
under `PageBarStyle.moduleName` a status-bearing page's status, and nothing else;
that is not an error state. `command grep -rln '\.helmWindowToolbar(' Sources`
lists the files that publish.

## The bar's zones

The page bar's zones are the name, the tabs, the actions, the search and the status (`ShellPageBarView.Zone`), framed by `ShellBarLayout`. The name and the status are `ShellPageBar`'s own hosted views (`NameZoneView`, `StatusZoneView`); the other three are `ShellBarTabs`, `ShellBarActions` and `ShellBarSearch`. The name is drawn under both styles, with the module's plate only under `PageBarStyle.moduleName`; the status only under that style on a page with no tabs, no actions and no search.

Left to right: the name, which starts `ShellBarLayout.leading` in, or right of the window's buttons where they
stand over the card; the tabs, centred on the window and held between the name and what stands at the right; the
actions capsule; the search field, last. A status, where one is drawn, ends `ShellBarLayout.statusTrailing` from
the bar's right edge. `ShellBarLayout.frames` answers one frame per zone and two verdicts — the tabs folded to one
item, the search folded to its magnifier — and its header holds what gives way and in which order;
`ShellPageBarView` puts each zone's view in its frame and hides a zone the layout calls absent.

**The actions are one capsule, not one view per action.** `ShellBarActions` hosts `HelmToolbarActionsCapsule`
(`Sources/HelmUI/DesignSystem/HelmToolbarActions.swift`) in one view as wide as the reserve of every *declared*
action (`HelmToolbarActionsCapsule.reserveWidth`), so the zone's frame does not move when an action shows or
hides and only the visible set morphs inside it; an action inapplicable on its tab is dimmed through the
capsule's model, one that belongs to other tabs is left out of the visible set; the capsule's header holds why.

## Toolbar actions

`HelmToolbarAction.Kind` is the one shape an action takes: a button, a toggle, a
`.segmented` pair (Hosts' Table/Plain-text switcher) or a `.menu` of checkmarked
items, each with its own press — `Sources/HelmUI/DesignSystem/HelmWindowToolbar.swift`
holds what each draws, how `isVisible`, `isEnabled` and `isBusy` differ, and why a
kind cannot be two at once. A segmented action stands at the right with every other action, and its reserve is what its switcher draws
under each look (`ShellBarActions.segmentedReserveWidth`). The bar has no overflow menu: out of room, the search narrows to `ShellBarLayout.searchFloor`, then the tabs
fold, then the search folds to its magnifier, then the name truncates, and the capsule keeps its width (`ShellBarLayout`'s header).

## The tabs and the search field

The tabs have one form, `HelmToolbarSwitcher`
(`Sources/HelmUI/DesignSystem/HelmToolbarSwitcher.swift`), labelled by
`ToolbarSwitcherStyle`, which the bar's right-click menu changes for all of them;
its `compact` flag folds it to the current tab, and `ShellBarLayout` decides when: the verdict is one
threshold in the bar's width. `ShellBarTabs` keeps two switchers rooted, the whole strip and the folded one, and its one plate holds whichever `ShellBarLayout` says. A tab may carry a dot (`HelmToolbarTab.needsAttention`): AppKit draws a segment's image before its label, so
the dot is the segment's image, and a folded switcher marks the tab in its menu with a badge. How the glass lens draws the
dot on a real screen was not measured. The search field is an `NSSearchField` on a plate of the bar's own, with the magnifier it folds to
(`ShellBarSearch`): Return, and only Return, runs a page's `onSubmit`. With `AppSettings.alwaysCollapseSearch`
on, an empty idle field rests as the magnifier at every width, and a field in use is never folded for room
(`ShellBarSearch.isInUse`, `ShellBarLayout`'s header).

## The bar's menu and style

The bar has one right-click menu (`ShellBarMenu`): `ShellPageBar` hands it to the bar's view and fills it each
time it opens (`ShellBarMenu.fill`). It has an Appearance section (Flat, Liquid Glass) on every page, and General
mirrors it in the row "Toolbar style"; `ShellPageBar` hands the setting to its zones, so the window's bar draws by
it. `ShellPageBarView` answers the menu anywhere on the bar except over the window buttons' capsule; the same
menu is each tab switcher's `NSView.menu`, which is what VoiceOver opens, and a resting search field answers it.

`PageBarStyle` is a setting in Appearance: the module's plate and name at the bar's leading edge with a status at the trailing edge — the shipping default, and what `PageBarStyle.init(stored:)` answers for an empty or unrecognised store — or the name alone, with no plate and no status. The
environment value `helmPageBar` is what the window sets; where it is nil — a sheet,
a page mounted on its own — the header is drawn in the page rather than in a
toolbar that does not exist for it (ARCHITECTURE.md § The header strip).

## The header strip

The header strip is the system's 52 pt and lies over the page rather than above it:
`helmPageHeader` (`Sources/HelmUI/DesignSystem/HelmPageHeader.swift`) applies it as
a modifier, so content scrolls behind its material. A page whose top band stays put
draws `HelmPageHeader` as an ordinary view and gets no scroll-edge material; the
guard that reads these pages (`ThePageHeaderCarriesNoRuleTests`) hunts for both
spellings.

Over a scroll view there is no rule at rest; the whole strip lights for three
reasons — the pointer on it while the window is key, the page scrolled underneath,
the page declaring that what sits under the band is not a scroll view — from one
answer, `HelmPageHeader.isLit`, which feeds both the fill and the rule.

Under the settings window's bar the same light is `helmToolbarBackdrop`'s, and
whose band lies there depends on the system: `HelmBandChoice`
(`Sources/HelmUI/DesignSystem/HelmBandChoice.swift`) is read once from the running
macOS and handed down as one value, and its header holds the 26-versus-27 reasoning.
