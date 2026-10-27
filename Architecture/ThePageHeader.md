# The page header

In the settings window a page's header and its controls live in a row at the top of the card, drawn by `SettingsDetail` (`helmCardHeader`, `Sources/HelmUI/DesignSystem/HelmPageHeader.swift`): the name and status on the left, the page's tabs, actions and search on the right (`HelmHeaderTabs`, `HelmHeaderActions`, `HelmHeaderSearch`), always whole, with no folding and no collapsed search. The window wears no `NSToolbar`.

A page says what it wants — tabs, actions, search — through
`.helmWindowToolbar(_:token:)`
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
