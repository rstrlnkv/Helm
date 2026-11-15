# The page header

In the settings window a page's header and its controls live in a row at the top of the card, drawn by `SettingsDetail` (`helmCardHeader`, `Sources/HelmUI/DesignSystem/HelmPageHeader.swift`): the name and status on the left, the page's tabs, actions and search on the right (`HelmHeaderTabs`, `HelmHeaderActions`, `HelmHeaderSearch`), always whole, with no folding and no collapsed search. The window wears no `NSToolbar`. Where pages share one tab strip and declare different runs — the settings window's General, Log and About — the strip stands in one place: the window declares, for the pages that share the strip, the widest run (`LogView.trailingRun`, its width `HelmTrailingRun.width`) as `reserves`, the row keeps at least that width for the actions and the search, and the strip ends 12 pt before it; a module page reserves only what it declares, since its tabs do not change its actions or its search (`HelmPageToolbarContent.reserves`, `HelmHeaderControls`). **The row holds the room of every declared action, visible or not** (`HelmHeaderActions`), so the actions that stay do not slide when another comes or goes. The old capsule's rule of 2026-11-15, "as wide as the actions it shows, no reserve, because the reserve left a dead slot beside the tabs", is not carried: the row is its own design, the reserve is deliberate, and a shared strip's widest run is `reserves`. The owner may reverse that for the new row. Likewise the Figma UI Kit's Flat geometry of 2026-11-15 (a 28 pt tab pill, 4 pt strip padding, 9 pt segment padding, regular 13 pt labels, one plate behind the visible actions, an 8 pt gap from actions to search, a 14 pt name inset) is not carried: it was drawn for the old toolbar, and the header row keeps its own numbers (`HelmHeaderTabs`: 2 pt plate padding, 12 pt segment padding, medium labels; `HelmHeaderActions`: bare actions under Flat; the name inset is `HelmLayout.formInset`, 20 pt), which `SettingsWindow.minSize` is measured with. The owner may take the Kit's numbers into the row. **The header band's Dark numbers** (`darkFill`, `darkShade`) were read on the Glass ground (Finder's sidebar material at level 49) and apply under Glass only; Flat keeps the Light fill in Dark, unmeasured against its own ground.

A page says what it wants — tabs, actions, search — through
`.helmWindowToolbar(_:)`
(`Sources/HelmUI/DesignSystem/HelmWindowToolbar.swift`), which publishes it as the preference `HelmPageToolbarKey`; the row reads it with `overlayPreferenceValue`, because the value carries closures cut from the page's state at its last body and a copy kept behind an `==` would hold the old ones. A module's UI target
never imports `HelmApp`. A page that never calls it shows the name and, for a status-bearing module, its status, and nothing else;
that is not an error state. `command grep -rln '\.helmWindowToolbar(' Sources` lists the files that publish.

## Where the row is drawn, and where it is not

The window sets the environment value `helmHeaderInCard` (`SettingsWindow`); where it is true, `helmPageHeader` draws no row in the page and `helmPageBar(title:)` reports the page's name (`HelmPageTitleKey`) and whether its scroll view has moved under the row (`HelmPageScrolledKey`) up to the card. Where it is false — a sheet, a page mounted on its own, a test — `helmPageHeader` draws the header in the page (`HelmPageHeader`) rather than in a card that does not exist for it (§ The header strip below), and `helmPageBar` does nothing: a page that uses only it, like About, has no header outside the card, and `LogView` draws its own row by its own `inCard` check.

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
