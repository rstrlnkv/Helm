# The page header

In the settings window a page's header and its controls live in a row at the top of the card, drawn by `SettingsDetail` (`helmCardHeader`, `Sources/HelmUI/DesignSystem/HelmCardHeader.swift`): the name and status on the left, the page's tabs, actions and search on the right (`HelmHeaderTabs`, `HelmHeaderActions`, `HelmHeaderSearch`), whole, with no folding; the search collapses only through Always Collapse Search (§ The row's choices and its menu), and then only to its own 36 pt magnifier. The row is the card's: the window's `NSToolbar` (`SettingsToolbar`) carries the page tabs alone, and only under Glass, by the owner's choice; under Flat the toolbar stays installed with no item and the row draws the tabs.

## What a page declares

A page says what it wants — tabs, actions, search — through
`.helmHeaderContent(_:)`
(`Sources/HelmUI/DesignSystem/HelmHeaderContent.swift`), which publishes it as the preference `HelmHeaderContentKey`; the row reads it with `overlayPreferenceValue`, because the value carries closures cut from the page's state at its last body and a copy kept behind an `==` would hold the old ones. A module's UI target
never imports `HelmApp`. A page that never calls it shows the name and, for a status-bearing module, its status, and nothing else;
that is not an error state. `command grep -rln '\.helmHeaderContent(' Sources` lists the files that publish.

## The row's geometry

**The row draws the Figma UI Kit's `Toolbar` geometry (Layout Inline, 856 × 52), under both looks; only the materials differ.** The row is 52 high: the controls are 36 high (`HelmHeaderActions.side`) with 8 above and below, and the row holds the 36 on a page that has no control (`HelmPageHeader`, `CardHeader.height`). The plate is 24 × 24, 14 pt from the card's left edge, and the name starts 12 pt after it (x = 50); the controls end 10 pt before the right edge (`CardHeader.leadingInset`, `trailingInset`, passed to `HelmPageHeader`; a header over a page on its own keeps 20 and 20, `HelmLayout.formInset`, and the content below the row still starts at 20).

The tab strip is centred on the card's row, not packed against the actions: `HeaderRowLayout` (`HelmCardHeader.swift`) takes the row's three parts, the name's side, the strip, and the runs on the right (the actions, then the search, one gap apart), and puts the strip's centre on the card's (the row's insets are 14 and 10, so the layout's own centre is shifted by half the difference). It gives way when there is no room: the strip never overlaps the name's side, which it keeps 36 pt from (`HeaderRowLayout.nameGap`), nor the first run, which it keeps one gap from (`HelmHeaderActions.gap`, 8 pt). At the narrowest both limits close on it and the row is name, 36, strip, 8, run, so `SettingsWindow.minSize` holds (its doc comment has the German, glyph-and-word measurement; the German Log is at the limit). The strip therefore stands at the card's centre on a page with a short run (Uninstaller, Screenshots, General) and further left on one with a long run (Log, Homebrew), in every language. The settings window's pages declare no shared widest run: a centred strip does not move between pages.

## Flat tabs

`HelmHeaderTabs`: a 36 pt strip, 4 pt plate padding, a 28 pt pill (radius 14), 9 pt segment padding, 5 pt between segments, 13 pt Regular in every state. The pick slides to a pressed tab. Segment padding, the dot gaps, the type sizes, the icon width, the dot and the dimming are named once, `HelmTabNumbers` (`HelmHeaderTabs.swift`); the plate (4) and the gap between tabs (5) are named once as well, and the Glass strip's width is derived from them in `HelmTabsMetrics.total` (Flat lays its strip out itself); the pill is not named. The Glass strip's measure (`HelmTabsMetrics`) reads the named ones too and equals the Flat strip's width to within each word's rounding (under 1 pt per word: `word()` rounds up and the glyph's 16 is a constant), in every style, with and without dots.

## Glass tabs

Under Glass the tabs are a real toolbar item: the system's `NSSegmentedControl` (`.extraLarge` = 36 pt) in an unbordered `NSToolbarItem` whose strip draws its own `NSGlassEffectView` track, and which gives the lens under a held press (outside a toolbar the control draws a solid accent-blue pick, so it is used nowhere else). Each segment's width is set from its label so no word is cut, and a segment with a dot is wider by the dot and its gap; the dot stands after the label, and the attention dot and one accessibility element per segment lie over the segments. The widths, the track's inset and the strip's total (`HelmTabsMetrics.widths`, `trackInset`, `total`, the one source for the control, the item and the row's placeholder) and what was measured are in `Sources/HelmUI/DesignSystem/HelmTabsRelay.swift`; why the item is unbordered and the toolbar is never taken off, the item's container, the items' coming and going and the lift are in the header of `Sources/HelmApp/SettingsToolbar.swift`, the title band in `ShellGeometry.titleBand`.

A view with no sink, Launchpad's borderless panel (it cannot carry a toolbar) and the fixtures, gets `HelmHeaderTabs`' glass strip: one `GlassEffectContainer`, a glass capsule for the track and one for the pick.

## How the page reaches the toolbar

The row mounts `HelmTabsRelay` (`Sources/HelmUI/DesignSystem/HelmTabsRelay.swift`), which hands the declaration to the `HelmTabsSink` the window puts in the environment of the detail pane, each call with the row's owner token, so a late word from a row rebuilt on a language change clears nothing of the new one; the doc comments of `HelmTabsSink` and `HelmTabsTarget` hold the token's rules. The row keeps a clear placeholder of the strip's whole width (`HelmTabsSlot`), so `HeaderRowLayout` still centres it on the card and gives way, and the placeholder's window rectangle goes to the toolbar, which positions its items itself: `SettingsToolbar.spacerWidth` and the header of `Sources/HelmApp/SettingsToolbar.swift` hold how the strip is brought to that rectangle.

The toolbar is 52 pt tall and centres its items at y 26 while the row centres at 30, so the tabs' item is 44 pt tall with the control at its bottom (`TabsStrip.lift`), which puts the control at the row's centre under Glass; the row stands at 30 under both looks, and the toolbar stays installed under Flat, so nothing moves when the look flips. The toolbar holds no item while a page declares no tabs, and the spacer and the tabs when it does. The sidebar holds the title bar's Flat band (`ShellGeometry.titleBand`) because the toolbar grows its safe area, and with the toolbar the window's three buttons stand lower and further right (`ShellGeometry.toolbarShift`; `ShellWindowButtons.placed` holds them at one place under both looks, reading the window's own state: `window.toolbar?.isVisible`).

## Actions

`HelmHeaderActions`: **the row holds the room of every declared action, visible or not**, so the actions that stay do not slide when another comes or goes. Under Flat one capsule of `HelmSurface.barPlate` stands behind the visible actions only, 36 high; under Glass the buttons are joined glass buttons.

## Search

`HelmHeaderSearch`: a 36 pt capsule, `barPlate` under Flat, `.glassEffect(.regular.interactive(), in: Capsule())` in its own `GlassEffectContainer` under Glass, 283 pt wide, an unbezeled `NSSearchField` inside (inset 8, glyph to text 6, the focus ring on the capsule). The gap tabs, actions, search is one constant, `HelmHeaderActions.gap`, 8 pt.

## The header band's Dark numbers

`darkFill` and `darkShade` were tuned against the former Finder-style glass backdrop. They still apply only to the Liquid Glass toolbar style in Dark; Flat keeps the Light fill in Dark. The header values were not retuned for the shared system backdrop.

## Where the row is drawn, and where it is not

The window sets the environment value `helmHeaderInCard` (`SettingsWindow`); where it is true, `helmPageHeader` draws no row in the page and `helmPageBar(title:)` reports the page's name (`HelmPageTitleKey`) and whether its scroll view has moved under the row (`HelmPageScrolledKey`) up to the card. Where it is false — a sheet, a page mounted on its own, a test — `helmPageHeader` draws the header in the page (`HelmPageHeader`) rather than in a card that does not exist for it (§ The header strip, below), and `helmPageBar` does nothing: a page that uses only it, like About, has no header outside the card, and `LogView` draws its own row by its own `inCard` check.

The look of the tabs and the actions, Flat or Liquid Glass, is `\.helmBarAppearance`, set from the stored choice (`HelmBarAppearance`; General's row "Toolbar style").

## The header strip

The header strip is the system's 52 pt and lies over the page rather than above it:
`helmPageHeader` (`Sources/HelmUI/DesignSystem/HelmPageHeader.swift`) applies it as
a modifier, so content scrolls behind its material. A page whose top band stays put
draws `HelmPageHeader` as an ordinary view and gets no scroll-edge material.

Over a scroll view there is no rule at rest; the whole strip lights for three
reasons — the pointer on it while the window is key, the page scrolled underneath,
the page declaring that what sits under the band is not a scroll view — from one
answer, `HelmPageHeader.isLit`, which feeds both the fill and the rule.

In the settings window the row is that header (`helmCardHeader`, `overContent: true`) with the page's scroll report (`HelmPageScrolledKey`) read at the pane's root, so the light is the header's own, and
whether the band is drawn at all depends on the system: `HelmBandChoice`
(`Sources/HelmUI/DesignSystem/HelmBandChoice.swift`) is read once from the running
macOS and handed down as one value, and its header holds the 26-versus-27 reasoning.

## The row's choices and its menu

Three stored choices change what the row draws, read from the environment value `helmHeaderChoices` (`Sources/HelmUI/DesignSystem/HelmHeaderChoices.swift`), which the window sets at the pane's root from `AppSettings.headerChoices` and updates on `.helmHeaderChoicesChanged`. Never an `.id`: the page below is not rebuilt for a choice it does not draw, and under Flat (and on Launchpad) `HelmHeaderTabs` keeps its pick and its namespace across a change, so the pick keeps sliding.

- `PageBarStyle` (`pageBarStyle`): `moduleName`, "With Icon", is the plate before the name; `windowTitle`, "Without Icon", is the name alone. The status stays under both.
- `HeaderTabLabels` (`tabLabels`): `text`, `icons` (SF Symbol, Regular 15, the word as tooltip and accessibility label, the attention dot on the glyph) or `iconsAndText` (glyph, 6 pt, word). Every `HelmHeaderTab` carries its `symbol`. Geometry is the Kit's in all three.
- `collapseSearch` (`AppSettings.alwaysCollapseSearch`, key `alwaysCollapseSearch`, off by default), "Always Collapse Search": while it is on the page's search rests as a 36 pt magnifier button on the same capsule whenever the field is empty and nobody is editing it. One predicate decides (`HelmHeaderSearch.rests`: setting on, not open, no query), so a query is never hidden behind a glyph. A press on the magnifier or ⌘F opens the slot to its full 283 pt and focuses the field; it closes again when the editing ends with the field empty (Escape in an empty field, a press elsewhere in the window, focus moving away). The `NSSearchField` stays mounted and is hidden from hit-testing and accessibility while it rests; the magnifier carries the field's accessibility label. **⌘F opens and focuses the page's search field on every page with a search, whatever the setting** (a local monitor installed with the field, matching the F key by position, consuming the key while the field's window is key; no other ⌘F handler exists). The press-elsewhere close is the setting's alone, and a field that did not take the focus is not left open. Only the slot's width moves, by `HelmMotion.interface`. The slot's state is keyed by the page (`.id` on the search only, never on the tabs). The tabs stand where `HeaderRowLayout` puts them: centred, giving way to the run's width, and the run holds the room of every declared action (`HelmHeaderActions`), so the strip does not move when an action appears or disappears.

None is sealed: nothing unattended reads them. The row has a right-click menu (`HeaderBarMenu`, whose doc comment lists its parts): Tab labels only where the page on screen declared tabs in its row, which the window reads from the declaration the row draws (`HelmPageHeaderFactsKey`, mirrored into `SettingsModel.pageHasTabs`), so the menu and the row cannot disagree, and Always Collapse Search only where the page declared a search (the same key, mirrored into `SettingsModel.pageHasSearch`), absent rather than dimmed elsewhere. The row does not draw it: `SettingsWindow` pops an `NSMenu` up, built each time from the store, and its writes go through `AppSettings`. A SwiftUI `.contextMenu` on the row never opens for a person, since the title bar view takes the press first.
