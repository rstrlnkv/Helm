# The menu-bar panel

The panel is drawn from the kit's tokens (`HelmSpace`, `HelmRadius`, `HelmSurface`, `HelmSignal`,
`HelmMotion`, `HelmText.onFill`); what is its own is the tab-strip metrics (`PanelBars.swift`), the edit-mode decoration, its numeric type sizes and small text styles (beside the `HelmText` faces it shares), the drawer rows' vertical inset, and the fixed sizes of its marks and glyph buttons (icon plates, the footer's glyph frame, the empty state's margin). Who draws each part:

- **The status item** — `Sources/HelmApp/StatusItemController.swift`, its mark `MenuBarIcon`
  (`Sources/HelmUI/DesignSystem/MenuBarIcon.swift`).
- **The window** — `PanelWindow.swift` (`KeyablePanel`, the shadow band, the width).
- **The glass** — the card in `HelmPanel.swift`, `glassEffect`.
- **The tabs** — `PanelTabStrip` in `PanelBars.swift`, which holds their metrics.
- **The grid** — `HelmPanel.swift` places the tiles by the rules of `Sources/HelmUI/PanelGrid.swift`.
- **The edit chrome** — `EditChrome` in `PanelChrome.swift`: the minus, the size chips and the drawer's
  pencil chip (both `helmPillTrack`), and the padding `EditChrome.overhang` that makes room for them; the
  drag insets each measured frame by `EditChrome.overhang` to draw and land the carried tile at its
  content size. The dashed outline is the gallery's ghost, `PanelGallery` in `PanelBars.swift`.
- **The drag** — `HelmPanel.swift` carries the tile, `Sources/HelmUI/PanelDrag.swift` decides the drop.
- **The footer** — `PanelFooter` and `PanelEditBar` in `PanelBars.swift`, the setting in
  `PanelFooterSetting.swift`.
- **The tiles** — each module's own.

Why the window is built as it is — no window shadow, a strip wider than the card by
`helmPanelShadowMargin`, one size per opening, a plain `NSHostingView`, `makeKey()`
after `orderFrontRegardless()` — is written where each is set: the doc comments of
`helmPanelWidth`, `helmPanelShadowMargin` and `.helmPanelDidShow`, and the `//`
comments in `HelmPanel.init` and `HelmPanel.toggle`. The width is derived: two
`PanelGrid.minimumTile` tiles, one `PanelGrid.gap` and `PanelGrid.padding` either side.

What the panel stores keeps its reasons on its own doc comments: the `init(from:)`
decoders of `PanelLayout` and its nested types, its `dismissed` and `hidden` lists,
and `PanelLayoutStore.key`.

The bars carry no lifetime of their own;
`Tests/HelmAppTests/PanelBarsCarryNoLifetimeTests.swift` is the guard. A `@State` in
one of them would be a second owner of a lifetime the panel steers by, and its
failure would look like a tile left hanging under the pointer rather than like
anything thrown or logged.
