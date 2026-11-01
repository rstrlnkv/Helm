# Targets

`Package.swift` is the whole account of the package's shape, and
`swift package describe --type json` is the census. Dependencies run one way:
`HelmContract` depends on nothing, `HelmRuntime` and `HelmUI` build on it, a
module's engine on the contract and the runtime, its UI target on the contract,
`HelmUI` and its own engine, and `HelmApp` on `HelmAppStrings`, every module's UI target and on no
engine. `HelmTestSupport` (`Tests/Support`) is a plain target every test target
depends on and no product lists. `HelmReadout` depends on nothing, and `HelmShowcase` on `HelmUI` alone; `HelmApp` depends on neither.

Each target and what it holds:

- `HelmLaunch` — the package's only non-Swift target: the Objective-C `@try` around an `NSTask` launch, which a Swift `catch` cannot be, and, inside `HelmReadNumber`, around the call `WindowCorner` makes of a window's own number.
- `HelmContract` — protocols, the types a module declares itself with, and `EngineNews`.
- `HelmRuntime` — shared plumbing without UI.
- `HelmUI` — the design system, `L()`, the `ModuleDescriptor` protocol, `HelmWord` (the shared words, `String` only) and the kit's own `Localizable.xcstrings`.
- `Module_<X>_Engine` — a module's headless logic.
- `Module_<X>_UI` — a module's descriptor, settings page, panel tile and view model.
- `HelmTestSupport` — `Tests/Support`, below.
- Test targets — `Module_<X>_EngineTests` and `Module_<X>_UITests`, each where the module's row in `Package.swift` sets its flag, and `HelmContractTests`, `HelmAppTests`, `HelmRuntimeTests`, `HelmUITests`; each depends on `HelmTestSupport`, and `HelmAppTests` holds the app-layer checks.
- `HelmReadout` — `Sources/HelmReadout`: the screen instrument that reads a capture and a window; no dependency on any other target, so an import of Helm's own target fails its build, and declared in no product (SwiftPM synthesises one for it, but `HelmApp` does not depend on it), so `--product HelmApp` never builds it. ARCHITECTURE.md § Two screen instruments.
- `HelmShowcase` — `Sources/HelmShowcase`: the kit's components in every state, one board per launch; depends on `HelmUI` only and is declared in no product (SwiftPM synthesises one for it), so `--product HelmApp` never builds it, and the build's import check cannot hold it off `HelmRuntime` (reached through `HelmUI`), which `TheBoundariesTheBuildCannotHoldTests` reads from its import lines. Architecture/DesignSystem.md § The showcase.
- `HelmAppStrings` — `Sources/HelmAppStrings`: the host's words (`AppStrings.swift`, `LogStrings.swift`), the changelog (`ChangelogData.swift`) and their two catalogs; depends on `HelmRuntime` and `HelmUI`, never on a module or an engine, and `HelmApp` and `HelmAppTests` depend on it. A library, because an executable's catalogs do not reach its test build (below).
- `HelmApp` — the executable.

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

`public` means "another target uses this" and nothing else. Every module is several
targets (`Package.swift`'s first doc comment counts them), so `public` is the only way across a
boundary and therefore the only honest declaration of where the boundaries are.
The compiler is what demotes a declaration and a `grep` is not
(ARCHITECTURE.md § Why the commands are run). One demotion exposes the next, so
expect several passes (commits 3ab499c6 and 18bfdf61 are the history).

`Sources/HelmApp` carries a test target despite being an `executableTarget` with
a `Sources/HelmApp/main.swift`: a test target depending on it with `@testable import HelmApp`
builds and runs, and `ModuleRegistry.all` answers inside it.

A test target over an executable compiles that executable's testable variant without its string catalogs: only the
product variant lists them in its sources phase, so `L(.x)` there builds with `swift build --target` and fails
`swift build --build-tests`. The words of an executable therefore live in a library (`HelmAppStrings`), which has a static and a `-dynamic`
target, and a test target builds on the static one. The phases are read with `swift package dump-pif --preserve-structure`.
