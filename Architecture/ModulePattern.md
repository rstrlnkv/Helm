# Module pattern

A module is two source directories, `Sources/Modules/<Module>/Engine` and `Sources/Modules/<Module>/UI`, and a test directory only
where a kept test lives, `Tests/Modules/<Module>/EngineTests` or `Tests/Modules/<Module>/UITests`, each switched on by its flag on the
module's `Module` entry in `Package.swift`; the reasons are on the doc comment
above `struct Module`. A directory with no flag is not compiled and nothing warns, so
`Tests/HelmAppTests/ListsAgreeWithTheTreeTests.swift` reads the two against each other, and a scanning module needs its UI tests,
because the same file looks for its stopped-model test there.
`ls Sources/Modules` gives the modules that have a directory; Tweaks, the one more in `ModuleRegistry.all`, has its descriptor in `Sources/HelmApp`.

A tweak is the same shape one size down: `Sources/Tweaks/<Tweak>/Engine` and `UI`, a `Tweak` entry in `Package.swift` and
`TweakDescriptor` in place of `ModuleDescriptor`, which asks for no menu-bar presence, hotkey, scan or panel widget; the
host that runs it and why it is not `ModuleHost` are the doc comments of `Sources/HelmApp/TweakHost.swift` and
`Sources/HelmApp/TweaksDescriptor.swift`.

## The boundaries

**The modules are blind to each other.** Each UI target imports exactly one
engine, its own, and no engine imports another. The build holds it:
`Package.swift` declares one engine per UI target and none per engine, and
`Scripts/test.sh` and `Scripts/package-app.sh` build with
`--explicit-target-dependency-import-check error`, which refuses an import of a
target outside the importing target's dependencies, direct or through another.
The check runs on a target only when it recompiles, so a rerun after a refusal
builds green and the refusing run can end on "Build complete!": its exit code is
the verdict. The same holds for a tweak: its UI target imports its own engine alone, and no tweak's target and no module's can see the other's.
A fresh build folder checks every target the build
asks for; the release's fresh clone asks for the targets `HelmApp` depends on (the shared ones, every module's engine and UI and every tweak's, no test target).

**Engines carry no UI, and the host imports no engine.** The build holds
neither: SwiftUI is a system module rather than a target, and the check passes
an import of a target reached through a declared one, which is how `HelmApp`,
declaring every module's and every tweak's UI target, could import every engine.
`Tests/HelmRuntimeTests/TheBoundariesTheBuildCannotHoldTests.swift` reads the
imports instead, in `Sources/Modules` and in `Sources/Tweaks`. AppKit reaches
only system calls, and its place is a module's
`Sources/Modules/<Name>/Engine/SystemPorts.swift`, directly under `Engine`:
`testEngineAppKitImportsStandOnlyInSystemPorts` refuses an
AppKit or Cocoa import anywhere else in an engine. What stays in review is
whether a line of a ports file is a system call or a drawing.

**A model calls its engine.** A module's model holds the engine, usually through an
internal port, and calls its methods. What differs per module is how the answer comes back.

Keep Awake's, Layout's, VPN's, Homebrew's and Screenshots' models call the engine's methods (VPN, Homebrew and Screenshots through a port: `VPNWork`, `HomebrewWork`, `ScreenshotsWork`) and take its states from its `stream()`;
Layout's re-read of the store goes to the engine's own serial queue, because it asks the accessibility server.
Leftovers' model takes every answer by return, with no stream, because that engine emits nothing.
Disk's and Duplicates' models take the answer of each call by return; the progress of a scan travels on a stream the model makes for
that one call, because those events exist only inside a call the model made. Autopilot's model takes the engine's one unasked signal, a pass
written into the history, on a one-slot stream the descriptor makes, as the Uninstaller's Trash arrivals travel.
Each module's page has the heading that says how: Keep Awake's § How the model reaches the engine, § How Layout's model reaches its engine, and so on; Homebrew's is § The model.

The host reaches a background scan through the descriptor's `backgroundScan(_:)` (`Sources/HelmUI/ModuleDescriptor.swift`): every
scanning module answers from its model, and the default answers nil because
it is asked only of `ScanRunner.scannableModules` (`Sources/HelmRuntime/ScanRunner.swift`).

**A payload is declared once, in the engine.** The engine and its page are in one
build and the UI target imports its engine, so the UI reads the engine's type itself
(Keep Awake's and VPN's `stream()` hand the model the engine's own `StatePayload`) and no state an engine
publishes is declared there a second time; the doc comment of
`Sources/Modules/KeepAwake/Engine/KeepAwakeStatePayload.swift` says why.

**A module's id is the engine's constant.**
`command grep -rn 'public static let moduleID' Sources/Modules/*/Engine/` prints
one line per engine; the descriptor forwards the id upward.
`StoreNamespacesAreModuleIdsTests` (`Tests/HelmAppTests/`) records the
registered ids and fails on a rename, since a rename orphans everything anybody
has configured; its `testNoModuleSpellsItsOwnIdAsALiteral` reads `Sources/Tweaks` as it reads `Sources/Modules`.

**A module may own windows over the displays.** Screenshots' overlay and toast are panels its UI target builds itself; a window a module needs and the host owns is the other shape, `Architecture/TheSettingsWindow.md` § A window a module needs and the host owns.

## Ports and logic

A module that reaches the system does it behind a protocol,
and the system implementation of that protocol lives in a module's
Sources/Modules/<Module>/Engine/SystemPorts.swift while its fake lives in the
tests. Pure decision logic sits in `Sources/Modules/<Module>/Engine/Logic/`.

```bash
ls Sources/Modules/*/Engine/SystemPorts.swift
```

names the modules that hold to the pattern. Two do not, for one reason: Disk and
Duplicates read the file system as their whole subject, so the
walk has no port, a port there would be a second name for `FileManager`, and it is
tested against a real temporary tree instead (Disk's `VolumeCapacityPort` sits
with its system implementation in `Sources/Modules/Disk/Engine/Ports.swift`, and the move to the Trash
comes in as a closure). Autopilot's ports sit in `Sources/Modules/Autopilot/Engine/Ports.swift`; the keychain implementations
(`KeychainRuleKey`, `KeychainRuleSequence`) stay in `RuleKeychain.swift`, the one
file that names the deployed keychain items, which `TheRuleItemsAreTheOnesThatShippedTests` pins.

**A port that answers more than one thing grows a second door.** Where a system
read comes back empty for more than one reason, the port either grows a second
entry point or stops answering an optional: `Sources/HelmRuntime/PowerSource.swift`
carries both (`current()` and `supply()`), and `VPNCredentialRead`
(`Sources/Modules/VPN/Engine/Ports.swift`) names its three reasons outright; their doc comments say how each caller folds a nil.

A port's doc comment says which reasons collapse into an empty read, and a caller that
must tell them apart is given a second entry point or an enum naming each reason, never a
convention for reading one optional two ways. A sentinel is the same defect: a zero
meaning "not measured yet" cannot also mean "not drawn". An unreadable system answer is
not folded toward the permissive side without asking whether the guard downstream needs
the difference. A port that can change under the app has a reverse channel and its fake stands in that state
too, since a local flag set once against a live external fact goes on reporting a world
that has moved. An engine reloads its cached settings in its activation and not only on a
settings-changed call: a field with no sensible initial value is bound to nothing on
every launch, and a test that makes the call itself cannot see it.

## The stream and the store

**What an engine says replays per slot, under one lock.** `EngineNews`
(`Sources/HelmContract/EngineNews.swift`) keeps the last value per slot rather than
one, because a module streams a log beside a state, and yields the replay and
registers the subscriber inside one lock; the reason is on the doc comment of
`EngineNews.stream`. `EngineNewsReplayTests.testANewStateIsNeverFollowedByOneItReplaced`
(`Tests/HelmContractTests/EngineNewsReplayTests.swift`) is the guard, and
it asserts it entered the window at all.

**Lifecycle and the store.** `Sources/HelmApp/ModuleHost.swift` reads the enabled
flag from the module's `NamespacedStore`, builds the module with `makeModule(store:)`
(the engine and the model, nothing started), activates the engine and keeps both in a
`Live` of closures that `makeLive` closes over the descriptor's `Model`. On the person's switch and on quit the host
calls the module's `stop(_:)` before the engine's `deactivate()`.
A module declares its global shortcuts as `hotkeys` and answers a press in
`hotkeyPressed(_:_:)`; `ModuleHost.registerHotkeys` registers every module's in one loop
over `ModuleRegistry.all`, each held only while its module is live, and `HotkeyManager`
re-reads on `.helmModuleEnabled` and `.helmModuleDisabled`.
`Sources/HelmApp/ModuleRegistry.swift` is the single list of descriptors, and
`Tests/HelmAppTests/ListsAgreeWithTheTreeTests.swift` holds its invariants (unique ids, a name and a short name on each, an `sfSymbol` macOS actually
ships). A `NamespacedStore`
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
`DispatchQueue.concurrentPerform` drains no pool per iteration. The sites are what
`command grep -rn autoreleasepool Sources/` prints, and the pool is independent of
parallelism: `Sources/HelmRuntime/ReleaseDigest.swift` has it in a plain serial
`while`. `resourceValues(forKeys:)` loops
are the measured exception and take no pool — `URLResourceValues` bridges to small
value types rather than to a retained buffer. `WalkFootprintTests.swift` holds that
reading beside the pooled walk's.

`Sources/HelmRuntime/BulkWalk.swift` is the shared walk, over `getattrlistbulk`.
Its load-bearing facts are written at the line each governs. A device identifier
is signed, as `BulkWalk.DeviceID` wraps a signed `st_dev`, and is never converted
to an unsigned type. A stored file identity (`PathCanonical.FileIdentity(status:)`) is the
opposite: it keeps the unsigned bit pattern because Autopilot history is written in it, and
it is compared, never ordered or subtracted.

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
it. `WindowSeenReader` (`Sources/HelmUI/DesignSystem/OffScreenIdle.swift`) reads the
window's level inside the block, since a sample taken before the hop and delivered after the window opened
would unmount both Settings panes behind a window on screen. Layout's fix gesture (`Sources/Modules/Layout/Engine/LayoutEngine.swift`) and the
hotkey handler (`Sources/HelmApp/HotkeyManager.swift`) sample before the hop on purpose,
because what the person had selected when they pressed is what must be converted, and
re-reading after the hop converts whatever they have selected since.
