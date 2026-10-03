# The page header

In the settings window a page's header and its controls live in the window's own
toolbar — one `NSToolbar` **per page**, built once and cached, owned by
`SettingsWindow` (`SettingsToolbar`, `Sources/HelmApp/SettingsToolbar.swift`; its
class header holds the reasons: why no page's toolbar is ever rewritten while it
is on screen, why none is user-customizable, the grace period before a page with
nothing declared falls back to the shared name-only bar).

A page says what it wants — tabs, actions, search — through
`HelmWindowToolbarChannel` and `.helmWindowToolbar(_:token:)`
(`Sources/HelmUI/DesignSystem/HelmWindowToolbar.swift`), so a module's UI target
never imports `HelmApp`; that file's headers hold why content is kept per page
token and how a generation number keeps an outgoing mount's late write from
overwriting the page on screen. A page that never calls it shows the name, and
under `PageBarStyle.moduleName` a status-bearing page's status, and nothing else;
that is not an error state. `command grep -rln '\.helmWindowToolbar(' Sources`
lists the pages that publish.

## The bar's zones

Left to right: the sidebar's tracking separator; the name (the module's plate and
its name, drawn only under `PageBarStyle.moduleName`); a flexible space; the tabs,
centred; a flexible space; **one** custom-view item for the whole action capsule;
the search field. A status-bearing page draws the shared name-only bar instead —
separator, name, a flexible space, `helm.status` at the trailing edge — and under
`PageBarStyle.moduleName` that bar always lists `helm.status`, drawing nothing on a page with no status, so General,
About and every status-less module that draws it never see that item move
(`SettingsToolbar.identifiers`, `StatusZoneView`).

**The actions are one `NSToolbarItem`, not one per action.** The tabs and the
actions both live in `NSToolbar`'s own layout, not SwiftUI's: an item that hides
collapses its width in a relayout AppKit itself animates, which no curve of this
app reaches. So the capsule (`HelmToolbarActionsCapsule`,
`Sources/HelmUI/DesignSystem/HelmToolbarActions.swift`) reserves the width of every
*declared* action and only the visible set morphs inside it; an action
inapplicable on its tab is dimmed through the capsule's model, one that belongs to
other tabs is left out of the visible set, and the bar's identifier list never
changes for either; the capsule's header holds why.

## Toolbar actions

`HelmToolbarAction.Kind` is the one shape an action takes: a button, a toggle, a
`.segmented` pair (Hosts' Table/Plain-text switcher) or a `.menu` of checkmarked
items, each with its own press — `Sources/HelmUI/DesignSystem/HelmWindowToolbar.swift`
holds what each draws, how `isVisible`, `isEnabled` and `isBusy` differ, and why a
kind cannot be two at once. Whether a segmented action slides on a press depends on
`SettingsToolbar.centredIdentifiers(_:)`, whose header has what was measured. The
overflow floor, when even the capsule does not fit, is
`NSToolbarItem.menuFormRepresentation` (`SettingsToolbar.patchActionsMenu`).

## The tabs and the search field

The tabs have one form, `HelmToolbarSwitcher`
(`Sources/HelmUI/DesignSystem/HelmToolbarSwitcher.swift`), labelled by
`ToolbarSwitcherStyle`, which the bar's right-click menu changes for all of them;
its `compact` flag folds it to the current tab before AppKit would push the strip
into its overflow menu, and `SettingsToolbar`'s "Folding the tabs" section decides
when. A tab may carry a dot (`HelmToolbarTab.needsAttention`): AppKit draws a segment's image before its label, so
the dot is the segment's image, and a folded switcher marks the tab in its menu with a badge. How the glass lens draws the
dot on a real screen was not measured. The search field is an `NSSearchToolbarItem` carrying an `NSSearchField`
`SettingsToolbar` builds itself (`makeSearchItem`): Return, and only Return, runs a
page's `onSubmit`. With `AppSettings.alwaysCollapseSearch` on, an empty idle field
rests as AppKit's magnifier at every width, through one rest predicate
(`SettingsToolbar.restSearch(_:)`; `PageBar.searchRestCap` holds the reading).

## The bar's menu and style

The bar has one right-click menu (`SettingsToolbar.barMenuItems`), answered by the
same local monitor as the magnifier press, so a Control-click on the collapsed
magnifier has one owner; the same menu is each centre switcher's `NSView.menu`,
which is what VoiceOver opens.

`PageBarStyle` is a setting in Appearance: the module's plate and name as the
toolbar's leading item with a status at the trailing edge — the shipping default,
and what `PageBarStyle.init(stored:)` answers for an empty or unrecognised store —
or the page's name as the window title with its status as the subtitle. The
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

Under the settings window's toolbar the same light is `helmToolbarBackdrop`'s, and
whose band lies there depends on the system: `HelmBandChoice`
(`Sources/HelmUI/DesignSystem/HelmBandChoice.swift`) is read once from the running
macOS and handed down as one value, and its header holds the 26-versus-27 reasoning.
