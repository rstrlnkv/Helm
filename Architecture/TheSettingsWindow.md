# The Settings window

`Sources/HelmApp/SettingsWindow.swift` builds an `NSSplitViewController` whose
sidebar is the source list at the window's full height. `NSSplitViewController`
supplies the glass itself, which is why nothing draws an `NSVisualEffectView`
behind it — one would block it. Both panes are `NSHostingController`s with
`sizingOptions = []`, so a pane fills what the window gives it and never sizes the
window; the comment above `sidebar.sizingOptions` says why.

One size serves every page: the reasons are the doc comments of `defaultSize` and
`minSize`, and the narrowest pane a page is drawn in is `minSize` less the sidebar.
Both detail frames, `SettingsDetail`'s and `ModuleDetailView`'s, are pinned
`.topLeading`; the comment on `ModuleDetailView`'s says why.

A grouped `Form` groups by what its direct children are, so rows wrapped in a view
change the card they are drawn in (`Sources/Modules/KeepAwake/UI/KeepAwakeAppRules.swift`,
file doc comment).

`SettingsSelection` has one case that is a module, `.module(String)`; `.general`,
`.about` and `.log` are not, which keeps their pages out of `ModuleRegistry.all`.
Why the Log row ships on every build is written on the `.log` case itself.
