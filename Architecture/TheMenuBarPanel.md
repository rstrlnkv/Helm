# The menu-bar panel

`Sources/HelmApp/PanelWindow.swift` carries the window,
`Sources/HelmApp/PanelChrome.swift` the chrome around the card,
`Sources/HelmApp/PanelBars.swift` the four rows of the card that are not tiles,
and `Sources/HelmApp/HelmPanel.swift` the card and the drag. The rules that decide
the grid and the drag are pure and live one target away, in
`Sources/HelmUI/PanelGrid.swift` and `Sources/HelmUI/PanelDrag.swift`.

Why the window is built as it is — no window shadow, a strip wider than the card by
`helmPanelShadowMargin`, one size per opening, a plain `NSHostingView`, `makeKey()`
after `orderFrontRegardless()` — is written where each is set: the doc comments of
`helmPanelWidth`, `helmPanelShadowMargin` and `.helmPanelDidShow`, and the `//`
comments in `HelmPanel.init` and `HelmPanel.toggle`. The width is the one
`PanelGrid.narrowestPanel` is the arithmetic for, and the card's edges are
`PanelGrid.padding` and `PanelGrid.gap` rather than numbers typed twice;
`PanelWidthTests` and `CardEdgesAreTheGridsConstantsTests` are the guards.

What the panel stores keeps its reasons on its own doc comments: the `init(from:)`
decoders of `PanelLayout` and its nested types, its `dismissed` and `hidden` lists,
and `PanelLayoutStore.key`.

The bars carry no lifetime of their own;
`Tests/HelmAppTests/PanelBarsCarryNoLifetimeTests.swift` is the guard. A `@State` in
one of them would be a second owner of a lifetime the panel steers by, and its
failure would look like a tile left hanging under the pointer rather than like
anything thrown or logged.
