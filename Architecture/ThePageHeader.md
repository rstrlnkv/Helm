# The page header

In the settings window a page's header and its controls live in the window's toolbar: an app-owned `NSToolbar` built by `SettingsToolbar` (`Sources/HelmApp/SettingsToolbar.swift`), a cached `NSToolbar` for each page that declares toolbar content and one shared by the pages that declare none, told what to show on every page change and assigned to the window by that class alone. The window the app builds wears it (`SettingsWindow.Bar.toolbar`, the default). The window's `.pageBar` build, which only tests construct, has no toolbar and holds Helm's own page bar instead: one view at the top of the card's clip, built once by `SettingsWindow` (`ShellPageBar`, `Sources/HelmApp/ShellPageBar.swift`; its class header holds the reasons: why a page that has declared before is shown the instant it is selected, the grace before a page with nothing declared falls back to the name, why a frozen page is remembered and shown without its closures).

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

`SettingsToolbar`'s bar, left to right: a spacer that carries the name over to the card, where the card leaves room for one; the name (the module's plate and
its name, drawn only under `PageBarStyle.moduleName`); a flexible space; the tabs,
centred; a flexible space; **one** custom-view item for the whole action capsule;
the search field. A status-bearing page draws the shared name-only bar instead —
spacer, name, a flexible space, `helm.status` at the trailing edge — and under
`PageBarStyle.moduleName` that bar always lists `helm.status`, drawing nothing on a page with no status, so every status-less module that draws it never sees that item move
(`SettingsToolbar.identifiers`, `StatusZoneView`). The window tells the toolbar where the card is (`ShellContentView`'s `cardMoved`, delivered a turn of the main queue after the layout that moved it, the window delivering the first itself), and the toolbar tells the shell only that a window took a bar. The pane starts where AppKit's strip ends and Helm adds nothing to its safe area.

**The actions are one capsule, not one view or item per action.** The capsule
(`HelmToolbarActionsCapsule`, `Sources/HelmUI/DesignSystem/HelmToolbarActions.swift`) reserves the width of every
*declared* action (`HelmToolbarActionsCapsule.reserveWidth`) and only the visible set morphs inside it; an
action inapplicable on its tab is dimmed through the capsule's model and one that belongs to
other tabs is left out of the visible set; the capsule's header holds why. The two hosts differ in what holds the capsule. In the
toolbar it is one `NSToolbarItem`, and the bar's identifier list never changes for an action dimmed or left out: the tabs and the actions both live in `NSToolbar`'s own layout, not SwiftUI's,
and an item that hides collapses its width in a relayout AppKit itself animates, which no curve of this
app reaches. In the page bar `ShellBarActions` hosts it in one view as wide as the reserve, so the zone's
frame does not move when an action shows or hides.

In the `.pageBar` build the zones are the name, the tabs, the actions, the search and the status (`ShellPageBarView.Zone`), framed by `ShellBarLayout`. The name and the status are `ShellPageBar`'s own hosted views (`NameZoneView`, `StatusZoneView`); the other three are `ShellBarTabs`, `ShellBarActions` and `ShellBarSearch`. The name is drawn under both styles, with the module's plate only under `PageBarStyle.moduleName`; the status only under that style on a page with no tabs, no actions and no search.

Left to right in the page bar: the name, which starts `ShellBarLayout.leading` in, or right of the window's buttons where they
stand over the card; the tabs, centred on the bar and held between the name and what stands at the right; the
actions capsule; the search field, last. A status, where one is drawn, ends `ShellBarLayout.statusTrailing` from
the bar's right edge. `ShellBarLayout.frames` answers one frame per zone and two verdicts — the tabs folded to one
item, the search folded to its magnifier — and its header holds what gives way and in which order;
`ShellPageBarView` puts each zone's view in its frame and hides a zone the layout calls absent.

## Toolbar actions

`HelmToolbarAction.Kind` is the one shape an action takes: a button, a toggle, a
`.segmented` pair (Hosts' Table/Plain-text switcher) or a `.menu` of checkmarked
items, each with its own press — `Sources/HelmUI/DesignSystem/HelmWindowToolbar.swift`
holds what each draws, how `isVisible`, `isEnabled` and `isBusy` differ, and why a
kind cannot be two at once. In the toolbar, whether a segmented action slides on a press depends on
`SettingsToolbar.centredIdentifiers(_:)`, whose header has what was measured. The
overflow floor, when even the capsule does not fit, is
`NSToolbarItem.menuFormRepresentation` (`SettingsToolbar.patchActionsMenu`). In the page bar a segmented action stands at the right with every other action, and its reserve is what its switcher draws
(both looks draw the same widths) (`ShellBarActions.segmentedReserveWidth`), and there is no overflow menu: out of room, the search narrows to `ShellBarLayout.searchFloor`, then the tabs
fold, then the search folds to its magnifier, then the name truncates, and the capsule keeps its width (`ShellBarLayout`'s header).

## The tabs and the search field

The tabs have one form, `HelmToolbarSwitcher`
(`Sources/HelmUI/DesignSystem/HelmToolbarSwitcher.swift`), labelled by
`ToolbarSwitcherStyle`, which the bar's right-click menu changes for all of them;
its `compact` flag folds it to the current tab. In the toolbar it folds before AppKit would push the strip
into its overflow menu, and `SettingsToolbar`'s "Folding the tabs" section decides
when; in the page bar `ShellBarLayout` decides, and the verdict is one
threshold in the bar's width. The switcher wears Helm's flat cell (`HelmFlatSegmentedCell`) unless
the environment's `helmSwitcherCell` asks for AppKit's, and only `SettingsToolbar` asks, under Liquid Glass, on the tabs and on the
actions capsule, so the toolbar's segmented controls wear AppKit's cell under Liquid Glass and every other switcher, and the toolbar's under Flat, wears Helm's (ARCHITECTURE.md § Ink and contrast). In the page bar, `ShellBarTabs` keeps two switchers rooted, the whole strip and the folded one, and its one plate holds whichever `ShellBarLayout` says. A press on a tab of the whole strip asks its cell to slide the pick to it over `HelmMotion.interfaceDuration` (a cut under Reduce Motion, on the first draw, when the page sets the selection, and for a tab chosen from the folded strip's menu; a republication that also renames a tab or moves a dot ends the slide); the page under the bar changes at once. The slide was not seen on a screen, and a cell that is not Helm's is not asked to slide. A tab may carry a dot (`HelmToolbarTab.needsAttention`): AppKit draws a segment's image before its label, so
the dot is the segment's image, and a folded switcher marks the tab in its menu with a badge. How the dot reads over the glass plate on a real screen was not measured. In the toolbar the search field is an `NSSearchToolbarItem` carrying an `NSSearchField`
`SettingsToolbar` builds itself (`makeSearchItem`): Return, and only Return, runs a
page's `onSubmit`. With `AppSettings.alwaysCollapseSearch` on, an empty idle field
rests as AppKit's magnifier at every width, through one rest predicate
(`SettingsToolbar.restSearch(_:)`; `PageBar.searchRestCap` holds the reading). In the page bar the search field is an `NSSearchField` on a plate of the bar's own, with the magnifier it folds to
(`ShellBarSearch`): the same Return rule, with the same setting on an empty idle field rests as the magnifier at every width, and a field in use is never folded for room
(`ShellBarSearch.isInUse`, `ShellBarLayout`'s header).

## The bar's menu and style

The bar has one right-click menu (`ShellBarMenu`), filled the same way for the toolbar and for `ShellPageBar`.
It has an Appearance section (Flat, Liquid Glass) on every page, and General
mirrors it in the row "Toolbar style". Two bars draw by that setting: the page bar's zones (`ShellPageBar` hands it to them) and the toolbar, whose
`SettingsToolbar` reads it once, when it reads a bar's shape (`ShapeSignature.look`); it hears `.helmBarAppearanceChanged`, as it hears a
change of page-bar style, and builds the bar of the page on the window afresh; a cached bar of another page is built afresh when that page is next shown, so a change of look puts one
fresh toolbar on the window and a bar built under the other look is never given back to a page; a look written equal to the one worn posts the same notification and rebuilds nothing. The look is handed down from the bar to its
items, and no item reads the setting itself. It changes what two items are made of, and only those:

| item | Liquid Glass | Flat |
|---|---|---|
| tabs | a bordered item, AppKit's platter behind AppKit's cell | `isBordered = false` (AppKit's platter off), Helm's flat cell on a `ShellBarPlate` wearing the flat look, which follows the window's activity; a press slides the pick |
| actions | the capsule on glass, `\.helmSwitcherCell` AppKit's for a segmented entry | the capsule on a flat fill (`\.helmBarAppearance`), dimmed in an inactive window by the name zone's numbers through the model's `appearsActive`, which is told the window's activity and rebuilds no host (the glass capsule's host is rebuilt for it), a segmented entry in Helm's cell |

The name and the search field are not made differently under either look. The widths the tabs and a segmented entry are measured at are measured wearing the cell
the look puts on them, and a measurement is kept with the look it was taken under. **Not seen on a screen:** the plate under the cell inside a toolbar item, that no platter of
AppKit's is behind it, the slide inside the toolbar, and the capsule drawn flat. `HelmBarAppearance`'s header has the two defaults.

In the toolbar the menu is answered by
the same local monitor as the magnifier press, so a Control-click on the collapsed
magnifier has one owner; the same menu is each centre switcher's `NSView.menu`,
which is what VoiceOver opens. In the page bar `ShellPageBarView` answers the menu anywhere on the bar except over the window buttons' capsule, and a resting search field answers it.

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
