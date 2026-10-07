# The Settings window

`Sources/HelmApp/SettingsWindow.swift` builds a window whose content is
`SettingsShellViewController`, a plain view controller that shows a
`ShellContentView` (`Sources/HelmApp/ShellContentView.swift`): glass at the bottom, the
sidebar on it, and an opaque card inset from the window's edge that holds the page. Every
frame comes from `ShellGeometry`. The sidebar and the page are each an `NSHostingController` with
`sizingOptions = []`, so a pane fills what the window gives it and never sizes the
window; the comment above `sidebar.sizingOptions` says why.

The sidebar is `ShellSidebar`: a column of rows for the modules that are on, and one row
at the foot for General, the Log and About. A module that is switched off has no row, and
a selection that names one reads as General (`ShellSidebarRows.settled`, applied in
`SettingsModel` when the live modules move and in `show(selecting:)`, and again where the
page is chosen). The page's name is in the window's bar, not over the sidebar:
the bar leads with a spacer (`SettingsToolbar.Lead.spacer`) that `SettingsWindow` keeps
told of where the card is, through the controller's `cardMoved`: the first time from its initialiser, afterwards a turn of the
main queue after the layout that moved it, because a bar that flips its spacer assigns
`window.toolbar` and that may not happen inside the content's layout pass.

One size serves every page: the reasons are the doc comments of `defaultSize` and
`minSize`, and the narrowest pane a page is drawn in is `minSize` less the sidebar and the card's inset (`ShellGeometry.defaultSidebarWidth`, `ShellGeometry.inset`): the window sets the sidebar to that width or to `ShellGeometry.railWidth`, and nothing drags it.
Both detail frames, `SettingsDetail`'s and `ModuleDetailView`'s, are pinned
`.topLeading`; the comment on `ModuleDetailView`'s says why.

A grouped `Form` groups by what its direct children are, so rows wrapped in a view
change the card they are drawn in (`Sources/Modules/KeepAwake/UI/KeepAwakeAppRules.swift`,
file doc comment).

`SettingsSelection` has one case that is a module, `.module(String)`; `.general`,
`.about` and `.log` are not, which keeps their pages out of `ModuleRegistry.all`.
Why the Log row ships on every build is written on the `.log` case itself.
