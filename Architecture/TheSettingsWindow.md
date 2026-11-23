# The Settings window

`Sources/HelmApp/SettingsWindow.swift` builds a window whose content is
`SettingsShellViewController`, a plain view controller that shows a
`ShellContentView` (`Sources/HelmApp/ShellContentView.swift`): the ground of the stored look
at the bottom, the sidebar on it, and an opaque card inset from the window's edge that holds
the page. Every frame comes from `ShellGeometry`. The ground is the look's: Flat is an
`NSVisualEffectView`, Glass the `NSGlassEffectView` AppKit builds for a split view's sidebar
(`ShellContentView.makeGlassGround()` holds the parameters); one is visible, and a live change of the look swaps them at once
(`.helmBarAppearanceChanged`). The window's corner is the token `HelmRadius.window` on macOS 27
and the card is cut from it; on macOS 26 `WindowCorner` reads it. The sidebar and the page are each an `NSHostingController` with
`sizingOptions = []`, so a pane fills what the window gives it and never sizes the
window; the comment above `sidebar.sizingOptions` says why.

The sidebar is `ShellSidebar`: a column of rows for the modules that are on, and one row
at the foot for General, the Log and About. A module that is switched off has no row, and
a selection that names one reads as General (`ShellSidebarRows.settled`, applied in
`SettingsModel` when the live modules move and in `show(selecting:)`, and again where the
page is chosen).
A row is the kit's `HelmSidebarRow`; it dims in a window that is not the active one (`\.helmWindowAppearsActive`, set on the sidebar's own hosting root too, since an environment on the pane's root does not reach it) and says "n of m" to VoiceOver. Typing the first letters of a name selects its row (`ShellSidebar`'s doc comment holds how the buffer clears). The page's name is in the header row at the top of the card, not over the sidebar, and the window's `NSToolbar` carries the page tabs alone, under Glass (`SettingsToolbar`; none under Flat).
`SettingsDetail` draws one row at the root of the detail pane (`helmCardHeader`), so it keeps its identity across a page switch: the name and status on the left (`ShellPageIdentity`), on the right what the page declared through `.helmHeaderContent`; the row's geometry, tabs and search are § The page header. The title bar is transparent and the detail pane takes no safe area (`safeAreaRegions = []`), so the row starts at the card's top edge and the page's inset is the row's own height. The empty part of the row drags the window (`WindowDragGesture`).

The window is one of the host's open windows: it joins `HostWindow`'s count when it is brought forward and leaves it when it closes (`SettingsWindow.counted`), so the activation policy is `.regular` while Settings or any other host-owned window is open and `.accessory` only when the last one closes. Bringing it forward reads whether it is key or main at once (`updateWindowAppearsActive()`), so a window shown while another app is in front dims without waiting for a notification. Opening Helm a second time reaches the running copy as the reopen event, and `AppDelegate.applicationShouldHandleReopen` posts `.helmOpenSettings` when no window is visible (a minimised Settings counts as not visible), and `bringForward()` activates and orders Settings front.

One size serves every page: the reasons are the doc comments of `defaultSize` and
`minSize`, which holds the Log page's header row, the fullest, in German, the widest of the eight languages, at the default sidebar (`ShellGeometry.defaultSidebarWidth`); a sidebar stored wider (the upper bound of `ShellGeometry.sidebarRange`) is reached only with a stored width, which nothing in the window writes, and `minSize` does not hold the header at it. The window sets the sidebar to the stored width brought into the range (`AppSettings.sidebarWidth(in:)`), to that default or to `ShellGeometry.railWidth`, and nothing drags it. A person's flip of the sidebar is remembered (`AppSettings.sidebarCollapsed(in:)`) and `ShellContentView` drives the width from one to the other for `HelmMotion.sidebarFoldDuration`, writing it by the timestamps of a display link it owns (`DisplayFoldLink`, `ShellContentView.fold(to:animated:)`); a fold set from code, a flip back to the width already standing and any fold under Reduce Motion are cuts.
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

The header row's three stored choices (`HelmHeaderChoices`) are set at the detail pane's root from `AppSettings.headerChoices` (`helmTracksHeaderChoices`), beside the look (`helmTracksBarAppearance`). The row's right-click menu is `HeaderBarMenu`, an `NSMenu` that `SettingsWindow` pops up from a local event monitor installed while the window is shown and removed when it closes and in `deinit`, because the row lies in the title bar zone, where AppKit takes a right-click before a SwiftUI `.contextMenu` could see it; the press is the row's if it is a right or Control-left press inside the card's top `HelmCardHeaderBand.height`, outside the window buttons and the search field while it is being edited. Its fourth part, Always Collapse Search, is offered only where the page declared a search (`SettingsModel.pageHasSearch`). General's `PageHeaderRow` (the page header, the only one of the three with a row there; the tab labels and Always Collapse Search are the menu's alone) and `BarAppearanceRow` (the look) write theirs through `AppSettings` only, and the two rows listen for the notification so a write from the menu reaches them.

## The sidebar is an arrangement

`Sources/HelmUI/SidebarLayout.swift` is sections of module ids: a `Codable` value
whose invariant is that every registered module appears exactly once.
`Sources/HelmApp/SidebarLayoutStore.swift` reads and writes it, and reading is
where the invariant is enforced rather than trusted — the bytes were written by a
build that is not necessarily this one.

The Tweaks entry is a module to it: one id among the others, in Utilities, and every tweak is a card on its page, so
the arrangement never holds a tweak's id. A stored layout from before it gains the entry in Utilities on read.

The window's sidebar and the status item's menu both draw the same store, so there
is one arrangement rather than two that agree by habit. Neither observes
`UserDefaults`: the sidebar listens for `.helmModuleOrderChanged`, and the menu
reads the store at each right click.

The drop arithmetic is pure and lives in `Sources/HelmUI/SidebarLayoutDrag.swift`
(`SidebarLayout.flattened`, `SidebarLayout.applyingDrag(of:toFlatIndex:)`).
`Sources/HelmApp/SidebarComposerSheet.swift` is the only way into the composer, and
why the composer is not an `NSTableView` is the doc comment of `SidebarComposerList`.

## A window a module needs and the host owns

`Sources/HelmUI/HostWindow.swift` is the base class for a window the host owns on
a module's behalf; `command grep -rn ': HostWindow' Sources/` lists the
subclasses. It owns three things — the activation policy by a count of open windows, which the Settings window joins too, a `closed`
flag and `isReleasedWhenClosed = false` — and its doc comment holds the reason for
each.

The host cannot import a module's engine, so a module that has something to say
vends one opaque door that returns a view or nothing, as `TrashedAppOffer` does:
nothing means no window at all rather than an empty one. The door takes the module's
model, which the host reaches by one `as?` on the live module's model. `TrashedLeftoversWindow`
is the example window.

## Revealing a path

`HelmReveal` (`Sources/HelmUI/DesignSystem/HelmReveal.swift`) shows a path in Finder
without launching or mounting a bundle: its enum doc comment and those of
`HelmReveal.target(for:exists:traits:)` and `HelmReveal.inFinder(_:)` hold the
reasons.
