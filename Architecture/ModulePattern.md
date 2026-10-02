# Module pattern

A module is four directories, expanded from one `Module` entry in
`Package.swift` (the reasons for all four being required, and for the manifest
leaving the filesystem unread, are on the doc comment above `struct Module`):
`Sources/Modules/<Name>/Engine`, `Sources/Modules/<Name>/UI`,
`Tests/Modules/<Name>/EngineTests`, `Tests/Modules/<Name>/UITests`.
`ls Sources/Modules` gives the modules.

## The boundaries

**The modules are blind to each other.** Each UI target imports exactly one
engine, its own, and no engine imports another:

```bash
command grep -rn '^import Module_' Sources/Modules/ \
  | sed 's|Sources/Modules/\([^/]*\)/\([^/]*\)/.*:[0-9]*:import \(.*\)|\1/\2 <- \3|' | sort -u
```

prints one row per module, each naming its own engine.

**Engines carry no UI.**
`command grep -rln '^import SwiftUI\|^import HelmUI' Sources/Modules/*/Engine/`
prints nothing. AppKit reaches only system calls, in the files
`command grep -rln '^import AppKit' Sources/Modules/*/Engine/` names, most of
them a module's Sources/Modules/<Name>/Engine/SystemPorts.swift.

**A command is a case of the module's own enum.** There is one
Sources/Modules/<Name>/Engine/Logic/<Name>Command.swift per module, and the
engines' handlers switch over them with no `default` arm. A global
`EngineCommand` enum was the obvious idea and is the wrong one: each engine
handles its own subset of the names, so no switch over it could be exhaustive.

The one place a string still crosses is the host, which links no engine:
`ScanCommand` (`Sources/HelmRuntime/ScanReport.swift:39`) is the constant both
sides read, and the modules `ScanRunner.scannableModules`
(`Sources/HelmRuntime/ScanRunner.swift:30`) names have their own command files
that say so in their doc comments.
`Tests/HelmAppTests/CommandNamesAreAnsweredTests.swift:20` pins those spellings,
and scans the source per module for a command name its own engine has
no `case` for, because a typo there is silence and silence already reads as
"refused" here.

**A payload is declared once, in the engine.** Both ends of the wire are in one
build and the UI target imports its engine, so the UI only aliases the engine's type
(`typealias` in `Sources/Modules/KeepAwake/UI/KeepAwakeViewModel.swift` and
`Sources/Modules/VPN/UI/VPNViewModel.swift`) and no type decoded under
Sources/Modules/<Name>/UI is declared there; the doc comment of
`Sources/Modules/KeepAwake/Engine/KeepAwakeStatePayload.swift` says why.

**A module's id is the engine's constant.**
`command grep -rn 'public static let moduleID' Sources/Modules/*/Engine/` prints
one line per engine; the descriptor forwards the id upward, in the same direction
the command enums travel.
`Tests/HelmAppTests/StoreNamespacesAreModuleIdsTests.swift:28` records the ids
that shipped and fails on a rename, since a rename orphans everything anybody has
configured.

## Ports and logic

A module that reaches the system does it behind a protocol,
and the system implementation of that protocol lives in a module's
Sources/Modules/<Name>/Engine/SystemPorts.swift while its fake lives in the
tests. Pure decision logic sits in `Sources/Modules/<Name>/Engine/Logic/`.

```bash
ls Sources/Modules/*/Engine/SystemPorts.swift
```

names the modules that hold to the pattern. Three do not, for two different
reasons: Disk and Duplicates read the file system as their whole subject, so a
port would be a second name for `FileManager` and the reading is tested against
a real temporary tree instead; Autopilot's two ports sit in `Engine/Logic/`
where the pattern would put them a directory higher, and that is drift rather
than a decision.

**A port that answers more than one thing grows a second door.** Where a system
read comes back empty for more than one reason, the port either grows a second
entry point or stops answering an optional. `Sources/HelmRuntime/PowerSource.swift`
carries both: `current()` is the battery reading and `supply()` is IOKit's own question about
the providing source; each caller folds a nil `supply()` toward its own worst
failure (Keep Awake toward sleep, a background scan toward mains), and the doc
comments of `supply()` and its callers say so. `VPNCredentialRead`
(`Sources/Modules/VPN/Engine/Ports.swift`) names its three reasons outright.

A port's doc comment says which reasons collapse into an empty read, and a caller that
must tell them apart is given a second entry point or an enum naming each reason, never a
convention for reading one optional two ways. A sentinel is the same defect: a zero
meaning "not measured yet" cannot also mean "not drawn". An unreadable system answer is
not folded toward the permissive side without asking whether the guard downstream needs
the difference, or "battery with an unreadable charge" becomes decidable nowhere. A port
that can change under the app has a reverse channel and its fake stands in that state
too, since a local flag set once against a live external fact goes on reporting a world
that has moved. An engine reloads its cached settings in its activation and not only on a
settings-changed message: a field with no sensible initial value is bound to nothing on
every launch and refuses before there is anything to log, and a test that sends the
message itself cannot see it.

## The transport and the store

**Events replay per name, under one lock.** `LocalTransport`
(`Sources/HelmContract/LocalTransport.swift`) keeps `lastEvents` keyed by event
name rather than one slot, because a module streams a log into the same engine
that emits a state, and yields the replay and registers the subscriber inside one
lock; the reason is on the doc comment of `LocalTransport.events`. `Tests/HelmContractTests/ReplayOrderTests.swift`
is the guard, and it asserts it entered the window at all, because a race test
that failed to race proves nothing.

**Lifecycle and the store.** `Sources/HelmApp/ModuleHost.swift` reads the enabled
flag from the module's `NamespacedStore`, builds the engine, activates it and
wraps the transport in a `ModuleViewModel`.
`Sources/HelmApp/ModuleRegistry.swift` is the single list of descriptors, and
`Tests/HelmAppTests/ListsAgreeWithTheTreeTests.swift` holds its invariants —
unique ids, a name and a short name on each, and an `sfSymbol` macOS actually
ships, since one it does not ship draws an empty square. A `NamespacedStore`
prefixes every key with `module.<id>.`, and every `set` posts `.helmStoreChanged`
with the full key, on the main thread whoever wrote; that notification is what
keeps the panel and the Settings window in step in both directions.

**A module's state belongs to its view model rather than to its page.** Leaving a
module's page in Settings tears down the type-erased subtree and every
`@StateObject` in it. The pattern is a cache keyed by the underlying
`ModuleViewModel`, and

```bash
command grep -rn 'static func shared(vm' Sources/Modules/*/UI/*.swift
```

counts the modules that hold one. Caching the view model is only half of it — whatever the
page keeps in `@State` dies with the page.

## Bulk reads

**A bulk read of file contents carries a pool inside the loop.**
`FileHandle.read` hands back an autoreleased `Data` and
`DispatchQueue.concurrentPerform` drains no pool per iteration, so without one the
footprint tracks the volume read rather than the slice size. The sites are what
`command grep -rn autoreleasepool Sources/` prints, and the pool is independent of
parallelism: `Sources/HelmRuntime/ReleaseDigest.swift` has it in a plain serial
`while`. `resourceValues(forKeys:)` loops
are the measured exception and take no pool — `URLResourceValues` bridges to small
value types rather than to a retained buffer.

`Sources/HelmRuntime/BulkWalk.swift` is the shared walk, over `getattrlistbulk`.
Its load-bearing facts (attribute **bit** order, the device id from a bulk read,
the epoch subtraction) are written at the line each governs. A device identifier
is signed, as `BulkWalk.DeviceID` wraps a signed `st_dev`, and is never converted
to an unsigned type.

A stored field is multiplied by the node count.
`DiskNode` (`Sources/Modules/Disk/Engine/Logic/DiskNode.swift`) carries a name and
no path, composed by whichever traversal needs one through
`Sources/HelmRuntime/ScanPath.swift`, and
`Tests/Modules/Disk/EngineTests/DerivedPathTests.swift` asserts the absence of
the field with a `Mirror` as well as pinning the composed strings. A running
record is bounded or it is a leak with a scrollbar: `LogTail.standardLimit` and
`ActionHistory.limit` are two.

## A value crossing to the main thread

A value crossing `DispatchQueue.main.async` is a *reading* or a *payload*, and the two are
handled in opposite ways: a reading is taken inside the block, a payload is captured before
it. `WindowSeenReader` (`Sources/HelmUI/DesignSystem/OffScreenIdle.swift`) sampled the
window's level before the hop and delivered that sample after the window had opened,
unmounting both Settings panes behind a window that was on screen and tearing down a live
toolbar. Layout's fix gesture (`Sources/Modules/Layout/Engine/LayoutEngine.swift`) and the
hotkey handler (`Sources/HelmApp/HotkeyManager.swift`) sample before the hop on purpose,
because what the person had selected when they pressed is what must be converted, and
re-reading after the hop converts whatever they have selected since.
