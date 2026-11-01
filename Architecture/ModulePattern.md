# Module pattern

A module is two source directories, `Sources/Modules/<Name>/Engine` and `Sources/Modules/<Name>/UI`, and a test directory only
where a kept test lives, `Tests/Modules/<Name>/EngineTests` or `Tests/Modules/<Name>/UITests`, each switched on by its flag on the
module's `Module` entry in `Package.swift`; the reasons, and why the manifest leaves the filesystem unread, are on the doc comment
above `struct Module`. A directory with no flag is not compiled and nothing warns, so
`Tests/HelmAppTests/ListsAgreeWithTheTreeTests.swift` reads the two against each other, and a scanning module needs its UI tests,
because the same file looks for its stopped-model test there.
`ls Sources/Modules` gives the modules.

## The boundaries

**The modules are blind to each other.** Each UI target imports exactly one
engine, its own, and no engine imports another. The build holds it:
`Package.swift` declares one engine per UI target and none per engine, and
`Scripts/test.sh` and `Scripts/package-app.sh` build with
`--explicit-target-dependency-import-check error`, which refuses an import of a
target outside the importing target's dependencies, direct or through another.
The check runs on a target only when it recompiles, so a rerun after a refusal
builds green and the refusing run can end on "Build complete!": its exit code is
the verdict. A fresh build folder compiles, and so checks, every target the build
asks for; the release's fresh clone asks for the targets `HelmApp` depends on —
the shared ones and every module's engine and UI, no test target.

**Engines carry no UI, and the host imports no engine.** The build holds
neither: SwiftUI is a system module rather than a target, and the check passes
an import of a target reached through a declared one, which is how `HelmApp`,
declaring every module's UI target, could import every engine.
`Tests/HelmRuntimeTests/TheBoundariesTheBuildCannotHoldTests.swift` reads the
imports instead; its doc comment lists the spellings it counts. AppKit reaches
only system calls, and its place is a module's
Sources/Modules/<Name>/Engine/SystemPorts.swift, directly under `Engine`:
`testEngineAppKitImportsStandOnlyInSystemPorts` in the same test refuses an
AppKit or Cocoa import anywhere else in an engine. What stays in review is
whether a line of a ports file is a system call or a drawing, because an import
line cannot tell them apart.

**A model calls its engine.** A module's model holds the engine, usually through an
internal port, and calls its methods; a command needs no name, because the compiler
checks a call. What differs per module is how the answer comes back.

Keep Awake's model calls the engine's methods directly and takes the engine's states
from its `stream()` (Architecture/KeepAwake.md § How the model reaches the engine).
Layout's model takes the same stream and calls the same way, except that its re-read of
the store goes to the engine's own serial queue, because it asks the accessibility server
(Architecture/Layout.md § How Layout's model reaches its engine).
Leftovers' model calls its engine the same way and takes every answer by return, with
no stream, because that engine emits nothing (Architecture/Leftovers.md § How Leftovers'
model reaches its engine).
Disk's model calls its engine the same way and takes the answer of each call by return;
the progress and the partial snapshots of a scan travel on a stream the model makes for
that one call, not on a stream of the engine's, because those events exist only inside a
call the model made (Architecture/Disk.md § How Disk's model reaches its engine).
Duplicates' model does the same for a search and for a removal, and asks the keychain
for the stored keep policy in `appear()` (Architecture/Duplicates.md § How Duplicates'
model reaches its engine).
VPN's model calls the same way through its port `VPNWork` and takes the engine's state from its `stream()`, forced re-emissions included (Architecture/VPN.md § How VPN's model reaches its engine).
Autopilot's model calls the same way and takes the engine's one unasked signal, a pass
written into the history, on a one-slot stream the descriptor makes, as the Uninstaller's
Trash arrivals travel (Architecture/Autopilot.md § How Autopilot's model reaches its
engine).
Homebrew's model calls through `HomebrewWork` and takes what the engine says while an
operation runs from its `stream()` (Architecture/Homebrew.md § The model), and
Screenshots' through `ScreenshotsWork` and its `stream()` (Architecture/Screenshots.md
§ How Screenshots' model reaches its engine).

The host reaches a background scan through the live module's `backgroundScan`, which is
the descriptor's `backgroundScan(_:)` (`Sources/HelmUI/ModuleDescriptor.swift`): every
scanning module's descriptor answers from its model, and the default answers nil because
it is asked only of the modules `ScanRunner.scannableModules`
(`Sources/HelmRuntime/ScanRunner.swift`) lists.

**A payload is declared once, in the engine.** The engine and its page are in one
build and the UI target imports its engine, so the UI reads the engine's type itself
(Keep Awake's and VPN's `stream()` hand the model the engine's own `StatePayload`) and no state an engine
publishes is declared there a second time; the doc comment of
`Sources/Modules/KeepAwake/Engine/KeepAwakeStatePayload.swift` says why.

**A module's id is the engine's constant.**
`command grep -rn 'public static let moduleID' Sources/Modules/*/Engine/` prints
one line per engine; the descriptor forwards the id upward.
`Tests/HelmAppTests/StoreNamespacesAreModuleIdsTests.swift:28` records the
registered ids and fails on a rename, since a rename orphans everything anybody
has configured.

**A module may own windows over the displays.** Screenshots' overlay, toast and pin are panels its UI target builds itself; a window a module needs and the host owns is the other shape, `Architecture/AWindowAModuleNeedsAndTheHostOwns.md`.

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
settings-changed call: a field with no sensible initial value is bound to nothing on
every launch and refuses before there is anything to log, and a test that makes the
call itself cannot see it.

## The stream and the store

**What an engine says replays per slot, under one lock.** `EngineNews`
(`Sources/HelmContract/EngineNews.swift`) keeps the last value per slot rather than
one, because a module streams a log beside a state, and yields the replay and
registers the subscriber inside one lock; the reason is on the doc comment of
`EngineNews.stream`. `EngineNewsReplayTests.testANewStateIsNeverFollowedByOneItReplaced`
(`Tests/HelmContractTests/EngineNewsReplayTests.swift`) is the guard, and
it asserts it entered the window at all, because a race test that failed to race
proves nothing.

**Lifecycle and the store.** `Sources/HelmApp/ModuleHost.swift` reads the enabled
flag from the module's `NamespacedStore`, builds the module with `makeModule(store:)`
(the engine and the model, nothing started), activates the engine and keeps both in a
`Live` of closures that `makeLive` closes over the descriptor's `Model`, so no caller
names the model's type. On the person's switch and on quit the host
calls the module's `stop(_:)` before the engine's `deactivate()`; the model goes with
the `Live`.
A module declares its global shortcuts as `hotkeys` and answers a press in
`hotkeyPressed(_:_:)`; `ModuleHost.registerHotkeys` registers every module's in one loop
over `ModuleRegistry.all`, each held only while its module is live, and `HotkeyManager`
re-reads on `.helmModuleEnabled` and `.helmModuleDisabled`.
`Sources/HelmApp/ModuleRegistry.swift` is the single list of descriptors, and
`Tests/HelmAppTests/ListsAgreeWithTheTreeTests.swift` holds its invariants —
unique ids, a name and a short name on each, and an `sfSymbol` macOS actually
ships, since one it does not ship draws an empty square. A `NamespacedStore`
prefixes every key with `module.<id>.`, and every `set` posts `.helmStoreChanged`
with the full key, on the main thread whoever wrote; that notification is what
keeps the panel and the Settings window in step in both directions.

**A module's state belongs to its view model rather than to its page.** Leaving a
module's page in Settings tears down the type-erased subtree and every
`@StateObject` in it. The pattern is `makeModule`, which the host holds for the
enable. Holding the view model is only half of it — whatever the page keeps in `@State`
dies with the page.

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
