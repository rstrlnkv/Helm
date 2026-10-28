# The Settings window

`Sources/HelmApp/SettingsWindow.swift` builds a window whose content is
`SettingsShellViewController`, a plain view controller that shows a
`ShellContentView` (`Sources/HelmApp/ShellContentView.swift`): the ground of the stored look
at the bottom, the sidebar on it, and an opaque card inset from the window's edge that holds
the page. Every frame comes from `ShellGeometry`. The ground is the look's: Flat is an
`NSVisualEffectView` with `.sidebar`, `.behindWindow` and `.followsWindowActiveState`, Glass is
`NSGlassEffectView`; one is visible, and a live change of the look swaps them at once
(`.helmBarAppearanceChanged`). The window's corner is the token `HelmRadius.window` on macOS 27
and the card is cut from it; on macOS 26 `WindowCorner` reads it (and nobody has run that here). The sidebar and the page are each an `NSHostingController` with
`sizingOptions = []`, so a pane fills what the window gives it and never sizes the
window; the comment above `sidebar.sizingOptions` says why.

The sidebar is `ShellSidebar`: a column of rows for the modules that are on, and one row
at the foot for General, the Log and About. A module that is switched off has no row, and
a selection that names one reads as General (`ShellSidebarRows.settled`, applied in
`SettingsModel` when the live modules move and in `show(selecting:)`, and again where the
page is chosen).
A row is the kit's `HelmSidebarRow`; it dims in a window that is not the active one (`\.helmWindowAppearsActive`, set on the sidebar's own hosting root too, since an environment on the pane's root does not reach it) and says "n of m" to VoiceOver. Typing the first letters of a name selects its row (`ShellSidebar`'s doc comment holds how the buffer clears). The colour/plain setting is no longer read here: the pages and the menu-bar panel read it. The page's name is in the header row at the top of the card, not over the sidebar, and the window wears no `NSToolbar`:
`SettingsDetail` draws one row at the root of the detail pane (`helmCardHeader`), so it keeps its identity across a page switch — the name and status on the left (`ShellPageIdentity`), on the right what the page declared through `.helmWindowToolbar`, which travels up as a preference (`HelmPageToolbarKey`) in the same hosting view and is read with `overlayPreferenceValue`. The title bar is transparent and the detail pane takes no safe area (`safeAreaRegions = []`), so the row starts at the card's top edge and the page's inset is the row's own height. The empty part of the row drags the window (`WindowDragGesture`). The tabs, actions and search are `HelmHeaderTabs`, `HelmHeaderActions` and `HelmHeaderSearch`, always whole; the look, Flat or Glass, is `\.helmBarAppearance`, set from the stored choice and live at the pane's root (`helmTracksBarAppearance`).

The window is one of the host's open windows: it joins `HostWindow`'s count when it is brought forward and leaves it when it closes (`SettingsWindow.counted`), so the activation policy is `.regular` while Settings or any other host-owned window is open and `.accessory` only when the last one closes. Bringing it forward reads whether it is key or main at once (`updateWindowAppearsActive()`), so a window shown while another app is in front dims without waiting for a notification.

One size serves every page: the reasons are the doc comments of `defaultSize` and
`minSize`, which holds the Log page's header row, the fullest, in German, the widest of the eight languages, at the default sidebar (`ShellGeometry.defaultSidebarWidth`); a sidebar stored wider (the upper bound of `ShellGeometry.sidebarRange`) is reached only with a stored width, which nothing in the window writes, and `minSize` does not hold the header at it. The window sets the sidebar to the stored width brought into the range (`AppSettings.sidebarWidth(in:)`), to that default or to `ShellGeometry.railWidth`, and nothing drags it. A person's flip of the sidebar is remembered (`AppSettings.sidebarCollapsed(in:)`) and `ShellContentView` drives the width from one to the other for `HelmMotion.sidebarFoldDuration`, writing it by the timestamps of a display link it owns (`DisplayFoldLink`, `ShellContentView.fold(to:animated:)`); a fold set from code, a flip back to the width already standing and any fold under Reduce Motion are cuts.
Both detail frames, `SettingsDetail`'s and `ModuleDetailView`'s, are pinned
`.topLeading`; the comment on `ModuleDetailView`'s says why.

A grouped `Form` groups by what its direct children are, so rows wrapped in a view
change the card they are drawn in (`Sources/Modules/KeepAwake/UI/KeepAwakeAppRules.swift`,
file doc comment).

`SettingsSelection` has one case that is a module, `.module(String)`; `.general`,
`.about` and `.log` are not, which keeps their pages out of `ModuleRegistry.all`.
Why the Log row ships on every build is written on the `.log` case itself.
