# Targets

`Package.swift` is the whole account of the package's shape, and
`swift package describe --type json` is the census. Dependencies run one way:
`HelmContract` depends on nothing, `HelmRuntime` and `HelmUI` build on it, a
module's engine on the contract and the runtime, its UI target on the contract,
`HelmUI` and its own engine, and `HelmApp` on `HelmAppStrings`, every module's and every tweak's UI target and on no
engine. `HelmTestSupport` (`Tests/Support`) is a plain target every test target
depends on and no product lists. `HelmReadout` and `HelmLaunchpadHelper` depend on nothing, and `HelmShowcase` on `HelmUI` alone; `HelmApp` depends on none of them.

Each target and what it holds:

- `HelmLaunch` — the package's only non-Swift target: the Objective-C `@try` around an `NSTask` launch, which a Swift `catch` cannot be, and, inside `HelmReadNumber`, around the call `WindowCorner` makes of a window's own number.
- `HelmContract` — protocols, the types a module declares itself with, and `EngineNews`.
- `HelmRuntime` — shared plumbing without UI.
- `HelmUI` — the design system, `L()`, the `ModuleDescriptor` protocol, `HelmWord` (the shared words, `String` only) and the kit's own `Localizable.xcstrings`.
- `Module_<X>_Engine` — a module's headless logic.
- `Module_<X>_UI` — a module's descriptor, settings page, panel tile and view model.
- `Tweak_<X>_Engine` and `Tweak_<X>_UI` — a tweak's two targets, declared by a `Tweak` row in `Package.swift`: the same dependencies as a module's pair, `HelmApp` depends on the UI target alone, and `Tweak_<X>_EngineTests` and `Tweak_<X>_UITests` exist where the row sets the flag.
- `HelmTestSupport` — `Tests/Support`, below.
- Test targets — `Module_<X>_EngineTests` and `Module_<X>_UITests`, each where the module's row in `Package.swift` sets its flag, and `HelmContractTests`, `HelmAppTests`, `HelmRuntimeTests`, `HelmUITests`; each depends on `HelmTestSupport`, and `HelmAppTests` holds the app-layer checks.
- `HelmReadout` — `Sources/HelmReadout`: the screen instrument that reads a capture and a window; no dependency on any other target, so an import of Helm's own target fails its build, and declared in no product (SwiftPM synthesises one for it, but `HelmApp` does not depend on it), so `--product HelmApp` never builds it. ARCHITECTURE.md § Two screen instruments.
- `HelmLaunchpadHelper` — `Sources/HelmLaunchpadHelper`: the Launchpad's Dock icon, a tiny AppKit app nested in Helm's bundle by `Scripts/package-app.sh`; no dependency on any other target, so an import of Helm's own target fails its build, listed in a product of its own that `HelmApp` does not depend on. Architecture/Launchpad.md § The Dock icon.
- `HelmShowcase` — `Sources/HelmShowcase`: the kit's components in every state, one board per launch; depends on `HelmUI` only and is declared in no product (SwiftPM synthesises one for it), so `--product HelmApp` never builds it, and the build's import check cannot hold it off `HelmRuntime` (reached through `HelmUI`), which `TheBoundariesTheBuildCannotHoldTests` reads from its import lines. Architecture/DesignSystem.md § The showcase.
- `HelmAppStrings` — `Sources/HelmAppStrings`: the host's words (`AppStrings.swift`, `LogStrings.swift`), the changelog (`ChangelogData.swift`) and their two catalogs; depends on `HelmRuntime` and `HelmUI`, never on a module or an engine, and `HelmApp` and `HelmAppTests` depend on it. A library, because an executable's catalogs do not reach its test build (below).
- `HelmApp` — the executable.

Beside `DesignSystem/`, `HelmUI` holds by role (the reason is on each file's doc comment, not here): the kit's
words (`ControlStrings.swift`, `SectionStrings.swift`, `BasketStrings.swift`, `ConfirmStrings.swift`,
`HelmWord.swift`, `L10n.swift`); the stored layouts and their drags (`PanelLayout.swift`, `PanelGrid.swift`,
`PanelDrag.swift`, `SidebarLayout.swift`, `SidebarLayoutDrag.swift`); the module contract
(`ModuleDescriptor.swift`, `MenuBarContribution.swift`) and the tweak's (`TweakDescriptor.swift`); the pickers (`AppPicker.swift`, `FolderPicker.swift`);
`HostWindow.swift`; and `Welcome/`.

The declarations in the contract are what this prints:

```bash
command grep -nE 'public (protocol|struct|enum|actor|final class) ' Sources/HelmContract/*.swift
```

One edge runs from `Sources/HelmRuntime` to `Sources/HelmContract` and none the
other way: `Sources/HelmRuntime/StatusPlan.swift` chooses among the contract's
`StatusAppearance` values.

`Sources/HelmRuntime` is the answer to "has this been written already", and
`ls Sources/HelmRuntime` is the list; `ls Tests/Support` is the same list for
test plumbing. A shared helper is no simpler than the thing it stands in for
(the reason is on the doc comment of `Tests/Support/SealKeyProbe.swift`), and
a local helper that does more keeps its own body and calls the shared one.
No file in `Sources/HelmRuntime` serves one module: a helper that only one module reads lives in
that module's engine (`MacHardware` is in `Sources/Modules/KeepAwake/Engine`).

`public` means "another target uses this" and nothing else. Every module is several
targets (`Package.swift`'s first doc comment counts them), so `public` is the only way across a
boundary and therefore the only honest declaration of where the boundaries are.
The compiler is what demotes a declaration and a `grep` is not
(ARCHITECTURE.md § Why the commands are run). One demotion exposes the next, so
expect several passes.

`Sources/HelmApp` carries a test target despite being an `executableTarget` with
a `Sources/HelmApp/main.swift`: a test target depending on it with `@testable import HelmApp`
builds and runs, and `ModuleRegistry.all` answers inside it.

A test target over an executable compiles that executable's testable variant without its string catalogs: only the
product variant lists them in its sources phase, so `L(.x)` there builds with `swift build --target` and fails
`swift build --build-tests`. The words of an executable therefore live in a library (`HelmAppStrings`), which has a static and a `-dynamic`
target, and a test target builds on the static one. The phases are read with `swift package dump-pif --preserve-structure`.

## What is deliberately not here

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

**No page bar of Helm's own.** The page's header is a row in the
card (`helmCardHeader`, declared through `Sources/HelmUI/DesignSystem/HelmHeaderContent.swift`); the bar is the
card's, and only the page tabs are a system `NSToolbar` item, under Glass (`SettingsToolbar`, by the owner's choice), so no custom bar of the shell's own goes back and the name, actions and search do not move into the toolbar.

**Not in Screenshots.** Video, a long screenshot, a history of shots, Beautify, a real window editor, Save As, Pin, a "Start with" choice and a panel place per display are not here and are not proposed as gaps; the owner left them out of Screenshots, and `Architecture/Screenshots.md` and `Architecture/ScreenshotsEditor.md` describe what is. Copy All names a shot that is gone by its position in the pile ("Screenshot 2"), by the owner's choice.

**Not one list of protected prefixes.** `StaleItemRules.protectedPrefixes` (what Leftovers offers) and `UserFileScope.protectedPrefixes` (what a removal of the user's files may touch; Leftovers' own removal passes `RemovableScope.partition`) are two lists on purpose: they answer two questions, and merging them would let the offer's list loosen a gate or a gate's list narrow the offer.
