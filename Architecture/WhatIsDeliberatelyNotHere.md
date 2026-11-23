# What is deliberately not here

**No external dependency.** `Package.swift` declares no `dependencies:` array,
and the third-party artwork (the flags, the palette's objects) is vendored with its attribution in `NOTICE.md`. A
utility that removes files and asks for Full Disk Access is read by the person
installing it, and every dependency is a thing he has to be told about.

**No sandbox and no privileged helper.** `Resources/HelmApp/` carries an
`Info.plist` and no entitlements file, and `command grep -rn 'NSXPCConnection'
Sources` prints nothing. The modules reach `/Library`, `/etc/sudoers.d` and other
applications' bundles; a sandbox would have to be perforated until it meant
nothing, and a privileged helper is a second binary to sign, install, update and
take back — taking back what one binary changed is already
ARCHITECTURE.md § Giving everything back.

**No transport between the parts.** The host and the modules are one process and
talk through `Sources/HelmContract` and the descriptor, so there is no version to
negotiate and no wire compatibility to keep across a release. A model calls its
engine's methods, and what an engine says unasked reaches the model as typed values
on `EngineNews` (`Sources/HelmContract/EngineNews.swift`): nothing is encoded, and
nothing reaches a socket, a pipe or a second binary.

**No back-deployment.** The package declares `.macOS("26.0")` and the shipped
bundle is arm64 only. Supporting an older system means the ports grow a second path each, and there
is no second machine to prove that path on.

**No page bar of Helm's own.** A bar drawn by the shell (`ShellPageBar`) was replaced by a header row in the
card (`helmCardHeader`, declared through `Sources/HelmUI/DesignSystem/HelmWindowToolbar.swift`); the bar is the
card's, and only the page tabs are a system `NSToolbar` item, under Glass (`SettingsToolbar`; the owner chose it on
2026-11-23), so nobody puts a custom bar back or moves the name, actions or search into the toolbar.

**Not in Screenshots' first version.** Video, a long screenshot, a history of shots, Beautify, a real window editor, Save As, Pin, a "Start with" choice and a panel place per display are not here and are not proposed as gaps; the owner left them out, and `Architecture/Screenshots.md` and `Architecture/ScreenshotsEditor.md` describe what is. Copy All names a shot that is gone by its position in the pile ("Screenshot 2"), by the owner's choice.

**Not one list of protected prefixes.** `StaleItemRules.protectedPrefixes` (what Leftovers offers) and `UserFileScope.protectedPrefixes` (what a removal of the user's files may touch; Leftovers' own removal passes `RemovableScope.partition`) are two lists on purpose: they answer two questions, and merging them would let the offer's list loosen a gate or a gate's list narrow the offer.
