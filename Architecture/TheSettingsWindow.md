# The Settings window

`Sources/HelmApp/SettingsWindow.swift` builds a window whose content is
`SettingsShellViewController`, a plain view controller that shows a
`ShellContentView` (`Sources/HelmApp/ShellContentView.swift`): the ground of the stored look
at the bottom, the sidebar on it, and an opaque card inset from the window's edge that holds
the page. Every frame comes from `ShellGeometry`. The ground is the look's: Flat is an
`NSVisualEffectView` with `.sidebar`, `.behindWindow` and `.followsWindowActiveState`, Glass is
the `NSGlassEffectView` AppKit builds for a split view's sidebar (style `.regular`, `cornerRadius` 0, private variant 18; `ShellContentView.makeGlassGround()`); one is visible, and a live change of the look swaps them at once
(`.helmBarAppearanceChanged`). The window's corner is the token `HelmRadius.window` on macOS 27
and the card is cut from it; on macOS 26 `WindowCorner` reads it (and nobody has run that here). The sidebar and the page are each an `NSHostingController` with
`sizingOptions = []`, so a pane fills what the window gives it and never sizes the
window; the comment above `sidebar.sizingOptions` says why.

The sidebar is `ShellSidebar`: a column of rows for the modules that are on, and one row
at the foot for General, the Log and About. A module that is switched off has no row, and
a selection that names one reads as General (`ShellSidebarRows.settled`, applied in
`SettingsModel` when the live modules move and in `show(selecting:)`, and again where the
page is chosen).
A row is the kit's `HelmSidebarRow`; it dims in a window that is not the active one (`\.helmWindowAppearsActive`, set on the sidebar's own hosting root too, since an environment on the pane's root does not reach it) and says "n of m" to VoiceOver. Typing the first letters of a name selects its row (`ShellSidebar`'s doc comment holds how the buffer clears). The page's name is in the header row at the top of the card, not over the sidebar, and the window's `NSToolbar` carries the page tabs alone, under Glass (`SettingsToolbar`; none under Flat):
`SettingsDetail` draws one row at the root of the detail pane (`helmCardHeader`), so it keeps its identity across a page switch — the name and status on the left (`ShellPageIdentity`), on the right what the page declared through `.helmHeaderContent`, which travels up as a preference (`HelmHeaderContentKey`) in the same hosting view and is read with `overlayPreferenceValue`. The title bar is transparent and the detail pane takes no safe area (`safeAreaRegions = []`), so the row starts at the card's top edge and the page's inset is the row's own height. The empty part of the row drags the window (`WindowDragGesture`). The tabs, actions and search are `HelmHeaderTabs`, `HelmHeaderActions` and `HelmHeaderSearch`; the tabs are always whole, the actions too, and the search rests as a 36-pt magnifier while Always Collapse Search is on; the look, Flat or Glass, is `\.helmBarAppearance`, set from the stored choice and live at the pane's root (`helmTracksBarAppearance`).

The window is one of the host's open windows: it joins `HostWindow`'s count when it is brought forward and leaves it when it closes (`SettingsWindow.counted`), so the activation policy is `.regular` while Settings or any other host-owned window is open and `.accessory` only when the last one closes. Bringing it forward reads whether it is key or main at once (`updateWindowAppearsActive()`), so a window shown while another app is in front dims without waiting for a notification. Opening Helm a second time reaches the running copy as the reopen event, and `AppDelegate.applicationShouldHandleReopen` posts `.helmOpenSettings` when no window is visible (a minimised Settings counts as not visible), and `bringForward()` activates and orders Settings front; whether a minimised Settings is restored is unverified (to check in Helm Dev).

One size serves every page: the reasons are the doc comments of `defaultSize` and
`minSize` (1207, measured with the Kit's row geometry of `ThePageHeader` and the tabs labelled by glyph and word, the widest labelling: 1001 pt of row in German plus the sidebar and the window inset; the default size is 1211), which holds the Log page's header row, the fullest, in German, the widest of the eight languages, at the default sidebar (`ShellGeometry.defaultSidebarWidth`). The window sets the sidebar to that default or to `ShellGeometry.railWidth`, and nothing drags it. A person's flip of the sidebar is remembered (`AppSettings.sidebarCollapsed(in:)`) and `ShellContentView` drives the width from one to the other for `HelmMotion.sidebarFoldDuration`, writing it by the timestamps of a display link it owns (`DisplayFoldLink`, `ShellContentView.fold(to:animated:)`); a fold set from code, a flip back to the width already standing and any fold under Reduce Motion are cuts.
Both detail frames, `SettingsDetail`'s and `ModuleDetailView`'s, are pinned
`.topLeading`; the comment on `ModuleDetailView`'s says why.

`HelmSettingsSection` lays out its content's subviews as the card's rows: a stack
wrapped round rows makes them one row, while `Group`, `ForEach` and a view of its
own are flattened (`Sources/Modules/KeepAwake/UI/KeepAwakeAppRules.swift`, file doc
comment). A grouped `Form` groups by what its direct children are, so rows wrapped
in a view change the card they are drawn in.

Every place that turns a module id into its descriptor — the sidebar, the panel, the launch page, the scan coordinator —
asks `ModuleRegistry.descriptor(_:)`; none searches `ModuleRegistry.all` by hand. The host's scan of a module runs inside
`HelmActivity.phase("scan.<id>")` (`ScanCoordinator`), so the interval closes on every way out (ARCHITECTURE.md § The activity registry).

`SettingsSelection` has one case that is a module, `.module(String)`; `.general`,
`.about` and `.log` are not, which keeps their pages out of `ModuleRegistry.all`.
Why the Log row ships on every build is written on the `.log` case itself.

The header row's three stored choices, how it names its page, how it labels its tabs and whether its search rests as a magnifier (`HelmHeaderChoices`), are set at the detail pane's root from `AppSettings.headerChoices` (`helmTracksHeaderChoices`), beside the look (`helmTracksBarAppearance`); the row's right-click menu (`HeaderBarMenu`, an `NSMenu` that `SettingsWindow` pops up from a local event monitor installed while the window is shown and removed when it closes and in `deinit`, because the row lies in the title bar zone, where AppKit takes a right-click before a SwiftUI `.contextMenu` could see it; the press is the row's if it is a right or Control-left press inside the card's top `HelmCardHeaderBand.height`, outside the window buttons and the search field while it is being edited; its fourth part, Always Collapse Search, is offered only where the page declared a search, `SettingsModel.pageHasSearch`) and General's `PageHeaderRow` (the page header, the only one of the three with a row there; the tab labels and Always Collapse Search are the menu's alone) and `BarAppearanceRow` (the look) write theirs through `AppSettings` only, and the two rows listen for the notification so a write from the menu reaches them.
