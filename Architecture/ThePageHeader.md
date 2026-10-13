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

`SettingsToolbar`'s bar, left to right: the name (the module's plate and
its name under `PageBarStyle.moduleName`, the name alone under `PageBarStyle.windowTitle`, "Without Icon"); the tabs' lead
(`helm.tabsLead`, an empty item of a computed width, where there are tabs; a flexible space where there are none); the tabs,
centred on the card; a flexible space; **one** custom-view item for the whole action capsule;
the search field. A status-bearing page draws the shared name-only bar instead —
name, a flexible space, `helm.status` at the trailing edge — and under
`PageBarStyle.moduleName` that bar always lists `helm.status`, drawing nothing on a page with no status, so every status-less module that draws it never sees that item move
(`SettingsToolbar.identifiers`, `StatusZoneView`). The window tells the toolbar where the card is and whether the window's buttons stand in the rail's placement (`ShellContentView`'s `cardMoved`, called inside `layout()` in the turn that moved either), and the toolbar tells the shell only that a window took a bar. The pane starts where AppKit's strip ends and Helm adds nothing to its safe area.

**The name starts sixteen points past the card's edge and never left of where AppKit starts its items.** The name's item is a container (`SettingsToolbar.makeNameItem`) holding the name's hosting view under one leading constraint, whose constant is the card's edge plus sixteen less where the items start, and 0 where that is negative or not a number (`SettingsToolbar.nameInset(paneLeading:itemsStart:)`). `paneMoved(leading:width:rail:)` writes it in the turn of the layout that moved the card, and a bar put on the window afterwards (another page's, or the bar of another look) is given the inset of now. A fold of the sidebar therefore assigns the window no toolbar and replaces no bar: it writes a constant, which follows the card's edge one for one, in the rail's placement of the window's buttons as in the expanded one, so the name stands on the card's edge plus sixteen at every step, including the turn in which the buttons change place. The start of items it is worked out from is the one of the placement the shell told (`SettingsToolbar.itemsStart`, the same start the tabs' lead is worked out from), not the name item's frame, which in that turn is still the other placement's; the constant is 0 only where the edge plus sixteen is left of that start. That the toolbar lays the item out at the width the constant gives it in the same display pass is not seen on a shown window. The window's own title is hidden under either style (`SettingsWindow`'s initialiser writes `titleVisibility` once and no other line of `Sources/HelmApp` writes it): the name is drawn by the bar, and the title stays the window's for the Window menu.

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
(`SettingsToolbar.restSearch(_:)`; `PageBar.searchRestCap` holds the reading).
Under Flat the toolbar's search field stays AppKit's: `makeSearchItem` reads no look, so the same `NSSearchToolbarItem` is made the same way under
both looks, and the look reaches the field only as its width, the room the tabs leave it and the room it is offered. The reason is a reading in a program outside this tree, on macOS 27.2, in a key window
under Dark, on an item's own default field and not on one assigned as `makeSearchItem` assigns it: the item's `isBordered` written false read back true, the field's
bezel written false took and the glass capsule was still drawn (the placeholder lifted and the field read 4 points wider), and the field's background and the item's
plain style read the same untouched as written, being an untouched item's own values. Light, a window that is not key and the field's fold to the
magnifier (the window was wide) were not seen, and no write was tried on an assigned field; Helm's own item was seen as AppKit's glass, `isBordered` read true, under both looks, in a key window under Dark, on one page, in a window 1060 points wide, the field idle and empty, before the search field's offer was built.
In the page bar the search field is an `NSSearchField` on a plate of the bar's own, with the magnifier it folds to
(`ShellBarSearch`): the same Return rule, with the same setting on an empty idle field rests as the magnifier at every width, and a field in use is never folded for room
(`ShellBarSearch.isInUse`, `ShellBarLayout`'s header).

**In the toolbar the tabs stand on the card's middle, not the window's.** AppKit centres an item listed in
`NSToolbar.centeredItemIdentifiers` on the window. The tabs stay in that set, since the lift and the slide of a press
are tied to membership (`SettingsToolbar.centredIdentifiers(_:)`), and the item in front of them, `helm.tabsLead`, pushes them right of the
set's place: an empty view with one width constraint, in the list where a flexible space stood. Its constant is the card's middle
less half the tabs, less the gap AppKit leaves between the name's end and the tabs, less where the name ends, held to 1 through 1,000,000, and
a number that is not one reads 1 (`SettingsToolbar.tabsLead(paneLeading:paneWidth:tabsWidth:gap:nameMaxX:)`). The tabs' width is read from the bar's view, and a gap for each look is read off the bar's frames: it starts at the look's prior (`SettingsToolbar.tabsGapPrior(of:)`: 0 under Flat, 4 under Liquid Glass, so a bar of a look the window has not worn yet is given the lead it will rest at), is replaced by the first gap read for that look where it lies under `tabsGapReadCeiling`, above the prior or below it, and is only lowered after that,
since the tabs' item is made of another thing under each. On a bar whose tabs item does not exist yet, which is the case when the lead item is made (the lead comes first in the list), the tabs' width is the whole width as the settle measures it (`SettingsToolbar.wholeTabsWidth(_:_:)`, kept on the bar), so the tabs' left edge in the turn that makes the lead stands within a point of where it rests. Where the name ends is the toolbar's start of items plus the inset of now plus the name's width,
and the start of items is the one of the placement of the window's buttons that the shell told, not the item's frame: the shell calls `cardMoved` inside `layout()`
whenever the card's frame or `ShellContentView.buttonsStandInRail` is not what it last called for, before it places the buttons, and the window's closure
hands the toolbar both (`SettingsToolbar.paneMoved(leading:width:rail:)`). A fold into the rail changes the placement when it starts (`ShellContentView.foldTarget`), so a layout that comes before the link's first write
calls with the card's frame as it was (read from the code). A fold out of the rail keeps the rail's placement until it lands, and the landing's layout changes both. The toolbar keeps a start of items for each placement and reads it off the name item's frame
only in the settle and on a resize and only while the window is visible (`SettingsToolbar.learnStartOfItems(_:)`), which it takes for a moment when the toolbar has laid out under the placement last told
(assumed, not tried in a shown window; a toolbar nothing had laid out put the name item at 756 and at 879.5 in a window never ordered in), refusing an edge that is not a number, is below 0 or is past the window's width, and one within a point (`itemsStartTolerance`) of the start held, the seed included: the name item's left edge moves by half a point with the inset it is given (read in a window never shown, 92.0 at an inset of 123.5 and 92.5 at 124.0, its right edge on a whole point), so a start taken from it and written back as an inset is never read back as the same number, and without the tolerance the settle rewrote the inset at every pass, the name, the tabs and the room-limited field each moving a point with it, until a count of four stopped the reads. Until one is read the start is a seed:
92.5 expanded (`itemsStartSeed`) and 22.5 in the rail (`railItemsStartSeed`), the seeds being the item's edge as read in a window never shown on macOS 27.2 at a 200-point sidebar
(92.0 to 92.5) and in the rail (22.0 to 22.5), on no other system. So the first fold after launch into the rail is worked out from 22.5, and every one after
a settle in the rail from what that settle read, where it read a start a point or more from the one held. The constant is written beside the name's inset: in the turn of the layout that moves the card or the buttons, on every step
of a fold of the sidebar, including the one that moves the window's buttons; on a bar put on the window; and in the settle, which reads the tabs' width and the gap again. It is written once more when the tabs fold or unfold, since that moves their width.
Measured in a window never shown, over a fold into the rail and out of it under both looks, the tabs' middle stands within a point of the card's at every step, including the step that moves the window's buttons, where the
constant stands 70.0 points above (into the rail) and 70.5 below (out of it) the one worked out from the name item's frame before the toolbar's layout. The name's inset is worked out from the same start, so the inset and the name's end the lead is worked out from cannot be read from two placements; whether that start agrees with the item's edge in a shown window is not seen.
Where the name reaches the place the tabs would take centred on the card, half the tabs and the gap short of the card's middle, the constant reads 1 and the tabs stand after the name, not centred: 36.0 points right of its end under Flat and 40.0 to 40.5 under Liquid Glass (read in a window never shown, with whole tabs). The lead's view was read there 1 point wide and 17.5 points right of the name's end, so the lead is taken to cost 36 points where the flexible space it replaced cost the bar's spacing. The fold
prediction counts the lead as fixed width, not as room, and no less than 36 points where it has no anchor (`SettingsToolbar`'s "Predicting whether the tabs can grow");
its anchored reading starts the room at the right edge of the lead's view, so the 17.5 points read between that edge and the tabs at the constant 1 are counted as room, and that is not corrected; its margins were not
measured again with the lead. Read once in a key window, before the search field's offer was built, under both looks at windows of 1060 and 860, expanded and in the rail: the tabs' middle stood on the card's or up to 1.2 points right of it where the name did not hold them, and the name's item started at 92.0 to 92.5 expanded and 22.0 to 22.5 in the rail. **Not seen on a screen:** a fold of the sidebar step by step, any of this since the offer, and the slide of a pressed tab on a pushed item.

**The search field is offered room before the tabs fold.** `SettingsToolbar.searchOffer(barEnd:paneLeading:paneWidth:tabsWidth:tabsEarliest:actionsWidth:)`
works out, from numbers, the room that whole tabs on the card's middle (or after the name, where it holds them) leave the idle field: the bar's right end
less the tabs' end, `SettingsToolbar.tabsToActions`, the actions and `ShellBarLayout.actionsToSearch`. The tabs fit whole while
that room is not below `ShellBarLayout.searchFloor`, and the field is offered that room held between `ShellBarLayout.searchFloor` and `ShellBarLayout.searchWidth`, written as a width cap on the field
(`PageBar.searchOfferCap`, by `SettingsToolbar.writeSearchOffer(_:tabsWidth:)` in the settle and when the tabs fold or unfold). The fold prediction
(`SettingsToolbar.predictedSlack(bar:tabsWidth:)`) returns that room less the floor for a bar with a lead item and an idle field, so what it charges for the field is what the field
is offered; for a field that is being edited, is opening, holds text or rests under Always Collapse Search it reads the layout as before. A field that grows to a width within that offer (`SettingsToolbar.growthIsWithinTheOffer(_:width:)`) is taking the room the whole tabs leave it, and the tabs do not fold for it. A number that is not one reads a
room under the floor, which folds the tabs. Read in a window never shown, with a sidebar of 200 and three tabs (343 points wide under Flat, 310 under Liquid Glass), an action and a search: under Flat the tabs
stay whole at a window of 900, where the slack read 0.00, and fold at 899, where it read -1.00; folded, they stay folded at 908 and 915 (8.00 and 15.00) and unfold at 916 (16.00); up to a window of about 917 the name holds the whole tabs right of the card's middle. Under Liquid Glass they were read folded at 798 and whole at 918, and where they turn was not read. The field is 283 wide at 1400 under both looks, where it was 325 before the cap. **AppKit's own collapse is not moved by this:**
read in a window never shown, under both looks, the idle field was shown and as wide as its room at rooms of 160 to 200 and was the 36-point magnifier at a room of 150, with the tabs whole (between 150 and 160 not read), and under Flat neither setting `preferredWidthForSearchField` nor a width
constraint of at least 120 on the field changed that, so a room between the floor and about 160 leaves the field collapsed in such a window. **Not seen on a screen:** any of this in a shown window, where under Liquid Glass the tabs were seen folded beside a wide field before this.
Why they fold there is not seen. In a window never shown the fold was read under Flat only, by a temporary print, since removed: `checkOverflow()` folded the tabs at first attach, when the actions' item answered not visible and before the cap was active, the settle unfolded them, and the field's regrowth to its offer folded them again, a growth `SettingsToolbar.growthIsWithinTheOffer(_:width:)` now lets pass without a fold; the fold at first attach was read before that clause and not since; by the code it still happens (the clause is in the field's observer, not in `checkOverflow()`), and the settle undoes it.

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
