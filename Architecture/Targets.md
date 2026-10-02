# Targets

`Package.swift` is the whole account of the package's shape, and
`swift package describe --type json` is the census. Dependencies run one way:
`HelmContract` depends on nothing, `HelmRuntime` and `HelmUI` build on it, a
module's engine on the contract and the runtime, its UI target on the contract,
`HelmUI` and its own engine, and `HelmApp` on every module's UI target and on no
engine. `HelmTestSupport` (`Tests/Support`) is a plain target every test target
depends on and no product lists.

Each target and what it holds:

- `HelmLaunch` — the package's only non-Swift target: the Objective-C `@try` around an `NSTask` launch, which a Swift `catch` cannot be.
- `HelmContract` — protocols and wire types.
- `HelmRuntime` — shared plumbing without UI.
- `HelmUI` — the design system, `L()`, `ModuleViewModel`, `TransportClient`, the `ModuleDescriptor` protocol; carries `Resources`.
- `Module_<X>_Engine` — a module's headless logic.
- `Module_<X>_UI` — a module's descriptor, settings page, panel tile and view model.
- `HelmTestSupport` — `Tests/Support`, below.
- Test targets — `Module_<X>_EngineTests` and `Module_<X>_UITests` per module, and `HelmContractTests`, `HelmAppTests`, `HelmRuntimeTests`, `HelmUITests`; each depends on `HelmTestSupport`.
- `HelmApp` — the executable.

The declarations in the contract are what this prints:

```bash
command grep -nE 'public (protocol|struct|enum|actor|final class) ' Sources/HelmContract/*.swift
```

One edge runs from `Sources/HelmRuntime` to `Sources/HelmContract` and none the
other way: `EngineReply` (`Sources/HelmRuntime/EngineReply.swift`) is engine-side
wire plumbing that logs, and the log lives in `Sources/HelmRuntime`.

`Sources/HelmRuntime` is the answer to "has this been written already", and
`ls Sources/HelmRuntime` is the list; `ls Tests/Support` is the same list for
test plumbing. A shared helper is no simpler than the thing it stands in for
(the reason is on the doc comment of `Tests/Support/ScratchDirectory.swift`), and
a local helper that does more keeps its own body and calls the shared one.

`public` means "another target uses this" and nothing else. Every module is several
targets (`Package.swift`'s first doc comment counts them), so `public` is the only way across a
boundary and therefore the only honest declaration of where the boundaries are.
The compiler is what demotes a declaration and a `grep` is not
(ARCHITECTURE.md § Why the commands are run).

`Sources/HelmApp` carries a test target despite being an `executableTarget` with
a `Sources/HelmApp/main.swift`: a test target depending on it with `@testable import HelmApp`
builds and runs, and `ModuleRegistry.all` answers inside it.
