# Helm — architecture

Helm is a menu-bar utility suite for macOS: one accessory application that hosts
its independent modules, which `ls Sources/Modules` lists. A module is a
headless engine and a settings page, and the two halves speak only over a
transport. Around them stand four foundation targets — `Sources/HelmContract`
for what crosses the engine/host boundary,
`Sources/HelmRuntime` for plumbing without UI, `Sources/HelmUI` for the design
system and the strings, and `Sources/HelmLaunch` for the one thing Swift cannot
express — plus `Sources/HelmApp`, the executable that owns the window, the panel
and the status item. The whole shape is declared in `Package.swift`, and the
boundaries in this document are the ones the compiler enforces.

## Targets

`Package.swift` is the whole account of the package's shape: a foundation layer, a
module pair (engine and UI) per module, one test harness, one executable,
host-level test targets and a test target per module.
`swift package describe --type json` is the census; `Package.swift` is where the
shape is declared.

```
HelmLaunch     the package's only non-Swift target: the Objective-C `@try`
               around an NSTask launch, which a Swift `catch` cannot be
HelmContract   protocols and wire types, and it depends on nothing
HelmRuntime    shared plumbing without UI; depends on HelmContract and HelmLaunch
HelmUI         the design system, `L()`, `ModuleViewModel`, `TransportClient`,
               the `ModuleDescriptor` protocol; carries `Resources`
Module_<X>_Engine  headless logic; depends on HelmContract and HelmRuntime
Module_<X>_UI      descriptor, settings page, panel tile, view model; depends on
                   HelmContract, HelmUI and its own engine
HelmTestSupport    `Tests/Support`, a plain target every test target depends on
                   and no product lists
HelmApp        the executable; depends on every module's UI target and on no engine
```

`Sources/HelmContract` holds `EngineCommand` and `EngineEvent`
(`Sources/HelmContract/EngineMessage.swift`), the `EngineTransport` protocol,
`LocalTransport`, `ModuleEngine`, `ModuleID`, `ModuleMetadata`,
`ModulePermission` and `StatusAppearance`. The declarations are what this prints:

```bash
command grep -nE 'public (protocol|struct|enum|actor|final class) ' Sources/HelmContract/*.swift
```

One edge runs from `Sources/HelmRuntime` to `Sources/HelmContract` and none the
other way: `EngineReply` (`Sources/HelmRuntime/EngineReply.swift`) is engine-side
wire plumbing that logs, and the log lives in `Sources/HelmRuntime`.

`Sources/HelmRuntime` is the answer to "has this been written already". Its
contents are not listed in prose; `ls Sources/HelmRuntime` is the list and
`ls Sources/HelmRuntime | wc -l` the count, because a figure describing the tree
belongs in the tree — the list was spelled out twice here and went stale both
times. `HelmTestSupport` (`Tests/Support`) is to test plumbing what
`Sources/HelmRuntime` is to app plumbing, and `ls Tests/Support` is that list.

The deployment target is `.macOS("26.0")` and the default localization is `en`.
One product is declared, `HelmApp`, so that `--product HelmApp` in
`Scripts/package-app.sh:258` names something the manifest says exists rather than
the product SwiftPM synthesises for an executable target. The declaration is not
what keeps the test harness out of a release build: naming the product on the
command line is.

`public` means "another target uses this" and nothing else. Every module is two
targets and the package is a dozen more, so `public` is the only way across a
boundary and therefore the only honest declaration of where the boundaries are.
The compiler is what demotes a declaration; a `grep` is not, because this
repository writes backticked names inside doc comments deliberately and at
volume.

`Sources/HelmApp` carries a test target despite being an `executableTarget` with
a `Sources/HelmApp/main.swift`: a test target depending on it with `@testable import HelmApp`
builds and runs, and `ModuleRegistry.all` answers inside it.

## What is deliberately not here

**No external dependency.** `Package.swift` declares no `dependencies:` array,
and the one third-party artwork is vendored with its licence in `NOTICE.md`. A
utility that removes files and asks for Full Disk Access is read by the person
installing it, and every dependency is a thing he has to be told about.

**No sandbox and no privileged helper.** `Resources/HelmApp/` carries an
`Info.plist` and no entitlements file, and `command grep -rn 'NSXPCConnection'
Sources` prints nothing. The modules reach `/Library`, `/etc/sudoers.d` and other
applications' bundles; a sandbox would have to be perforated until it meant
nothing, and a privileged helper is a second binary to sign, install, update and
take back — the reset story is already the hardest chapter here.

**No transport between the parts.** The host and the modules are one process and
talk through `Sources/HelmContract`, so there is no version to negotiate and no
wire compatibility to keep across a release. `EngineCommand`/`EngineEvent`
(`Sources/HelmContract/EngineMessage.swift`) box a payload as `Data`, and
`Sources/HelmRuntime/EngineReply.swift` fills it with `JSONEncoder`/`JSONDecoder`
only to erase the payload's type for one generic call site — that boxing never
reaches a socket, a pipe or a second binary.

**No back-deployment.** The package declares `.macOS("26.0")` and the shipped
bundle is arm64 only. Supporting an older system means the ports that read
`Activity Monitor`-era APIs grow a second path each, and there is no second
machine to prove that path on.

## Module pattern

A module is four directories, and the manifest expands them from one `Module`
entry: `Sources/Modules/<Name>/Engine`, `Sources/Modules/<Name>/UI`,
`Tests/Modules/<Name>/EngineTests`, `Tests/Modules/<Name>/UITests`. All four are
required, so a missing one is a manifest error on every machine rather than a
module quietly having no tests. The manifest deliberately leaves the filesystem
unread: walking `Sources/Modules` would turn a missing directory into a missing
target, which is the same silence in a new shape.

`ls Sources/Modules` gives the modules. The order in `Package.swift` is the order
`HelmApp` listed them in.

**The modules are blind to each other.** Each UI target imports exactly one
engine, its own, and no engine imports another:

```bash
command grep -rn '^import Module_' Sources/Modules/ \
  | sed 's|Sources/Modules/\([^/]*\)/\([^/]*\)/.*:[0-9]*:import \(.*\)|\1/\2 <- \3|' | sort -u
```

prints one row per module, each naming its own engine. `HelmApp` imports every
module's UI target and no engine, so a direct edge from the host into an engine
would be a door past the transport.

**Engines carry no UI.**
`command grep -rln '^import SwiftUI\|^import HelmUI' Sources/Modules/*/Engine/`
prints nothing. AppKit reaches only system calls, in the files
`command grep -rln '^import AppKit' Sources/Modules/*/Engine/` names, most of
them a module's Sources/Modules/<Name>/Engine/SystemPorts.swift.

**A command is a case of the module's own enum.** There is one
Sources/Modules/<Name>/Engine/Logic/<Name>Command.swift per module, and the
engines' handlers switch over them with no `default` arm. A global
`EngineCommand` enum was the obvious idea and is the wrong one: each engine
handles its own subset of the names, so no switch over it could be exhaustive
and the compiler would stay silent exactly where a defect lives. A name the enum
cannot parse is refused once at the door instead.

The one place a string still crosses is the host, which links no engine:
`ScanCommand` (`Sources/HelmRuntime/ScanReport.swift:39`) is the constant both
sides read, and the modules `ScanRunner.scannableModules`
(`Sources/HelmRuntime/ScanRunner.swift:30`) names have their own command files
that say so in their doc comments.
`Tests/HelmAppTests/CommandNamesAreAnsweredTests.swift:20` pins those spellings,
and scans the source per module for a command name its own engine has
no `case` for, because a typo there is silence and silence already reads as
"refused" here.

**A module's id is the engine's constant.**
`command grep -rn 'public static let moduleID' Sources/Modules/*/Engine/` prints
one line per engine; the descriptor forwards the id upward, in the same direction
the command enums travel.
`Tests/HelmAppTests/StoreNamespacesAreModuleIdsTests.swift:28` records the ids
that shipped and fails on a rename, since a rename orphans everything anybody has
configured.

**Events replay per name, under one lock.** `LocalTransport`
(`Sources/HelmContract/LocalTransport.swift`) keeps `lastEvents` as a dictionary
keyed by event name rather than one slot, because a module streams a log into the
same engine that emits a state. The replay is yielded and the subscriber
registered inside a single `NSLock`
(`Sources/HelmContract/LocalTransport.swift:37`): registering first and yielding
the history afterwards left a window in which an `emit` reached the new subscriber
ahead of its own replay, so the stream carried the new state and then the state it
replaced. `Tests/HelmContractTests/ReplayOrderTests.swift:34` is the guard, and it
asserts it entered the window at all, because a race test that failed to race
proves nothing.

**Ports and logic.** A module that reaches the system does it behind a protocol,
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
carries both: `current()` (`:43`) is the battery reading, `supply()` (`:81`) is
IOKit's own question about the providing source and answers a three-case `Supply`
(`:60`). The fold to a `Bool` is `isOnMains(_:)` (`:110`), spelled once per caller
that wants it — `Sources/Modules/KeepAwake/Engine/KeepAwakeEngine.swift:496` folds
`supply() == .mains`, so an unnamed supply fails toward sleep, while
`Sources/HelmApp/ScanCoordinator.swift:166` keeps the lax fold, where
unknown-means-mains is the right reading for a background scan.
`VPNCredentialRead` (`Sources/Modules/VPN/Engine/Ports.swift:30`) names its three
reasons outright — `.ready`, `.notNeeded` (`:37`), `.behindAPrompt` (`:43`).

**Lifecycle and the store.** `Sources/HelmApp/ModuleHost.swift` reads the enabled
flag from the module's `NamespacedStore`, builds the engine, activates it and
wraps the transport in a `ModuleViewModel`.
`Sources/HelmApp/ModuleRegistry.swift:16` is the single list of descriptors, and
`Tests/HelmAppTests/ListsAgreeWithTheTreeTests.swift` holds its invariants —
unique ids, a name and a short name on each, and an `sfSymbol` macOS actually
ships, since one it does not ship draws an empty square. A `NamespacedStore`
prefixes every key with `module.<id>.`
(`Sources/HelmRuntime/NamespacedStore.swift:73`), and every `set` posts
`.helmStoreChanged` with the full key, hopping to the main thread when the writer
is elsewhere (`Sources/HelmRuntime/NamespacedStore.swift:90`) — a clamshell
callback writes from a background queue. That notification is what keeps the panel
and the Settings window in step in both directions.

**Blocking work leaves the cooperative pool.** Transport handlers run on the
Swift-concurrency pool, and `offTheCooperativePool`
(`Sources/HelmRuntime/OffTheCooperativePool.swift:14`) is the dispatch-queue hop a
blocking call takes instead of parking a pool thread.

**A bulk read of file contents carries a pool inside the loop.**
`FileHandle.read` hands back an autoreleased `Data` and
`DispatchQueue.concurrentPerform` drains no pool per iteration, so without one the
footprint tracks the volume read rather than the slice size. The sites are what
`command grep -rn autoreleasepool Sources/` prints. Three are the shape itself:
`Sources/Modules/Duplicates/Engine/DuplicateScanner.swift:446` hands only a verdict
out of the pool; `Sources/HelmRuntime/ReleaseDigest.swift:66` is the same shape in
a plain serial `while`, so the pool is independent of parallelism; and
`Sources/HelmRuntime/BulkWalk.swift:215` and `:246` carry one per directory in the
worker loop and one per batch around `consume`. `resourceValues(forKeys:)` loops
are the measured exception and take no pool — `URLResourceValues` bridges to small
value types rather than to a retained buffer.

`Sources/HelmRuntime/BulkWalk.swift` is the shared walk, over `getattrlistbulk`.
Three of its facts are load-bearing and each is written at the line it governs:
attributes arrive in attribute **bit** order rather than request order
(`:299`–`:302`); `ATTR_CMN_DEVID` from a bulk read is the parent filesystem's
view, so `BulkWalk.deviceID(of:)` (`:114`) stays a `stat`; and a `Date` composed
through the epoch loses its last bits, so the epoch is subtracted from the whole
seconds first.

A stored field is multiplied by the node count.
`Sources/Modules/Disk/Engine/Logic/DiskNode.swift:19` carries a name and no path;
the path is composed by whichever traversal needs one, through
`Sources/HelmRuntime/ScanPath.swift`, and
`Tests/Modules/Disk/EngineTests/DerivedPathTests.swift:39` asserts the absence of
the field with a `Mirror` as well as pinning the composed strings. A running
record is bounded or it is a leak with a scrollbar:
`Sources/HelmRuntime/LogTail.swift:49` at 1000 and
`Sources/Modules/Autopilot/Engine/Logic/ActionHistory.swift:182` at 500.

**A module's state belongs to its view model rather than to its page.** Leaving a
module's page in Settings tears down the type-erased subtree and every
`@StateObject` in it. The pattern is a cache keyed by the underlying
`ModuleViewModel`, and

```bash
command grep -rn 'static func shared(vm' Sources/Modules/*/UI/*.swift
```

counts the modules that hold one. Caching the view model is only half of it — whatever the
page keeps in `@State` dies with the page.

**`ModuleMetadata.shortName` defaults to `name`**
(`Sources/HelmContract/ModuleMetadata.swift:45`). The sidebar column is fixed and
truncates mid-word; page headers, the panel and the icon menu take the full name.

### Running other programs

`Sources/HelmLaunch` is the package's only non-Swift target and exists for one
reason: `NSTask` does not merely return errors, it **raises** on some launch
paths, and an Objective-C exception has nothing to land on in a Swift frame. The
`@try`/`@catch` therefore sits in Objective-C with no Swift frame between it and
the raise (`Sources/HelmLaunch/HelmLaunch.m:11`, `:13`). The error it answers with
carries the exception's name and nothing else, because a reason string holds
whatever the task was given and this log carries no names.
`Tests/HelmAppTests/NoBareLaunchInTheShellTests.swift` refuses a bare
`try process.run()` anywhere but `HelmProcess`'s own door.

`Sources/HelmRuntime/HelmProcess.swift` bounds how many tools are out at once:
`launchCeiling` is 8 (`:48`), held by a `DispatchSemaphore` (`:58`) around the
whole run. A caller may ask for more; what it gets is a queue. Nothing deadlocks
on itself, because a thread holding a slot is inside `readDataToEndOfFile`
(`:156`, `:167`) rather than running code that could ask for a second slot. Output
is drained ahead of the wait, and stderr is `FileHandle.nullDevice` (`:138`) rather
than an undrained `Pipe`.

Output that gets *streamed* is a different port and keeps stderr on purpose,
merged onto the one pipe
(`Sources/Modules/Homebrew/Engine/SystemPorts.swift:148`) — a console shows what
the tool says. Output that gets *parsed* carries no diagnostics (`:109`). The
stream is split into whole lines on the newline **byte** by `LineBuffer`
(`Sources/Modules/Homebrew/Engine/SystemPorts.swift`, documented from `:18`),
decoded with `String(decoding:as:)`, so a multi-byte character straddling a read
boundary stays in the buffer instead of taking its whole chunk with it, and bytes
that are not UTF-8 at all come through as replacement characters. The readability
handler treats an empty read as end of file, flushes the buffer and only then waits
for the exit (`:156`–`:166`), so the last line a tool prints reaches the console.
A launch that fails clears the handler and reports at once (`:177`), because no
end-of-file is coming.

A privileged command carries its content rather than a path: a staged file's path
stands in `ps auxww` while the prompt is up. The escaping is `AppleScript.literal`
(`Sources/HelmRuntime/AppleScript.swift:24`), backslash replaced before quote —
the order is the whole security property — and
`AppleScript.administratorShellScript` (`:31`) is the one place that composes the
privileged line.

### Running applications

`NSWorkspace.runningApplications` and `.frontmostApplication` are read on the
main thread only. A read from another thread does not go stale — it crashes
the process: AppKit keeps the running-applications list in a mutable array
behind a KVO helper, `-applications` copies that array under a lock while the
main thread mutates it as apps come and go, and the VPN engine reading it off
its own serial queue segfaulted the whole program inside `_cow_copy` the
moment an app quit at the wrong instant
(`Sources/HelmRuntime/RunningApps.swift:4-24`). The Keyboard module proved the
same fact a second time over `frontmostApplication`, once its gesture moved
onto a background queue and took eight call sites with it
(`Sources/HelmRuntime/FrontmostApp.swift:6`).

There is no safe shape for "a live list, off the main thread", and neither
port offers one. `RunningApps` and `FrontmostApp` read where AppKit publishes
— on the main thread, from the notification that arrives there anyway — and
hand every other thread a snapshot: whoever was running, or in front, a
moment ago. Layout's fix gesture and the Uninstaller's quit loop both call
through the snapshot rather than straight into AppKit
(`Sources/Modules/Layout/Engine/SystemPorts.swift:630`,
`Sources/Modules/Uninstaller/Engine/SystemPorts.swift:239`), because both run
off the main thread by construction — the gesture to keep a slow
accessibility call off the run loop, the quit loop on the transport's own
pool — which is exactly where a straight read would crash.

### Where things are

| What a change touches | Where it lives |
|---|---|
| a module's pure logic | `Sources/Modules/<Module>/Engine/Logic/` |
| its engine, its command enum, its store | `Sources/Modules/<Module>/Engine/` |
| its screen | `Sources/Modules/<Module>/UI/` |
| its tests, both halves | `Tests/Modules/<Module>/EngineTests/`, `Tests/Modules/<Module>/UITests/` |
| what crosses the engine/host boundary | `Sources/HelmContract/` |
| plumbing two modules both want | `Sources/HelmRuntime/` |
| a string or a control two modules both draw | `Sources/HelmUI/` |
| a token — surface, motion, colour, radius | `Sources/HelmUI/DesignSystem/` |
| the translations | `Sources/HelmUI/Resources/` |
| the window, panel, status item, settings, changelog | `Sources/HelmApp/` |
| plumbing a test target wants | `Tests/Support/` |
| build, sign, package, disk image | `Scripts/` |

## UI shell

### The menu-bar panel

`Sources/HelmApp/PanelWindow.swift` carries the window,
`Sources/HelmApp/PanelChrome.swift` the chrome around the card,
`Sources/HelmApp/PanelBars.swift` the four rows of the card that are not tiles,
and `Sources/HelmApp/HelmPanel.swift` the card and the drag. The rules that decide
the grid and the drag are pure and live one target away, in
`Sources/HelmUI/PanelGrid.swift` and `Sources/HelmUI/PanelDrag.swift`, which is
why the view that draws the grid has been rewritten without the rules moving.

`Sources/HelmApp/PanelWindow.swift:94` sets `panel.hasShadow = false`: AppKit
derives a transparent window's shadow from the alpha of its content, and the
content is a card floating at the top of a strip that runs to the bottom of the
screen, so the shadow traced the strip rather than the card. Glass carries its own
shading. The strip is wider than the card by `helmPanelShadowMargin` on each side
(`Sources/HelmApp/PanelWindow.swift:56`), because glass draws its shading inside
the view and at equal widths the card's shading was cut off flat. There is no
custom `hitTest` anywhere in the panel — a transparent SwiftUI tap area posts the
dismissal instead, and `Sources/HelmApp/PanelWindow.swift:103` records why a plain
`NSHostingView` is used. `panel.orderFrontRegardless()` is followed by
`panel.makeKey()` (`Sources/HelmApp/PanelWindow.swift:126`): a non-activating panel
leaves SwiftUI animations unticked until it is key.

`helmPanelWidth` is 320 (`Sources/HelmApp/PanelWindow.swift:48`), and the number
has an arithmetic behind it: `PanelGrid.minimumTile` is 144, `PanelGrid.padding`
12 and `PanelGrid.gap` 8 (`Sources/HelmUI/PanelGrid.swift:44`), so
`PanelGrid.narrowestPanel` (`Sources/HelmUI/PanelGrid.swift:57`) is
`2 * 144 + 8 + 2 * 12`. A card of 300 bought two columns ten points under the
app's own floor. `Tests/HelmAppTests/PanelWidthTests.swift:8` and
`Tests/HelmAppTests/CardEdgesAreTheGridsConstantsTests.swift:25` are the guards
that keep the card's edges the grid's constants rather than numbers typed twice.

A widget size is a word: `compact`, `wide`, `tall`
(`Sources/HelmUI/PanelGrid.swift:12`). `PanelGrid.resolve`
(`Sources/HelmUI/PanelGrid.swift:84`) clamps a size a module no longer offers to
its neighbour, and `PanelGrid.rows` (`Sources/HelmUI/PanelGrid.swift:142`) packs so
a full-width tile has a row to itself. SwiftUI has no column span, so the grid is
rows of `HStack`.

`PanelLayout` (`Sources/HelmUI/PanelLayout.swift`) carries two different refusals,
`dismissed` and `hidden` (`Sources/HelmUI/PanelLayout.swift:99`): one list saying
both made taking a widget off look like deleting the module. Its `init(from:)` is
hand-written and uses `decodeIfPresent` throughout
(`Sources/HelmUI/PanelLayout.swift:43`): a synthesised `Decodable` throws on a
missing key and `JSONDecoder` then abandons the whole document, so one field added
by a later build would cost everybody their arrangement. The layout's store key is
`panelWidgets` (`Sources/HelmApp/PanelLayoutStore.swift:14`), and
`module.app.panelLayout` is in `ObsoleteDefaults.retired`
(`Sources/HelmRuntime/ObsoleteDefaults.swift:13`), so a layout stored under the
older name is purged at launch.

`Sources/HelmApp/PanelWindow.swift:194` declares `.helmPanelDidShow`.
`Sources/HelmApp/StatusItemController.swift:19` makes the panel `lazy`, so the
content view stays mounted for the life of the app and `onAppear` fires once;
anything that has to happen per opening listens for that notification.
The bars carry no lifetime of their own —
`Tests/HelmAppTests/PanelBarsCarryNoLifetimeTests.swift:25` is the guard. A
`@State` in one of them would be a second owner of a lifetime the panel steers by,
and its failure would look like a tile left hanging under the pointer rather than
like anything thrown or logged.

The panel's two bar heights are `CGFloat?`
(`Sources/HelmApp/HelmPanel.swift:58`, `:59`), `nil` until measured, on the
contract `helmMeasuredHeight` states
(`Sources/HelmUI/DesignSystem/HelmAccordion.swift:65`), because
`PanelGrid.roomForGrid(strip:top:foot:)` (`Sources/HelmUI/PanelGrid.swift:125`)
reads `nil` as "not drawn" and `0` as "drawn, not yet measured" — two facts a
`CGFloat = 0` cannot tell apart.

### The status item

`Sources/HelmRuntime/StatusPlan.swift` is the pure rule. `StatusPlan.choose`
(`:64`) reads every enabled module's appearance and returns, in order: the module
whose spin is still running, else the first that tints, else the first that carries
a title. `StatusPlan.spinDuration` is 1.2 s (`:22`). The title tier is last because
a tint is a permanent presence in the menu bar and a title is a moment; a moment
does not interrupt continuous state.

`StatusPlan.frame` (`:99`) applies its bound to the `Double` before the conversion
to `Int` and guards `frameCount > 0` first: a conversion inside a clamp is not
protected by it, and an empty frame array makes the phase infinite, whose product
with zero is a NaN that passes through `min` and `max` untouched.
`StatusPlan.redrawKey` (`:128`) had the same shape and takes the same repair,
through `Sources/HelmRuntime/Clamped.swift`. Two ticks drive the icon
(`Sources/HelmRuntime/RepeatingTick.swift`): one per second while a countdown runs
and one of `1.0 / 30` while a spin does
(`Sources/HelmApp/StatusItemController.swift:89` and `:95`).

### The Settings window

`Sources/HelmApp/SettingsWindow.swift` builds an `NSSplitViewController` whose
sidebar is the source list at the window's full height, with
`allowsFullHeightLayout` set (`:195`). `NSSplitViewController` supplies the glass
itself, which is why nothing draws an `NSVisualEffectView` behind it — one would
block it.

`sizingOptions = []` on both hosting controllers (`:180`, `:224`): by default
`NSHostingController` feeds SwiftUI's ideal size into auto layout, and a pane whose
ideal height is unbounded grows the window to the full screen. With sizing options
off, panes fill whatever the window gives them, and not the reverse. One size
serves every page — `defaultSize` 1060×700 (`:30`), `minSize` 860×540 (`:32`) —
because the Disk screen needs an 810 pt detail pane, and because a window that
resized per page would move under the cursor. The shared detail frame is pinned
`.topLeading` (`:494`, `:560`), since centring on the horizontal axis as well is
invisible until the one time a row asks for more than the pane has.

`SettingsSelection` has four cases and two of them are not modules
(`Sources/HelmApp/SettingsWindow.swift:83`): `.general`, `.about`, `.log` and
`.module(String)`. That distinction is what keeps the Log pane out of
`ModuleRegistry.all` and so out of the store, the panel, the tour and every
count. `ModuleOrder` reorders that same kind of id list too, but nothing in
`Sources/` calls it — only its own tests do. The only registry count drawn is About's
(`Sources/HelmApp/AboutPage.swift:101`); the sidebar summary counts the
arrangement (`Sources/HelmApp/AppStrings.swift:529`). The Log row ships on every
build, because the logging switch lives in it
(`Sources/HelmApp/SettingsWindow.swift:87`). `show(selecting:)`
(`Sources/HelmApp/SettingsWindow.swift:64`) opens directly on a module's page.

### The page header

The strip a settings page opens with is the system's 52 pt and lies over the page
rather than above it: `helmPageHeader`
(`Sources/HelmUI/DesignSystem/HelmPageHeader.swift`) applies it as a modifier, so
content scrolls behind its material. A page whose top band stays put draws
`HelmPageHeader` as an ordinary view instead and gets no edge, which is why the
guard that reads these pages hunts for both spellings.

There is no rule at rest. What macOS lights instead is the whole strip, for two
reasons — the pointer resting on it while the window is key, and the page having
scrolled underneath. `HeaderEdgeLight`
(`Sources/HelmUI/DesignSystem/HelmPageHeader.swift:81`) asks
`isLit(hovering:active:scrolled:)`
(`Sources/HelmUI/DesignSystem/HelmPageHeader.swift:182`) once and feeds both the
fill and the rule from that single answer, so the two cannot disagree. Lighting is
a fill rather than a material, which is the only reason it is verifiable offscreen
at all: `cacheDisplay(in:to:)` renders model values, glass excluded.

### The sidebar is an arrangement

`Sources/HelmUI/SidebarLayout.swift` is sections of module ids: a `Codable` value
whose invariant is that every registered module appears exactly once.
`Sources/HelmApp/SidebarLayoutStore.swift` reads and writes it, and reading is
where the invariant is enforced rather than trusted — the bytes were written by a
build that is not necessarily this one.

The window's sidebar and the status item's menu both draw the same store, so there
is one arrangement rather than two that agree by habit. Neither observes
`UserDefaults`; both listen for `.helmModuleOrderChanged`
(`Sources/HelmRuntime/NamespacedStore.swift:162`), posted on every write.

Where a drop lands is arithmetic: `SidebarLayout.flattened`
(`Sources/HelmUI/SidebarLayoutDrag.swift:30`) turns the layout into headings and
their modules, and `SidebarLayout.applyingDrag(of:toFlatIndex:)`
(`Sources/HelmUI/SidebarLayoutDrag.swift:38`) answers what the layout becomes.
Both are members of `SidebarLayout`; the file is named after what it adds, not
after a type of its own. The pair is pure and tested, which is why the view
that draws the list has been rewritten without the drop rules moving.
`Sources/HelmApp/SidebarComposerSheet.swift` is the composer's only entry: it
builds `SidebarComposerList` at `:182` with `editing: true`, is the sheet's own
writer of the arrangement (`:137`), and the only sender of
`.helmModuleOrderChanged` (`:146`). The list still has two states and one row
height in both — at rest a list of what the sidebar holds with every switch
live, and in edit the grips, the section menus and the buttons that change the
arrangement — but with the composer reachable only through the sheet,
`editing: true` is what it always opens with; the at-rest state is unreachable
today. The composer was an `NSTableView` once, driven by `SidebarComposerRedraw` through
`SidebarComposerTable`; two animation systems in one list cost more than the table
saved, and both names survive only in the prose about their removal.

### A window a module needs and the host owns

`Sources/HelmUI/HostWindow.swift` is the base class for a window the host owns on
a module's behalf. Three things live in it: the activation-policy round trip —
Helm is an accessory app, so a window ordered front without `.regular` opens behind
whatever the person is looking at, and one that stays `.regular` leaves a Dock icon
the app did not earn; a `closed` flag (`Sources/HelmUI/HostWindow.swift:45`),
because `close()` is what makes AppKit call `windowWillClose` and an unguarded
callback records a refusal twice; and `isReleasedWhenClosed = false` (`:62`),
because the holder is a Swift reference. `command grep -rn ': HostWindow' Sources/`
lists the subclasses.

The host cannot import a module's engine, so a module that has something to say
vends one opaque door: `TrashedAppOffer.sweep(vm:onClose:)` returns a view or
nothing, and `TrashedAppOffer.windowTitle` is the module's spelling of a title the
`NSWindow` still belongs to the host to set
(`Sources/Modules/Uninstaller/UI/TrashedLeftoversView.swift:21`,
`Sources/HelmApp/TrashedLeftoversWindow.swift:25`). Nothing means no window at all
rather than an empty one.

`.helmModuleEnabled` (`Sources/HelmUI/MenuBarContribution.swift:55`) is posted from
`ModuleHost.setEnabled` (`Sources/HelmApp/ModuleHost.swift:60`) and not from
bootstrap: it means somebody switched this on, which is the moment a module may act
unasked. `.helmModuleDisabled`
(`Sources/HelmUI/MenuBarContribution.swift:50`) is its opposite number.

Every way out of such a window is an answer, including the red button, so the
refusal is recorded and awaited rather than fired.
`TransportClient.send(_:payload:)` (`Sources/HelmUI/TransportClient.swift:47`)
exists for that, beside the `fire` (`:29`) that is not awaitable.

### Revealing a path

`NSWorkspace.open` on a bundle launches it, and on a package it mounts or opens it
— a disk scan lists the top-level children of a bundle, so a stale row pointing
inside one is reachable. `HelmReveal.target`
(`Sources/HelmUI/DesignSystem/HelmReveal.swift:56`) asks the enclosing folder's
traits instead: a plain directory is opened to its contents, a package is selected
in its parent with `activateFileViewerSelecting`, which highlights without
launching or mounting, and an enclosing folder that is itself gone reveals nothing
rather than acting on half the request. `inFinder` (`:94`) returns nothing: the
half of that promise that can be kept honestly is `target(for:)` answering `nil`
before the button is drawn.

## Subsystems

One section per module, in the order `ls Sources/Modules` prints.

### Autopilot

`Sources/Modules/Autopilot/` acts on somebody's files without being asked each
time, so its boundary is a set of refusals rather than a set of capabilities.

Rules live in a plist any process running as the user can write, so authorship is
settled by an HMAC keyed from a secret in Helm's own login keychain item
(`Sources/Modules/Autopilot/Engine/RuleKeychain.swift:13`, service
`com.helm.autopilot`); a rule set whose seal disagrees decodes to `[]`. What says
a migration is due is the absence of the keychain item rather than the absence of
the seal. `Sources/Modules/Autopilot/Engine/AutopilotEngine.swift` serialises
reading, judging and recording that judgement under one lock, because the rules are
read from four places — the hourly sweep, FSEvents, the transport and the watch
refresh.

`WatchScope` bounds what even a rule Helm itself sealed may reach. What a rule can
do is `RuleAction` (`Sources/Modules/Autopilot/Engine/Logic/RuleAction.swift:13`):
`move`, `sortIntoSubfolder`, `rename`, `addTag`, `trash` — five cases and no script
action; `command grep -rn 'case script\|runScript\|shellAction' Sources/Modules/Autopilot/`
prints nothing. What a rule can ask about is `RuleCondition`
(`Sources/Modules/Autopilot/Engine/Logic/RuleCondition.swift`): name, baseName,
fileExtension, kind, size, dateAdded, dateModified, downloadedFrom, tag.

A rule acts on one file once because
`Sources/Modules/Autopilot/Engine/RuleStamp.swift:25` writes the extended attribute
`com.helm.autopilot.stamp`, which travels with the file across a move. A stamp that
will not stick is logged and tolerated, which is survivable only because sorting,
moving and tagging recognise a file already where the rule would put it. Renaming
tells "already done" from "do it again" by inspecting the name against
`Sources/Modules/Autopilot/Engine/Logic/RenameShape.swift`.

Three triggers reach the runner and none covers the others: FSEvents coalesced at a
second, an hourly sweep, and run-now. Each names itself while it runs:

```bash
command grep -o 'autopilot\.[a-zA-Z]*' \
  Sources/Modules/Autopilot/Engine/AutopilotEngine.swift | sort -u
```

prints `autopilot.preview`, `autopilot.runNow`, `autopilot.sweep` and
`autopilot.watch`. One funnel,
`Sources/Modules/Autopilot/Engine/Logic/RulePlan.swift`, decides for the dry run,
the sweep and the live arrival alike, so the three cannot disagree about what will
happen.

The history is a second sealed document in the same plist:
`Sources/Modules/Autopilot/Engine/Logic/ActionHistory.swift` is what a return
replays, and a forged record is a ready-made way to move a file with Helm's Full
Disk Access, so `Sources/Modules/Autopilot/Engine/UndoRunner.swift` checks the
record's shape, `WatchScope` on both ends, and device-and-inode identity through
`PathCanonical.FileIdentity`. A history seal that fails to verify freezes the
history rather than being overwritten or deleted.

### Disk

`Sources/Modules/Disk/` answers where the space went, so it is the one module
whose reading may not leave the largest folder out.

On an APFS volume group `/` is the read-only System volume with the Data volume's
directories firmlinked in, and both mounts report the same `dev_t`, so a device
check cannot separate them and every user file is reachable twice.
`Sources/HelmRuntime/FirmlinkMap.swift:21` reads macOS's own table at
`/usr/share/firmlinks` and skips the Data-side duplicates. That skip set matches
only while paths are joined through `Sources/HelmRuntime/ScanPath.swift:16`.
`BulkWalk.DeviceID` (`Sources/HelmRuntime/BulkWalk.swift:90`) wraps a signed
`st_dev`. Folder names on screen come from
`Sources/HelmRuntime/SystemFolderNames.swift`, which reads macOS's own
`SystemFolderLocalizations` table; eligibility is decided by path rather than by
the name shown.

`Sources/Modules/Disk/Engine/DiskScanner.swift:89` refuses descent into the
media-library bundles `ScanRoot` names
(`Sources/HelmRuntime/ScanRoot.swift:131`) only when `unattended` is true — a
person watching the ring gets the whole volume. The refusal is by name, so no
directory is read in order to decide whether to read it, and
`Sources/Modules/Disk/Engine/Logic/UnattendedAdvice.swift` applies the `~/Library`
refusal at the report rather than at the descent.

A scan has an identity:
`Sources/Modules/Disk/Engine/Logic/ScanRegistry.swift` hands out a token only its
owner can spend, and every event names its scan, so a second walk started by
drilling into an unmeasured folder cannot clear the first one's slot.

`Sources/Modules/Disk/Engine/Logic/DiskAdvisor.swift:125` names three cache folders
whose *contents* are regenerable; `~/Library/Caches` itself carries
`group:everyone deny delete`, so an advice carries the children and
`Sources/Modules/Disk/Engine/Logic/DiskRemovalPlan.swift` swaps them in — every
child then goes through `UserFileScope.partition` and `HelmTrash.remove` like any
other path.

The ring lays out one level more than it draws:
`Sources/Modules/Disk/UI/RingView.swift:53` is `visibleRings = 3` and
`Sources/Modules/Disk/UI/DiskViewModel.swift:596` asks `RingView.visibleRings + 1`
levels, so the level that becomes outermost after a drill has somewhere to slide in
from. The drill lands before the animation starts: `onSelect` runs first and the
animation carries a snapshot of the layout being left out over the top.

### Duplicates

`Sources/Modules/Duplicates/` decides which of several identical files is the extra
one, and that decision is a belief rather than a fact the disk holds.

`Sources/Modules/Duplicates/Engine/Logic/KeepPolicy.swift:22` offers two beliefs:
`byPlace` (the default, `KeepPolicy.standard`) treats where a copy sits as the
deciding fact, and `byDate` keeps whichever arrived first. One ladder answers both
what stays and why — five rungs per policy, `[.place, .undated, .date, .depth,
.name]` and `[.undated, .date, .place, .depth, .name]` — and
`Sources/Modules/Duplicates/Engine/Logic/SurvivingCopy.swift:61` reads that one
ladder for both the ordering and the `KeepReason` the screen shows.

An APFS clone shares its blocks, so a group's size is not what deleting it returns.
`Sources/HelmRuntime/CloneShare.swift:20` reads the clone family id and
`CloneShare.reclaimable` counts a family once, and not at all when a member of it
survives. A file whose id cannot be read counts as its own.

Acting on a finding re-reads the pair:
`Sources/Modules/Duplicates/Engine/DuplicateVerification.swift` is its own phase
beside the removal. `DuplicateVerification.Batch` memoises the survivor's reading
only, for the life of one press; the copy about to stop existing is read from disk
in full every time. Stop
(`Sources/Modules/Duplicates/Engine/DuplicatesEngine.swift:648`) is honoured
between files rather than mid-read.

The unattended walk is narrower than the watched one:
`Sources/Modules/Duplicates/Engine/DuplicateScanner.swift:330` asks
`ScanRoot.refusesDescentInHome` of every directory the walk meets when `unattended`
is set, so the `~/Library` subtrees macOS guards with TCC stay out of the 0600
journal.

### Homebrew

`Sources/Modules/Homebrew/` runs somebody else's package manager, and its two kinds
of run are governed differently on purpose.

The read-only queries carry a deadline —
`Sources/Modules/Homebrew/Engine/SystemPorts.swift:83` is
`defaultQueryTimeout: TimeInterval = 90`. Past it `HelmProcess` answers
`HelmProcess.timedOutStatus` (`Sources/HelmRuntime/HelmProcess.swift:74`, the value
`-2`) with no output. The five long operations stream and no clock ends them. A
timed-out query answers nil and the view model keeps what it had, so a full Cellar
is not drawn as "no packages"; the refusal is a named line in the log instead. The
one query that retries halves its batch rather than its timeout.

Quitting mid-operation is reported rather than prevented: every operation writes a
marker through the `OpMarker` port
(`Sources/Modules/Homebrew/Engine/Ports.swift:66`), whose real implementation
`FileOpMarker` (`Sources/Modules/Homebrew/Engine/SystemPorts.swift:220`) is a file,
so it survives the quit it exists to report and the next launch's first `status()`
answers `interruptedOp` (`Sources/Modules/Homebrew/Engine/Model.swift:77`).

One phase covers all five long operations —
`Sources/Modules/Homebrew/Engine/HomebrewEngine.swift:275` is
`operationPhase = "homebrew.operation"`, opened in `beginBusy` and closed in
`endBusy`, which is the one `begin` in the app with no `defer` on the next line,
because an operation ends in a callback. The queries hold scoped phases of their
own. Package names travel as array elements after `--`, so a name starting with a
dash is a package rather than a flag, and they reach the log through `Redact.pkg`
(`Sources/HelmRuntime/Redact.swift:143`). The engine executes a package reference
straight off the wire with no gate of its own, which is sound only while the
transport is in-process with one sender.

The in-app installer (`installBrew`, `Sources/Modules/Homebrew/Engine/HomebrewEngine.swift:461`)
runs Homebrew's own `install.sh`, fetched over HTTPS from `installerURL` (`:46`),
which names `HEAD` rather than a pinned revision or checksum — whatever the branch
holds the day the button is pressed. Before the download, one administrator dialog
authorizes `/bin/mkdir -p /opt/homebrew && /usr/sbin/chown -R '<user>':admin
/opt/homebrew` (`:481`), which is the only privileged step; the installer itself then
runs as the now-owning user. See «Giving everything back» for why that ownership
change is the one reach this document does not describe as reversible.

### Hosts

`Sources/Modules/Hosts/` edits `/etc/hosts`
(`Sources/Modules/Hosts/Engine/Logic/HostsWrite.swift:58`) and manages SSH keys,
and both halves are built around the same idea: the bytes are canonical and a parse
is a reading rather than a representation.

`Sources/Modules/Hosts/UI/HostsViewModel.swift` holds one string; the rows are
derived from it on every read and every row editor writes back into that same
string through `Sources/Modules/Hosts/Engine/Logic/HostsFile.swift`. A hosts file
carries comments, alignment and lines this parser leaves unmodelled, so a round
trip through a structure would reformat somebody's file.

Privilege crosses one door. `HostsWrite.command(base64:)`
(`Sources/Modules/Hosts/Engine/Logic/HostsWrite.swift:127`) refuses anything outside
the base64 alphabet, which holds no quote, dollar, backtick, semicolon, backslash or
newline, so nothing an encoded payload contains can end root's AppleScript literal.
The command carries its content rather than a path. The shell's own decoder counts
the bytes first and the redirect does not exist until that count matches, because
redirection truncates before the decoder runs. `HostsWrite.fits`
(`Sources/Modules/Hosts/Engine/Logic/HostsWrite.swift:83`) answers whether the
sentence would survive its own `execve`, which caps a writable hosts file at roughly
390 KB; larger files are still shown, and said so on open.

There is no rule in `/etc/sudoers.d` for this module — of every module naming it,
only Keep Awake's is a rule of its own:

```bash
command grep -rln 'sudoers.d' Sources/ --include='*.swift' | command grep 'Modules/'
```

Every Apply is one dialog, and `PrivilegedOutcome` keeps "you cancelled" and "the write failed" apart
all the way to the screen. A port reporting success is believed by nothing but the
read-back, compared by digest through `Sources/HelmRuntime/HexDigest.swift` because
the log carries no names.

The keys tab holds the one secret this app has.
`Sources/Modules/Hosts/Engine/PTYProcess.swift` exists because
`ssh-keygen -N '<passphrase>'` would put the passphrase in `ps auxww`: it opens a
pseudo-terminal with `posix_openpt`, spawns with the slave end on all three
descriptors and `POSIX_SPAWN_SETSID`
(`Sources/Modules/Hosts/Engine/PTYProcess.swift:89`), and writes the answer to the
master when the child asks. The secret is taken `inout`
(`Sources/Modules/Hosts/Engine/PTYProcess.swift:57`) and zeroed on every path out,
and no `String` is made of it inside that file.
`Sources/Modules/Hosts/Engine/Logic/Secret.swift` is the only payload shape in the
module that can carry one; the other acts take a key name, which has no field for a
secret.

`Sources/Modules/Hosts/Engine/Logic/KnownHostsFile.swift` keeps every line exactly
as written and renders by joining those bytes, so a round trip holds by
construction and the only edit is dropping a line whole. A hashed file is an
ordinary file: forgetting is by line, and a line is something the file can identify
in every case.

### KeepAwake

`Sources/Modules/KeepAwake/` holds sleep off. Its logic units are pure and its
engine is the orchestration between them and the ports:
`ls Sources/Modules/KeepAwake/Engine/Logic/` is the list, and
`Sources/Modules/KeepAwake/Engine/KeepAwakeEngine.swift:10` names Conditions,
ExternalDisplaySupport, BatteryGuard, TimerPolicy, JiggleTarget and
ClamshellRecovery as the units it drives.

The module lifecycle and the session are separate axes: `activate()`/`deactivate()`
are the host enabling the module, while the keep-awake session runs through
`startSession`/`stopSession`/`toggleSession`.
`Sources/Modules/KeepAwake/Engine/Logic/Conditions.swift` is why a session is being
held, and its raw values are the wire names, so both sides of the transport spell
the reason the same way.
`Sources/Modules/KeepAwake/Engine/Logic/TimerPolicy.swift` is what the module
believes about a timed session — how long one may be, and whether running out
deactivates or continues as automatic.
`Sources/Modules/KeepAwake/Engine/Logic/BatteryGuard.swift` and
`Sources/Modules/KeepAwake/Engine/Logic/BatteryVetoNews.swift` are the battery's
veto and the sentence it earns.

Two things here cross out of the module's own process. The pointer jiggle
(`Sources/Modules/KeepAwake/Engine/Logic/JiggleTarget.swift`) resets the system idle
counter, which is why `Sources/HelmRuntime/ScanSchedule.swift` declares
`.helmPointerNudged` — the poster and the listener sit in targets that cannot see
each other. And `Sources/Modules/KeepAwake/Engine/ClamshellCoordinator.swift` is the
one thing in the app that outlives its own process: `pmset disablesleep 1` is
system-wide and stays in force after Helm quits, reached through a NOPASSWD rule at
`/etc/sudoers.d/helm-keepawake`
(`Sources/Modules/KeepAwake/Engine/Logic/SudoersRule.swift:25`). That rule's text is
pure data in a logic unit rather than a comment, it ends with an argument-exact
entry permitting only its own removal, so the grant carries its own revocation and
the withdrawal costs no dialog. It lives in its own coordinator so the code that can
leave a Mac unable to sleep is separable from the session logic, which only asks for
the lid and is told whether it got it. That coordinator is
`@unchecked Sendable` rather than `@MainActor` (`:30`), which is load-bearing: a
callback arriving on a background queue does its check on that queue rather than
after the caller has returned. Two facts it is told rather than asks —
`sessionIsActive` and `stateChanged` (`:56`, `:57`) — because both can change while
a password prompt is up. Who may *raise* the prompt is a separate question from
what the prompt runs: `consumeEdge()` (`:481`) answers an `Edge` (`:490`), and the
engine reads it before its own active guard
(`Sources/Modules/KeepAwake/Engine/KeepAwakeEngine.swift:449`–`:450`), so the rising
edge installs, the falling edge withdraws, and neither is inferred from a value that
stays true after a dialog was declined. That edge was `consumeRisingEdge` until the
rename, and the pair of names is the account of a document that outlived its
subject.

A veto that ends everything is on the wire under its own name, and the engine
refreshes the published sets *before* the veto returns
(`Sources/Modules/KeepAwake/Engine/KeepAwakeEngine.swift:568`–`:575`), so a screen
drawn under a veto is not drawn from whatever the sets held when it began. Two sets
exist deliberately: `activeConditions` is the list of reasons the Mac is *currently*
being held, and is empty for a suppressed rule; `triggeredConditions`
(`Sources/Modules/KeepAwake/Engine/KeepAwakeEngine.swift:75`) is the set of triggers
that hold whether or not they are being obeyed, built once from the same three
expressions the stop path consults, so the screen and the behaviour cannot come
apart. The row's four states are decided in one pure place,
`RuleNote.of(enabled:satisfied:batteryStopped:suppressed:triggerHolds:)`
(`Sources/Modules/KeepAwake/Engine/Logic/RuleNote.swift:51`), where the veto
outranks the pause (`:54`) and `triggerHolds` is per-rule rather than the module's
own flag.

### Layout

`Sources/Modules/Layout/` reads every keystroke and types into other applications,
which is a larger claim on the machine than anything else Helm does. Four things
bound it.

The tap is listen-only: `Sources/Modules/Layout/Engine/SystemPorts.swift:104`
passes `options: .listenOnly`, so it reports keys and can neither delay nor swallow
them. Replacement is synthesised Unicode through `keyboardSetUnicodeString`
(`Sources/Modules/Layout/Engine/SystemPorts.swift:344`) rather than the clipboard.
Translation goes through `UCKeyTranslate`
(`Sources/Modules/Layout/Engine/SystemPorts.swift:532`) against the layouts actually
installed. Helm's own events carry a marker on `CGEventSource.userData`
(`Sources/Modules/Layout/Engine/SystemPorts.swift:311`) and are dropped on the way
in, so the tap does not read its own replacement back as typing.

The decision to convert is
`Sources/Modules/Layout/Engine/Logic/LayoutVerdict.swift` — a list of reasons to
decline with one way through: the word is not a word as typed and is one once
translated. Secure input, password fields, terminals and password managers are
refused before the dictionary is consulted. The gesture and the hotkey skip the
dictionary and are judged by `decideForced`
(`Sources/Modules/Layout/Engine/Logic/LayoutVerdict.swift:125`) against the same
exceptions, as pure logic beside `decide` rather than a clause in the engine.

What the module keeps from typing is a count.
`Sources/Modules/Layout/Engine/Logic/ConversionLedger.swift:35` stores words and
characters per day and nothing else, and
`command grep -rni 'vocabulary\|learned:\|salted' Sources/Modules/Layout/` prints
nothing. The one path from typed text to a file is the page's button for excluding
a word, which writes into
`Sources/Modules/Layout/Engine/Logic/Exceptions.swift`'s plist in cleartext, and it
is closed for a forced conversion.

Which layout a word is converted *into* is
`Sources/Modules/Layout/Engine/Logic/OtherSource.swift` rather than "the first that
is not the current one", because three installed sources are ordinary.

The selection actions are the one exception to the no-clipboard rule: they have two
routes, the accessibility API where the app answers and ⌘C/⌘V where it does not.
`Sources/Modules/Layout/Engine/Logic/PasteboardSafety.swift:30` gates both, because
a string restore cannot give back an image, a file promise or RTF, and the read
destroys as thoroughly as the write.

The engine holds no strings: it emits announcements over a port and the UI side
speaks them, gated on VoiceOver being on. The emoji item in the menu-bar indicator
is drawn only when Accessibility is granted, because the only route that works is
pressing the frontmost app's own Edit-menu item through the accessibility API —
`Sources/Modules/Layout/UI/EmojiPalette.swift:79` is `@MainActor` and returns false
when the grant is missing.

### Leftovers

`Sources/Modules/Leftovers/` finds login items and plug-in files whose owner is
gone. Its boundary is what it will *offer*, and the rules err toward leaving things
alone: `Sources/Modules/Leftovers/Engine/Logic/StaleItemRules.swift` keeps anything
Apple's, anything in a system location, anything whose owner is still installed, and
anything whose owner cannot be identified.

Its removal path goes through `RemovableScope.partition` inside
`Sources/Modules/Leftovers/Engine/LeftoversEngine.swift` and then through
`HelmTrash.remove`; the engine reaches the gate with its own `home` rather than the
process's, so the scan and the removal gate cannot be looking at two homes.

Turning a login item off is not deleting it:
`Sources/Modules/Leftovers/Engine/Logic/LaunchctlDisabled.swift` writes the same
per-user disabled-label list the system's own Login Items switches write, so nothing
on disk changes and the choice survives a reboot and can be undone in System
Settings. That switch is aimed at a launchd *label*, and a label is not a file —
`Sources/Modules/Leftovers/Engine/Logic/LaunchClaims.swift` is what says how many
files claim one switch, since a vendor's agent commonly sits in both
`~/Library/LaunchAgents` and `/Library/LaunchAgents` and both load into the same GUI
domain.

`LeftoversEngine` keeps its own record of the labels it disabled
(`Sources/Modules/Leftovers/Engine/LeftoversEngine.swift:34`), so switching the
module off gives back exactly those and nothing the person switched off in
System Settings. `willDisable()` (`:81`) reads that record rather than the
system's own disabled list, because the system's list holds every switch anybody
threw and giving those back would be Helm undoing a decision that was never
Helm's; the edge that record cannot close is in «Giving everything back».

Writability is asked of a directory rather than of each item in it: the port is
named for that in `Sources/Modules/Leftovers/Engine/Ports.swift`.
`Sources/Modules/Leftovers/Engine/Logic/LeftoversSilence.swift` is the page's answer
to a request nobody answered — said once, whichever of the two went unanswered,
because a transport request answers nil both for a throw and for a reply that would
not decode.

### Uninstaller

`Sources/Modules/Uninstaller/` removes an application and the files it left behind,
which makes "does this path belong to the app being removed" the whole question at
its boundary.

A path a pattern produced is a candidate rather than a finding.
`Sources/Modules/Uninstaller/Engine/Logic/GlobMatch.swift` supports any number of
wildcards, and a prefix glob on a bundle id matches a *different* vendor's app, so
glob results are filtered against the installed set two ways at once:
`AppLister.isKnownToSystem` asks LaunchServices and `installedPaths(forBundleID:)`
asks the directory listing
(`Sources/Modules/Uninstaller/Engine/Ports.swift:17` and `:25`,
`Sources/Modules/Uninstaller/Engine/SystemPorts.swift:33` and `:48`). The exact
candidates go through the same filter, because their hazard is different — an app
that declares somebody else's bundle id in its own Info.plist.
`Sources/Modules/Uninstaller/Engine/Logic/LeftoverOwnership.swift` is where that
verdict is formed, and
`Sources/Modules/Uninstaller/Engine/Logic/OrphanDetector.swift` is deliberately
conservative: only entries whose name looks like a bundle id are considered at all,
and Apple's domains are skipped outright.
`Sources/Modules/Uninstaller/Engine/Logic/SystemApp.swift` keeps macOS's own apps
off the checkbox entirely, because a refusal after the click is the right
explanation at the wrong moment.

Quitting is asked rather than assumed. `UninstallerEngine.waitUntilGone`
(`Sources/Modules/Uninstaller/Engine/UninstallerEngine.swift:275`) polls to a
deadline, and the deadline ends the *wait* rather than the question:
`UninstallPlan.verdict(running:mayQuit:)`
(`Sources/Modules/Uninstaller/Engine/Logic/UninstallPlan.swift:99`) is asked again
after the quit loop, and a batch still holding a live app moves nothing and names it
in `stillRunning`. Non-empty `stillRunning` means nothing moved, which is why it is
its own field on `UninstallResult`
(`Sources/Modules/Uninstaller/Engine/Model.swift:107`) rather than a classified
failure — nothing was attempted and macOS said nothing.

The quit is by bundle identifier: `RunningAppsPort.quit(bundleID:force:)`
(`Sources/Modules/Uninstaller/Engine/Ports.swift:117`) names no location, so it
reaches every copy of the app that is running. A fake can only record ids, so "the
wrong copy was quit" is a state no test can express while the port has that shape.

`Sources/Modules/Uninstaller/Engine/Logic/TrashWatch.swift` is the offer that
appears when an app is dragged to the Trash; it needs Full Disk Access to see
anything, and the switch reads the port's live answer rather than the memory of
having been switched on.

### VPN

`Sources/Modules/VPN/` raises and drops tunnels on its own, from rules nobody
presses a button for each time.

Books are keyed by what they are looked up by, and macOS lets two service
configurations carry one display name. The rules book is keyed by the
configuration's own id, with the name kept beside it because a configuration deleted
between two reads is gone from the list and the drop still has to be named.
`VPNNoticeBook` (`Sources/Modules/VPN/Engine/Logic/VPNNoticeBook.swift`) is keyed by
the `scutil` UUID and stores an override only for a configuration somebody changed,
so `nil` means "use what the app says" and there is no migration. Nothing prunes the
book against a `scutil` read, because that tool answers with a short list or none at
all on a refusal or a Mac mid-boot. What stays keyed by name is the auto-connect
book, because `scutil --nc start`/`stop` take a name.

A per-app rule is bound to a signature rather than to a bundle identifier.
`Sources/HelmRuntime/CodeIdentity.swift:28` reads what a bundle is actually signed as
— signing id and team id — and
`Sources/Modules/VPN/Engine/Logic/VPNRuleTrust.swift:55` compares the identity
recorded when the rule's app was picked against what is running under that bundle id
now, at launch only, since a quit has no bundle left to read. Its verdicts
(`Sources/Modules/VPN/Engine/Logic/VPNRuleTrust.swift:33`) are `act`,
`noIdentityRecorded`, `appNotSigned`, `runningInstanceUnreadable`, `mismatch`: a rule
with no recorded identity refuses rather than trusting the name. The bind is real for
an App Store or Developer ID app, and adds nothing against an ad-hoc-signed bundle,
which carries no team identifier.

The tool is asked before the app announces. `scutil --nc start`/`stop` exit `0`
whatever happens and put their answer on stdout, so the port hands back the whole
process result and `Sources/Modules/VPN/Engine/Logic/VPNCommandReply.swift` reads the
status and the stdout together before anything is announced.

The page's own reading is about the tunnel carrying the default route.
`Sources/Modules/VPN/Engine/Logic/VPNExitVerdict.swift:14` is three cases —
`throughTunnel(countryCode:)`, `besideTunnel`, `unknown` — rather than a boolean,
because routing is a local reading that cannot fail silently while the country comes
from a server that can be slow, blocked or wrong. Every reading on
`Sources/Modules/VPN/Engine/Logic/VPNTunnelFacts.swift` is optional and an absent one
is a missing tile rather than a zero. The exit check is the app's one request to a
server that is not the update feed: `TraceExit`
(`Sources/Modules/VPN/Engine/SystemPorts.swift:486`) asks Cloudflare's trace
endpoint, only the two-letter region code leaves the port, and
`Sources/Modules/VPN/Engine/Logic/VPNExitAsk.swift` is the gate every path into a
refresh reaches. `VPNExitAsk.routeMoved` drops the answer when the interface carrying
the default route changes, because the country belongs to the route rather than to a
tunnel.

The speed reading is a press rather than a timer: `/usr/bin/networkQuality`
(`Sources/Modules/VPN/Engine/SystemPorts.swift:568`) spends real traffic for tens of
seconds, so it runs off the cooperative pool and comes back to the serial work queue
(`Sources/Modules/VPN/Engine/VPNWorkQueue.swift`) only to write what it learned.
`Sources/Modules/VPN/Engine/Logic/VPNSpeedReading.swift` takes every field or none,
because a run killed at its deadline prints part of its JSON. Names reach the log
through `Redact.vpn` (`Sources/HelmRuntime/Redact.swift:134`); counts and outcomes
are free. An engine refuses a payload equal in every field to the last one it sent,
so a poll that re-reads behind one connect puts one payload on the wire rather than
many.

The connections are a card grid, and a grid takes its column count from the count
*and* a ceiling. `GridItem(.adaptive(minimum:maximum:))` alone fixes columns from the
available space and leaves a hole beside two cards; the count alone turns one card
into a banner. `Sources/Modules/VPN/UI/VPNGridLayout.swift` states the rule as the
thing it protects — the fewest rows among the column counts that leave at most one
empty slot, since one empty slot at the end of a row reads as a list that finished
and two reads as a layout that failed — with `maxColumns`
(`Sources/Modules/VPN/UI/VPNGridLayout.swift:27`) set by what the card's widest name
needs and `collapsedLimit` (`Sources/Modules/VPN/UI/VPNGridLayout.swift:35`) chosen
so that it divides by every column count the rule can return. A cap needs an order,
or the page hides its own answer: `VPNConnectionOrder.upFirst` puts whatever is up
first and leaves the tail exactly as the system gave it. A locked configuration used
to be kept out of the page-wide banner by `VPNRules.unspokenFor`; the rules moved
into a popover nobody had opened and the filter went with them.

### Background scans

Three modules can measure with nobody watching.
`Sources/HelmRuntime/ScanRunner.swift:30` is
`scannableModules = ["duplicates", "uninstaller", "disk"]`, spelled as a literal
because a module gaining a scan costs a walk of the volume. The list and the
capability are tied by the type system: `BackgroundScanning`
(`Sources/HelmRuntime/ScanReport.swift:29`) has exactly three conformers —
`Sources/Modules/Duplicates/Engine/DuplicatesEngine.swift:13`,
`Sources/Modules/Uninstaller/Engine/UninstallerEngine.swift:8`,
`Sources/Modules/Disk/Engine/DiskEngine.swift:7`.

The clock and the decision are in different targets.
`Sources/HelmApp/ScanCoordinator.swift` owns the one-minute tick, the notification
observer, the reading of live system counters and the transport call;
`Sources/HelmRuntime/ScanSchedule.swift` and `Sources/HelmRuntime/ScanRunner.swift`
are pure and decide. Every refusal is a named verdict — `run`, `off`, `busy`,
`onBattery`, `notDue`, `spent`, `clockSkew`, `notAtTheConsole` — and it is logged on
change only, because a line per module per minute would push everything else out of
the bounded tail.

Two of the conditions are less obvious than they look. Helm resets the idle counter
itself through Keep Awake's pointer jiggle, so `ScanRunner.advance` keeps an estimate
across ticks rather than trusting one reading, and stays at or above the counter. And
idleness is not evidence under fast user switching, so the console session and the
lock state are read as well.

What crosses the transport is deliberately thin.
`Sources/HelmRuntime/ScanReport.swift` is bytes, a count and a list of path and size
— the shape three unlike scanners can all speak — and nil is not an empty report.
`Sources/HelmRuntime/ScanJournal.swift:56` keeps the numbers for the last
`limit = 30` scans per module and the item lists for the newest two, fixed at two
files per module rather than growing with use. It stores no localized text, and it
redirects itself out of the real Application Support when it sees `XCTestCase`
loaded. It sweeps its own abandoned siblings, and the risk is in the judgement rather
than the removal: `abandonedTestJournals`
(`Sources/HelmRuntime/ScanJournal.swift:82`) is pure and tested, liveness is asked of
the kernel, and the sanity check on the number lives inside the decision rather than
beside the kill.

`Sources/HelmRuntime/ScanComparison.swift` is the arithmetic on those two lists and
carries whether there was a previous one at all;
`Sources/HelmRuntime/ScanNews.swift` is what turns that into something worth saying,
measured on appeared bytes alone, and it reaches macOS through the one notification
conversation in `Sources/HelmRuntime/NoticeChannel.swift`. An attempt and a
completion are two facts: a completion holds a module for the interval, an attempt
for the shorter retry interval, and the attempt is written before the work so a crash
mid-walk costs the gap rather than nothing.

## Permissions

`PermissionCheck` (`Sources/HelmRuntime/PermissionCheck.swift:28`) probes Full Disk
Access by reading protected files — `~/Library/Safari/Bookmarks.plist`,
`~/Library/Messages/chat.db` and further fallbacks, because none is guaranteed to exist
and `TCC.db` is absent on recent macOS. A write probe would be wrong: creating a file
under `~/Library/Containers` is refused even where access is granted.

`Scripts/package-app.sh:315` signs ad-hoc (`codesign --force --deep --sign -`), so the
bundle carries no Team ID and macOS ties a granted permission to the exact binary. A
cdhash is a hash of contents, so every rebuild is a different program to TCC while the
checkbox in System Settings stays ticked. A grant therefore survives relaunch and
reboot — the installed binary's cdhash changes only when it is replaced — and every
reinstall costs both toggles again. `AppBuild` (`Sources/HelmRuntime/AppBuild.swift`)
is where the app asks what copy of itself it is: `shortVersion` (`:25`) returns an
optional and picks no default, because the fallbacks that had been written by hand
were not interchangeable; `codeFingerprint` (`:56`) is the identity the permission
audit compares, and `PermissionAuditPlan.shouldSpeak`
(`Sources/HelmRuntime/PermissionAuditPlan.swift:45`) treats an unknown identity as
"cannot tell". `isDev` (`Sources/HelmRuntime/AppBuild.swift:84`) reads the build's own
version string rather than the update channel, which is a picker anybody can move.

A stable signing identity is the only real fix, and the same purchase is what
`NEVPNManager`, an `SMAppService` helper and notarization each need.

`SystemExtensionParser` and `SystemExtensionCLI`
(`Sources/HelmRuntime/SystemExtensionParser.swift:60`) are the single source for
`systemextensionsctl list`; the uninstaller, the leftovers scanner and the settings
audit all parse through them.

### The gates

Five types answer five different questions about where a path may be reached,
and four of them are about reading or removing. The fifth is about writing, and
it is the only one, which is why it reads differently from its neighbours: it
answers *may Helm write this path*, over one file the user owns and Helm did not
create. This is the list of who asks which:

```bash
command grep -rn --include='*.swift' \
  -oE '(RemovableScope|UserFileScope|WatchScope|ScanRoot|SSHFileScope)\.[a-zA-Z]+' Sources/
```

`RemovableScope` (`Sources/HelmRuntime/RemovableScope.swift`) asks what belongs to an
*application*. The rule is positional rather than a blocklist: a path is removable
only strictly inside one of the roots its private `roots(home:)` lists — the user's
own two, `/Applications`, and the `/Library` subtrees an installer writes into:

```bash
sed -n '/private static func roots/,/^    }/p' Sources/HelmRuntime/RemovableScope.swift
```

— minus those in `forbidden`: `/Library/Apple`, `/System`,
`/Applications/Utilities`. A `.app` bundle is removable wherever it lives
as long as it is not a top-level directory.

`UserFileScope` (`Sources/HelmRuntime/UserFileScope.swift`) asks what belongs to the
*user*; Disk and Duplicates read it, and it replaced the disk module's own `DiskSafety`
gate. `WatchScope`
(`Sources/Modules/Autopilot/Engine/Logic/WatchScope.swift`) is Autopilot's own and asks
where an unattended folder rule may reach: inside the home but not the home itself,
outside `~/Library`, and inside `/Volumes/<disk>/` but not at a volume root.
`ScanRoot` (`Sources/HelmRuntime/ScanRoot.swift`) asks where a read nobody is watching
may begin and how far it may descend.

`SSHFileScope` (`Sources/Modules/Hosts/Engine/Logic/SSHFileScope.swift:27`) asks
whether Helm may **write** a path, and it exists because Hosts & Keys is the one
module that edits a file the user wrote by hand. `mayWrite(_:home:under:)` is the
whole gate, and the module's rule that anything it does not parse is written back
byte for byte is the other half of the same care.

Paths reach all four through `Sources/HelmRuntime/PathCanonical.swift`, which resolves
symlinked ancestors and leaves the leaf alone, so a stale alias is trashed rather than
chased. `PathCanonical.ancestryIdentity(of:)` returns the device-and-inode chain that
`Sources/HelmRuntime/HelmTrash.swift` re-reads immediately before each move; the window
between a gate's answer and the syscall's own resolve is narrowed by that re-read and
is not closed by it.

`Sources/HelmRuntime/UserFileScope.swift` compares a path against its protected
prefixes in **both** spellings (`:66`), because `NSString.standardizingPath` (`:31`)
rewrites `/private/var/…` to `/var/…` for a path that exists on disk and leaves it
alone for one that does not. Symlinks are resolved separately (`:33`), since
`standardizingPath` does not follow them, and case is not folded by it at all (`:61`).
`Sources/HelmRuntime/PathCanonical.swift:180` is the shared spelling of the same fact.

### Removal

`HelmTrash.remove` owns the batch itself, whichever module handed it the paths: the
order, one outcome per path, one set of file ids so a hard link counts once, and the
reading of a path's size before it moves. A module keeps its gate and whatever it
knows that macOS's error does not say. The phase a removal runs under is composed
rather than literal — `Sources/HelmRuntime/HelmTrash.swift:117` builds
`"\(module).trash"` from the caller's id — so the shared removal path carries the
name of whichever module is deleting.

Refusals are values rather than silences: `TrashFailure.Reason`
(`Sources/HelmRuntime/PermissionCheck.swift:129`) carries `outOfScope`,
`changedSinceScan`, `unreadable`, `readOnlyVolume`, `diskFull`, `missing`,
`needsFullDiskAccess`, `activeSystemExtension`, `noPermission`, `systemRefused` —
`outOfScope` is Helm refusing before anything was attempted. `TrashFailure`
classifies from the Cocoa error code rather than from the shape of a path.

### One removal at a time

Four modules send a `trash` command — Disk, Duplicates, Leftovers and the
Uninstaller — and a second press while the first is in flight is not a second
removal, because the files it would name are already gone: what a repeat can
only be is a refusal. That refusal has to live in the model and not only in a
dimmed control, because a control's disabled state lags the redraw that would
show it and never reaches a row's own context menu at all, which draws from
the same data with none of the button's `.disabled`.
`DiskViewModel.toggleBasket` declining while `busy` is the same guard read
from the basket's own door
(`Sources/Modules/Disk/UI/DiskResultView.swift:362`).

Left unguarded, a second send does not merely do nothing: the reply that
lands second overwrites the model's report of the reply that landed first, so
the person is told the removal that worked failed, over a list of files that
plainly did not move.

`Tests/HelmAppTests/OneRemovalAtATimeEverywhereTests.swift:33` walks every
file under `Sources/Modules/` and fails on any that sends a removal without
the guard; the files it finds today are the output of
`command grep -rln "guard !busy" Sources/Modules/`, since the count itself
does not belong in this sentence (CLAUDE.md:129). It scans by whether a file
**sends** a removal — matching `Command.trash` or `uvm.trashPaths(` in its
own source — rather than by whether a view model **names** it: an earlier
version matched `lastPathComponent.contains("ViewModel")` and missed two
doors that are not named `ViewModel` at all, `OrphansView.swift` and
`TrashedLeftoversView.swift`, both of which send a removal on their own path
around the guard the type of that name usually carries.

### Giving everything back

A reset is not a deletion first. Helm can change four things outside its own two
folders, each only if the person switches it on, and three of them are given back:

- the passwordless `pmset` rule Keep Awake's closed-lid option writes under
  `/etc/sudoers.d` — taken back by the module that put it there
  (`Sources/Modules/KeepAwake/Engine/KeepAwakeEngine.swift:172`), through an
  administrator dialog the person can decline, in which case the rule stays and
  Helm says so rather than reporting a reset that did not happen;
- the login items Leftovers switched off with `launchctl disable`
  (`Sources/Modules/Leftovers/Engine/SystemPorts.swift:135-146`) — switched back
  on from the module's own record of what it disabled;
- Helm's own registration in the login-item database
  (`Sources/HelmApp/LoginItem.swift:64`) — unregistered as a step of the plan,
  because the application registered it and no module owns it;
- ownership of `/opt/homebrew`, changed by the in-app Homebrew installer
  (`Sources/Modules/Homebrew/Engine/HomebrewEngine.swift:481`). **This one is not
  given back.** Helm does not record who owned the tree before, and handing it
  back to root would leave a `brew` that cannot install anything without `sudo`
  — the ownership is what Homebrew needs, and it is what Homebrew's own
  installer does on any Mac.

The launchd give-back has an edge that cannot be closed from here: a label the
person disabled themselves *after* Helm disabled it is indistinguishable from
Helm's own, so it is switched back on too. The alternative — reading the
system's own disabled list — would give back decisions that were never Helm's,
which is worse in the same direction.

Two keychain keys stay: `com.helm.app` / `settings-seal` and `com.helm.autopilot`
/ `rule-seal`. `KeychainSealKey` can read and create and not delete, and a
delete on an ad-hoc-signed bundle costs a modal dialog for each. By the time the
reset reaches them the preferences domain is gone, so what they sealed no longer
exists: what remains is 32 bytes the next launch reads as its own.

`ResetPlan.Step` (`Sources/HelmRuntime/ResetPlan.swift:27`) is
`handBackWhatIsOutsideHelm`, `giveBackTheLoginItem`, `trashHelmsOwnFolders`,
`forgetPreferences`, `relaunch`, and `ResetPlan.order` (`:59`) is that order as a
value rather than the shape of a function body, where what was missing from it
was invisible for exactly that reason. `Sources/HelmApp/ResetEverything.swift:33`
switches over the steps exhaustively, so a step added to the plan and left
uncarried is a build error. The engines are asked first, through
`ModuleEngine.willDisable`, while the settings an engine decides with are still
there; asking is not being given. `ResetPlan.roots`
(`Sources/HelmRuntime/ResetPlan.swift:67`) names the two folders: Helm's Application
Support directory (`Sources/HelmRuntime/HelmSupport.swift:20`) and
`~/Library/Logs/Helm`. They go to the Trash rather than through `unlink`.

## Diagnostics log

`~/Library/Logs/Helm/helm.log`, two megabytes and then one rollover
(`Sources/HelmRuntime/HelmLog.swift:190`), in a folder created 0700
(`Sources/HelmRuntime/PrivateFile.swift:204`). `LogPolicy`
(`Sources/HelmRuntime/HelmLog.swift:13`) answers whether it logs at all, and
`LogDestination` (`:43`) answers where it lives. `LogPolicy.isEnabled` (`:14`) keys off
the `-dev` substring in the version (`:16`), so every prerelease ships with the log on
and a beta build stays silent until its owner turns the switch on. That switch is in
the Log page (`Sources/HelmApp/LogView.swift:43`).

A failure that cannot be triaged is recorded rather than logged. `HelmLog.warn`
(`Sources/HelmRuntime/HelmLog.swift:388`) and `.error` (`:395`) capture `#fileID`,
`#line` and `#function` automatically; `info` (`:347`) leaves them out, because it
describes an event rather than a fault and a source location is noise on every line of
a healthy log. `HelmLog.failure` (`:403`) is the common shape.
`HelmFailure.describe` (`Sources/HelmRuntime/HelmFailure.swift:50`) unwraps an
`NSError` to domain, code, message, failure reason, failing path and the underlying
error, which is in the great majority of cases the actual answer; `osStatus` (`:93`)
adds the name macOS knows for a code and `posix` (`:106`) names an errno, because a
bare integer is a number to paste into a search engine rather than a fact.

`Redact` (`Sources/HelmRuntime/Redact.swift`) is what goes into the file in place of a
name: `path` (`:20`) rewrites the home prefix, and `vpn` (`:134`), `app` (`:138`) and
`pkg` (`:143`) give a short stable tag. The digest is FNV-1a rather than `Hasher`,
which is seeded per process — comparing a line from one session with a line from
another is exactly what triage does — and it is salted (`:109`, `:152`), because a
keyless hash of a name drawn from a small public list is an index into that list rather
than redaction. The salt is per install and lives beside the log in a `0600` file
(`:159`), which keeps the property the digest was chosen for while making a tag pasted
into a bug report meaningless on another machine. `HelmFailure.describe` strips the
home path from every string it emits, including messages, which carry no key for
`Redact.path` to find them by.

Two things follow the file rather than the process. The one-time purge records that it
has run in a file beside the log rather than in `UserDefaults`, which is namespaced per
process: any binary linking `HelmRuntime` ran the purge again against the one real log.
And a test runner writes into a folder of its own —
`LogDestination.directory(home:temporary:underTest:)`
(`Sources/HelmRuntime/HelmLog.swift:158`) moves the folder rather than the file, because
the rollover, the purge latch and the salt all belong beside whatever file is real. The
question "is this a test runner" is answered once, by `TestProcess.isRunning`
(`Sources/HelmRuntime/TestProcess.swift:21`), which reads
`NSClassFromString("XCTestCase") != nil` rather than an environment variable:
`XCTestConfigurationFilePath` is Xcode's and `swift test` leaves it unset. The scan
journal reads the same answer, since the two decide the same question.

### The activity registry

`Sources/HelmRuntime/HelmActivity.swift` is the registry of named phases — what is
running *now*. `HelmActivity.phase(_:_:)` exists in a synchronous and an `async`
overload (`:45` and `:59`); each opens an `os_signpost` interval on the same call and
closes both the interval and the registry entry from a `defer`, so a phase closes on
return, on throw and on cancellation. `begin`/`end` (`:70`, `:76`) is the pair for a
body the closure cannot take. The live set is bounded at `HelmActivity.liveLimit`,
declared 64 (`:35`), and `begin` drops a phase rather than growing past it (`:72`).
`HelmActivity.sweep(module:)` (`:84`) removes every phase whose label is the module id
or begins with it; it is called from `Sources/HelmApp/ModuleHost.swift:81` and `:135`,
so an interval nobody closed cannot go on naming a module that has been dropped.

The labels are not listed in prose. What exists is what
`command grep -rhoE 'HelmActivity\.(phase|begin)\("[^"]+"' Sources | sort -u` prints.
`HelmActivity.describe(_:now:excluding:)` (`:118`) is the phrase that goes after a
memory reading: oldest first, with nothing hidden for having run long — an interval
running for forty minutes is what the registry exists to show. `excluding` is the phase
asking, since a phase's own line already names it. An empty registry renders as
`no phases running`, which is what the registry knows; it is not a statement about the
app, since the SwiftUI render, a VPN refresh, the update check and the trash sweep all
run outside it.

### The memory trail

`HelmLog.memory(_:)` (`Sources/HelmRuntime/HelmLog.swift:359`) is the other instrument:
the process footprint under the `memory` category, as a delta against the last reading
for the same label, with `HelmActivity.describe` appended. The figure is
`phys_footprint` (`Sources/HelmRuntime/MemoryFootprint.swift:26`) — what Activity
Monitor calls Memory — rather than `resident_size`, which counts shared pages. The
accounting and the threshold sit in `FootprintTracker`
(`Sources/HelmRuntime/MemoryFootprint.swift:33`), whose `defaultThreshold` is
`8 * 1024 * 1024` (`:37`) and which measures from the last *reported* value (`:57`), so
a slow drift crosses eventually. `sample` and `launch` are the two labels that ask about
everything and are therefore not excluded from their own description
(`Sources/HelmRuntime/HelmLog.swift:365`). The second overload, `memory(_:grewBy:)`
(`:384`), reports a bounded scope from two readings taken around it and has no threshold
at all — its figures are single-digit megabytes and being small is the answer
(`Sources/HelmRuntime/ScopeCost.swift`).

`MemoryFootprint.current()` is the *process* cost. A **per-object** cost is read from
the allocator's own books — `malloc_zone_statistics`' `size_in_use`. Every walk with a
budget carries its ceiling as a file rather than as a paragraph, per entry or per item:
`Tests/Modules/Disk/EngineTests/ScanFootprintTests.swift:98`,
`Tests/Modules/Leftovers/EngineTests/LeftoversScanFootprintTests.swift:59`,
`Tests/Modules/Duplicates/EngineTests/WalkFootprintTests.swift:91` and
`Tests/HelmRuntimeTests/ReleaseDigestFootprintTests.swift:51`, with
`Tests/HelmRuntimeTests/MemoryTrailCoverageTests.swift` holding the list of phases
obliged to carry a reading at all.

### The log pane

`Sources/HelmApp/LogView.swift` is the same lines readable while they are being written,
on every build. It computes nothing: one `write`, one format, and the pane is a window
onto it. It is also where logging is switched on, where the file is revealed and where
it is cleared, so the place a person is sent to when they report a problem is the one
named after it.

`Sources/HelmRuntime/LogTail.swift` is the in-memory tail, bounded by `limit`, default
1000 (`:49`), trimmed from the front (`:58`). It is filled from the parts a file line is
spelled from rather than by parsing the line back apart.
`Sources/HelmRuntime/LogSeed.swift` is the one exception and says so in its own first
line: a seed has no parts to hold, so it parses — once, in a type whose name says so,
and as the exact inverse of the format rather than an approximate reader of it. It seeds
from this process's log files and their predecessor on disk
(`Sources/HelmRuntime/HelmLog.swift:194`, read at the first `recentEntries()`, `:283`),
so the pane is not limited to what this process happened to write. A line it cannot read
is kept whole, claims no level and no category, and takes the date of the line above it.

The pane follows the newest line by its identity rather than by the tail's count
(`Sources/HelmApp/LogView.swift:266`) — the count is the limit for ever once the tail is
full.

## Localization

`L()` (`Sources/HelmUI/L10n.swift:108`) takes the English string as the key and an
optional inline table; a second overload (`:118`) takes a language. The English text
stays at the call site, and the translations live in
`Sources/HelmUI/Resources/<language>.lproj/Localizable.strings`.
`ls -d Sources/HelmUI/Resources/*.lproj` lists the languages and
`command grep -c '^"' Sources/HelmUI/Resources/*.lproj/Localizable.strings` counts the
keys per file — the numbers agree, and
`Tests/HelmUITests/StringsCoverageTests.swift:12` is what fails when they diverge.
SwiftPM builds the resources into the `HelmUI` bundle (`.process("Resources")` in
`Package.swift`), and `Scripts/package-app.sh` copies every generated bundle, so nothing
in the script knows about this.

The `.lproj` directories are named by `AppLanguage`'s raw values
(`Sources/HelmUI/L10n.swift:6`) rather than by the `zh-Hans` and `pt-BR` spellings,
because Helm resolves the language itself. `Localized`
(`Sources/HelmUI/L10n.swift:135`) loads the per-language sub-bundle explicitly and caches
one bundle per language. `NSLocalizedString` appears nowhere in the sources except in the
paragraph explaining its absence (`Sources/HelmUI/L10n.swift:131`): it would hand the
language decision to the system and break the `language:` overload every localization
test asks through. An inline table is kept where a Swift-interpolated string is the key,
because interpolation runs before the lookup, and
`command grep -rl 'table:' Sources` names those sites.

Each of these guards faces a direction the others were blind to:

- `Tests/HelmUITests/StringsCoverageTests.swift:12` — every English key present in all
  eight files, nothing empty, one lookup end to end through the shipped bundle.
- `Tests/HelmUITests/NoOrphanTranslationsTests.swift:25` — a translation nothing asks
  for. Such a key is a trap rather than weight: the most reusable words in an interface
  would silently inherit seven translations written about something else, and English
  cannot show it, since `L()` falls back to its own key. One sweep deleted sixteen of
  them, `FOLDERS` among the words that would otherwise have inherited another control's
  translations.
- `Tests/HelmUITests/StringsLiveInLprojTests.swift:26` — the direction where a literal
  in the source reached no table at all: it reads perfectly in English and ships English
  to the other seven with nothing failing. It skips interpolated literals, which keep
  their tables at the call site.
- `Tests/HelmUITests/OneEntryPerKeyTests.swift:23` and
  `Tests/HelmUITests/NoKeyIsWrittenTwiceTests.swift:21` — a key written twice, faced from
  two sides. `NSDictionary(contentsOfFile:)` keeps the last entry and says nothing about
  the first, `plutil -lint` calls such a file valid because it is, and a coverage check
  reads the dictionary the loader already collapsed; the first of the two reads the file
  as text and cross-checks what it parsed against what the loader returned, and the
  second counts each key's occurrences straight off the lines, proven on a fixture of
  its own rather than on the tree.

A malformed `.strings` file is silent: the loader returns nil and every
string falls back to English with no error anywhere.

One English key means one thing. Where a second meaning needs the same word, the English
is written differently, because several languages had independently drawn distinctions
the English had lost and the translators were right to diverge. A sentence that names a
control is built from the control's own word rather than spelling it a second time, so a
rename carries the sentence with it. What interpolation carries is a name rather than a
verb: a verb inflected against eight grammars would be right in roughly one of them, so
each variant is a full key with its own eight translations.

Everything the language shapes goes through `Sources/HelmUI` rather than through a
`Foundation` formatter built with no locale, which answers in the system's language:
`HelmBytes.string` (`Sources/HelmRuntime/HelmBytes.swift:30`) for a size,
`HelmBytes.decimal` (`:59`) for a mantissa with grouping off, since a separator there is
a second decimal mark, `HelmBytes.grouped` (`:74`) for a count with grouping on, `Quoted`
(`Sources/HelmUI/L10n.swift:516`) for a language's own quotation marks, and `HelmDates`
(`Sources/HelmUI/L10n.swift:202`) for relative times. A formatter is cached per language
and per style rather than held in a `static let`, because the app's language changes
while it runs, and because a cache keyed by language alone answers whichever style asked
first. `HelmBytes`'s cache is keyed by grouping as well, or a size and a count share a
formatter.

Terminology is looked up rather than remembered: the units, the permission panes and the
module names come from the tables macOS itself ships. Punctuation is terminology too, and
so is a screen reader's vocabulary
(`Sources/HelmUI/DesignSystem/A11yStrings.swift:16`). French is the one of the eight that
spaces its punctuation, with an unbreakable space before a colon and a question mark and
inside a pair of guillemets, where an ordinary space is a line-breaking one.
`Tests/HelmUITests/PunctuationIsTerminologyTests.swift:21` is the guard, and it seeds its
union of marks from `Quoted`'s own answers (`:40`) rather than from a list.

A language code is not in every case the directory macOS files it under.
`SystemFolderNames` (`Sources/HelmRuntime/SystemFolderNames.swift:73`) carries a
one-entry table for exactly that: macOS ships `zh_CN`, `zh_TW` and `zh_HK` and no plain
`zh`, and loading a table that is not there is an empty dictionary rather than an error,
so the failure was silent.

Fixed widths are measured rather than chosen. `HelmPickerWidth.fitting`
(`Sources/HelmUI/DesignSystem/PickerWidth.swift:36`) sizes a pop-up from its own titles,
and `segmented` (`:83`) models the different arithmetic of a segmented control, whose
segments AppKit draws equal-width and rounds up per segment; a number chosen for one
language cannot survive eight.
`Tests/HelmAppTests/AnImposedPickerWidthFitsItsLabelsTests.swift:57` measures every
imposed width in the tree against a hosted control's own answer.

### An age has two spellings

`HelmDates.AgeStyle` (`Sources/HelmUI/L10n.swift:220`) offers `.full` and `.short`, and a
third is deliberately absent: `RelativeDateTimeFormatter`'s abbreviated style prints a
signed delta in several languages, which reads as a negative number rather than as a
time. A comment warning against it would be a comment; an enum that cannot spell it is a
build error.

`HelmDates.age` (`Sources/HelmUI/L10n.swift:267`) returns an optional and refuses below
`youngestAgeWrittenAsPast`, one second (`:289`). Two ways a stamp arrives in the future
voice, and only the first is expected: a clock genuinely ahead, and a stamp behind the
clock by less than a second — the formatter rounds to the nearest second and renders a
rounded zero in the future voice, and only at a full second says "ago". A key just
written and a scan row redrawn the moment its scan returns both sit inside that first
second. The answer is the absence rather than a clamp: "just now" is also what a true
fresh reading says, so an absence is the only answer a reader can tell apart from a true
one.

## State and lifetime

### State a person asked for outlives the process

A session the person asked for lives in the store rather than in engine fields, because
anything that ends the process would otherwise cancel it — routinely Helm's own updater,
which terminates the app and has a detached script relaunch it. The IOKit assertion is
per-process too, so the Mac was free to sleep with the countdown gone from the menu bar
and nothing saying the session had been cut short. The module already held the pattern
one field away: `clamshellGuard`
(`Sources/Modules/KeepAwake/Engine/KeepAwakeSettings.swift:34`) is written when sleep is
disabled and undone in `activate()`, because that change outlives the process — it
protected the system from being left wrong rather than the person's own request.

Three things shape how such a state is written:

- `deactivate()` is the one place it is left unwritten.
  `Sources/HelmApp/AppDelegate.swift:265` calls it on every live engine at termination,
  so recording "off" there would erase the session on every quit, including the
  updater's — the relaunch the whole arrangement exists for. The state is written where
  the person's intent changes: start, stop, expiry. The cost of that choice, stated
  rather than hidden: `deactivate()` cannot tell quitting from the module being switched
  off, so switching Keep Awake off and on again resumes an unexpired session. Of the two
  possible mistakes, forgetting what was asked for is the one that was reported.
- A restored deadline is a deadline rather than a duration: re-scheduling for the
  original minutes gives a session that ends later on every restart, so the restore
  passes what is left.
- A `Date` is a `Double` of seconds since the 2001 reference date, so a round trip
  through `timeIntervalSince1970` adds and subtracts a large constant and loses the
  low-order bits. `Sources/Modules/KeepAwake/Engine/KeepAwakeEngine.swift:796` stores
  `timeIntervalSinceReferenceDate`. The difference was a fraction of a second, which is
  enough for a re-scheduled expiry to miss its interval and enough for a test to pass
  under a filter and fail in the full suite.

`SessionRestore`
(`Sources/Modules/KeepAwake/Engine/Logic/SessionRestore.swift:21`, `decide` at `:37`) is
the pure unit deciding what a session found in the store is worth, and every branch is a
judgement rather than arithmetic: a deadline stored beside a session that is off is stale
bookkeeping; "until I say stop" survives a restart, because a restart is not the person
saying stop; a deadline that passed while the app was gone is over; and a session cannot
come back longer than it ever was, which is what bounds it when the system clock moves
backwards. What it cannot repair, and does not pretend to: the assertion died with the
process, so the Mac genuinely could have slept in the gap.

### State that outlives a page and ends with its module

A module's UI state outlives its page and not its module. Settings rebuilds a page on
every sidebar visit, so the view models are cached; the cache is dropped by module id
through `ModuleUICache.dropWhenDisabled`
(`Sources/HelmUI/DesignSystem/ModuleUICache.swift:23`), written once there rather than in
each view model, and driven by `.helmModuleDisabled`, posted from
`Sources/HelmApp/ModuleHost.swift:138`. The on-disk scan cache is untouched by this: the
copy in memory goes, the answer stays.

Dropping the cache is only one of two owners. A subscriber task started as
`Task { [weak self] in await self?.observeEvents() }` resolves its weak capture once, and
the method then holds `self` for as long as it runs — which, over a transport whose
stream does not finish, is the life of the app. The tasks are therefore held and
cancelled from the class's own teardown rather than from `deinit`.
`LocalTransport.subscriberCount` (`Sources/HelmContract/LocalTransport.swift:71`) is what
makes the guard a count that stays put rather than a memory figure:
`Tests/HelmContractTests/SubscriberPruningTests.swift` and
`Tests/HelmAppTests/ASwitchedOffModuleLetsItsSubscriberGoTests.swift`.

A mounted SwiftUI tree is billed whether or not anybody can see it.
`Sources/HelmUI/DesignSystem/OffScreenIdle.swift` unmounts a subtree while its window is
out of sight and rebuilds it from the view model's current state; the model keeps its
subscription throughout, so nothing is missed. It rides `helmSettingsColumn()`
(`Sources/HelmUI/DesignSystem/HelmSurfaces.swift:259`), so every module page carries it.
A harness that leaves its window unordered declares itself with `helmMeasuringBench()`
(`Sources/HelmUI/DesignSystem/OffScreenIdle.swift:86`), setting `helmTreatsWindowAsSeen`
(`:76`) — a declaration the app itself does not make. The panel window is deliberately
ungated.

### An observer outlives the thing it points at

An observer, a timer or a system port an engine or a view model starts is
taken down twice: once in `deactivate()` and again in `deinit`. Both are
needed because `deactivate()` is not guaranteed on every route out, and a
`deinit` alone is not enough either where the thing observed keeps its own
reference — the run loop holds a repeating `Timer` for as long as it is
armed, so the timer outlives whatever created it until something calls
`invalidate()`, `deinit` included:

```
guard let self else { return timer.invalidate() }
```

is the timer's own callback finding its owner already gone, inside
`RepeatingTick.set(active:)` (`Sources/HelmRuntime/RepeatingTick.swift:30`).
`VPNEngine` stops its network
observer from both `deactivate()` (`Sources/Modules/VPN/Engine/VPNEngine.swift:343`)
and `deinit` (`:350`), because a host that calls `deactivate()` and then drops
the engine leaves a callback still holding it pointing at freed memory the
moment the port fires again; `NetworkWatchPort.stopObserving`
(`Sources/Modules/VPN/Engine/Ports.swift:105`) states the same rule from the
port's own side, since a port's caller is never guaranteed to be the only
thing that can reach it before it is gone.
`Tests/Modules/VPN/EngineTests/VPNNetworkWatchTests.swift:50` guards the
`deactivate()` half; there is no test for the `deinit` half beyond the fact
that both engines write it, because a missing `deinit` does not fail loudly —
it fails as the crash in `Sources/HelmRuntime/RunningApps.swift`'s own doc
comment did, on whichever call happens to land on the freed object next.

`DiskViewModel` holds its mount-watch observer the same way, so a view model
dropped when the module is switched off is not woken by the next disk
somebody plugs in
(`Sources/Modules/Disk/UI/DiskViewModel.swift:65`).

### Sealed settings

`Sources/HelmRuntime/SettingGuard.swift` is the door on a stored value: `seal` (`:30`),
`verdict` (`:42`), and `establishKey()` (`:70`), which spends first use so the adoption
`.adopt` leaves open is Helm's own rather than whatever a plist happened to hold.
`warmKey()` (`:82`) moves the keychain round trip off the thread that draws.
`Sources/HelmRuntime/SealKeyCache.swift` caches the key once per process and no verdict
at all: the key is a secret created once, so remembering it cannot go stale, while
whether a stored value is Helm's own is a live fact about a plist anything can rewrite. A
refusal is not cached either. `Sources/HelmRuntime/SettingSeal.swift` and
`Sources/HelmRuntime/KeychainSealKey.swift` are the rest of the mechanism, which is
Autopilot's moved rather than a second one — Autopilot keeps its own keychain item
because that item already exists on every Mac that has run the module. A broken seal
refuses in each side's own safe direction: the folder is left unwalked, and the disabled
list becomes every scannable module.

What is *not* sealed is as much a part of the shape.
`KeepAwakeSettings.clamshellEnabled`
(`Sources/Modules/KeepAwake/Engine/KeepAwakeSettings.swift:164`) steers privileged work
and reads straight from the store, because this bundle is ad-hoc signed and every build
is a new code identity to the keychain — a seal on a value read from `recompute` is a
modal dialog in front of the launch. The mitigation that ships instead is the gesture
requirement above: a forged value can engage a grant the person already gave, and cannot
summon a password dialog.

### A number that came from a file

`~/Library/Preferences` is not a trusted input, and Swift traps on overflow in release as
well as debug. The single ceiling for the durations is `TimerPolicy.longestSessionMinutes`
(`Sources/Modules/KeepAwake/Engine/Logic/TimerPolicy.swift:30`), read by every reader of
the number — the settings
(`Sources/Modules/KeepAwake/Engine/KeepAwakeSettings.swift:132`, `:191`), the extend
button (`Sources/Modules/KeepAwake/Engine/Logic/TimerPolicy.swift:50`) and the drawn
label — so the multiply is unreachable by construction rather than guarded at each call
site. `SessionRestore.decide` refuses a restored deadline rather than bringing it down to
the ceiling, and checks the two dates are ordered before either bound runs.
`UpdateCheck.lastChecked(stored:now:)` (`Sources/HelmRuntime/UpdateCheck.swift:74`) reads
a stamp as a moment rather than doing arithmetic on the raw `Int`.

`Sources/HelmRuntime/Clamped.swift` is the shared clamp, in a fixed
`min(max(x, lo), hi)` order (`:20`) that propagates NaN rather than absorbing it. Which
answer a NaN gets is stated at the call site through `clamped(to:whenNotANumber:)`
(`:54`); `clampedIfFinite(to:)` (`:37`) is the caller who wants `nil` instead and is not
a substitute, since it refuses infinity too.

## Release

The number is `MAJOR.MINOR.PATCH`. It lives in one place,
`Resources/HelmApp/Info.plist` under `CFBundleShortVersionString`, and
`/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/HelmApp/Info.plist`
is what the tree currently says it is. `CFBundleVersion` in that file is a placeholder:
`Scripts/package-app.sh:222` computes the build number as `git rev-list --count HEAD`
(`--no-replace-objects` and `-c core.commitGraph=false` alongside it, so neither a
replacement ref nor a forged or stale commit-graph cache can shorten the history it
walks), after refusing a checkout whose history cannot be trusted — none at all; a
shallow clone, which exits 0 having counted only the commits it fetched; a tree that is
not git's own top level, one whose own `.git` an ancestor's `core.worktree` can stand in
for, or one steered by a `GIT_DIR`/`GIT_WORK_TREE` from the environment; or a history a
graft or a replacement ref has given a shorter parent chain — rather than substituting a
number. The gate announces what it computed (`==> Build number: N`) right after, before
the compile it guards, and `Scripts/package-app.sh:298` writes the same number into the
plist *of the assembled bundle*, so the tree's copy and a shipped bundle's copy disagree
by design.

A release tag is `vMAJOR.MINOR.PATCH`; a prerelease tag is `vMAJOR.MINOR.PATCH-dev.N`.
`git tag --list 'v*' --sort=v:refname` is the list and `git tag --list 'v*' | wc -l` the
count. `-dev` is the only suffix the scheme has: `UpdateVersion.prereleaseOrdinal`
(`Sources/HelmRuntime/UpdateVersion.swift:16`) reads the trailing number of the suffix
and nothing else, so `-dev.2` and `-beta.2` are indistinguishable to it.

MAJOR marks a milestone — a new architecture, a breaking redesign. MINOR is a new
capability or a reworking of an existing one. PATCH is a fix, and it is also the step of
a **numbered line**: one MINOR's worth of work cut into releases that ship one at a time.
A MINOR bump resets PATCH to zero, a MAJOR bump resets both. What makes a line a line
rather than a licence to call any feature a patch is that the whole series — which
releases, in what order, where it ends — is written down before the first of them ships.
`CHANGELOG.md` names the line in one italic line under the first section heading it
ships; that italic line is the only prose a section there gets, and
`command grep -c '^\*[^*]' CHANGELOG.md` counts them against
`command grep -c '^## ' CHANGELOG.md` version headings.

While the number is `0.x`, MINOR is the lane the work runs in. `1.0.0` is reserved for a
Developer ID and notarization — the build opening without `xattr` — plus a settled module
set: "1.0" is the claim that the program is ready for other people.

Two releases carrying one version are invisible to the updater. `UpdateVersion.isNewer`
(`Sources/HelmRuntime/UpdateVersion.swift:24`) requires a strictly greater version, so a
release without a bump reaches nobody, and nothing published can pull a user back to an
earlier build — there is no rollback, and that is the shape of the comparison rather than
a missing feature. A prerelease sorts below its own release and above every earlier
version: `UpdateVersion.parse` (`Sources/HelmRuntime/UpdateVersion.swift:8`) drops
everything from the `-` on and the ordinal supplies the tiebreak.

There are two channels, and `UpdateCheck.Channel`
(`Sources/HelmRuntime/UpdateCheck.swift:36`) is where the difference lives: `beta` reads
`releases/latest`, which GitHub answers without prereleases at all; `dev` reads the
releases list and takes the newest entry, prereleases included. `Channel.stored` folds an
unreadable setting to `beta` rather than to the faster one. The name is `beta` rather
than `stable` because the program has not reached 1.0 and a channel called stable would
promise what no release has earned. In the app the switch is About → Update channel, and
switching re-checks at once.

Everything reaches the dev channel first, as a `vX.Y.Z-dev.N` prerelease, and the same
code goes out as the beta `vX.Y.Z` release once the count of known problems is zero. A
`-dev.N` prerelease leaves the beta numbering alone: the eventual `vX.Y.Z` supersedes
every `-dev.N` before it. Two consequences of that arrangement look like faults and are
not. A release published with `--prerelease` is invisible to the Beta channel, because
`releases/latest` skips every prerelease — so the flag, or its absence, is what decides
reachability rather than presentation. And in the window between a beta shipping and the
next `-dev` build being cut, the newest entry in the whole releases list *is* the beta, so
the Dev channel answers "up to date" and is right.

One release is one `CHANGELOG.md` section, one git tag, and both a `.dmg` and a `.zip`
attached with a `sha256` line for each in the notes. `Scripts/make-zip.sh:36` and
`Scripts/make-dmg.sh:81` each print that line. The zip is what the in-app updater
downloads for a silent install; the dmg is the manual drag-install path, and a release
with no zip asset falls back to opening the release page.

`Scripts/package-app.sh:258` builds `swift build -c release --product HelmApp`, assembles
and signs in `$TMPDIR/helm-package`, and leaves a copy in `build/` for inspection.
`Scripts/make-dmg.sh:12` and `Scripts/make-zip.sh:14` read the **signed** bundle from
`$TMPDIR/helm-package` and re-run `codesign --verify --deep --strict`
(`Scripts/make-dmg.sh:14`, `Scripts/make-zip.sh:16`) before packaging, exiting non-zero
rather than shipping a bundle whose seal something broke. `Scripts/package-dev.sh`
builds through `Scripts/package-app.sh`, rewrites `CFBundleIdentifier` to
`com.helm.app.dev` (`Scripts/package-dev.sh:38`) so the two hold separate
preferences domains, then replaces the installed **Helm Dev** and reopens it: it
kills any running copy (`:51`), removes `/Applications/Helm Dev.app` (`:53`),
strips quarantine (`:55`) and opens the fresh one (`:56`). The release scripts are
`Scripts/package-app.sh`, `Scripts/make-dmg.sh`, `Scripts/make-zip.sh` and
`Scripts/package-dev.sh`; `Scripts/flags` and `Scripts/design` produce nothing
that ships on their own.

### The updater

`Sources/HelmApp/UpdateService.swift` carries the networking and the published state;
`UpdateCheck.evaluate` (`Sources/HelmRuntime/UpdateCheck.swift:90`) is pure and tested;
`Installer.installZip` (`Sources/HelmApp/Installer.swift:27`) does the install. The app
downloads the release zip itself, so the file carries no quarantine, unpacks it with
`/usr/bin/ditto -x -k` (`Sources/HelmApp/Installer.swift:34`), and — once the
downloaded bundle passes the check that it names the same program already
installed here, refusing otherwise — a detached script waits for the process to
exit, swaps the running bundle, relaunches and removes every temp artifact
including itself. `UpdateSwap`
(`Sources/HelmApp/UpdateSwap.swift:31`) moves the installed bundle aside, copies, reads
the status and either removes the aside or puts it back. `UpdateHandoff`
(`Sources/HelmApp/UpdateSwap.swift:100`) is the note a failure is reported by at the next
launch. Copying first is not by itself the fix: a `ditto` into a live bundle merges into
it, which is how a half-new, half-old app is made.

Nothing installs without a published digest. The updater strips quarantine on purpose and
the app is ad-hoc signed, so `codesign --verify` proves nothing — any ad-hoc signature
passes, and TLS protects the transport rather than the contents. `ReleaseDigest.line`
(`Sources/HelmRuntime/ReleaseDigest.swift:22`) is the `sha256 <asset> <hex>` line the
release notes carry, `parse` (`:29`) finds it for one asset name and `matches` (`:80`)
checks the downloaded file: no digest for this exact asset name opens the release page
with the reason stated, and a digest that disagrees refuses the install outright.
`installZip(at:expectedVersion:)` (`Sources/HelmApp/Installer.swift:44`) then re-reads the
unpacked bundle's own version, so a mislabelled asset cannot be swapped in either.

### What shipped

`CHANGELOG.md` at the root of the tree is the canonical English record and is not
bundled — nothing in `Scripts/package-app.sh` or `Package.swift` names it.
`Sources/HelmApp/ChangelogData.swift` is the same list inside the app: structured entries
badged `new`, `upd` and `fix` (`:28`), each text passing through `L()` and computed rather
than stored so the current language resolves on every read (`:71`). A version heading in
the file is `## X.Y.Z — YYYY-MM-DD`, one line per change with `**NEW**` / `**UPD**` /
`**FIX**` first, newest version first. `command grep -c '^### ' CHANGELOG.md` prints zero:
the file carries no sub-headings at all.

### The disk image window

`Scripts/make-dmg.sh` builds a laid-out window rather than a bare folder. The background
is generated at build time by `Scripts/design/make-dmg-background.swift` and the layout
lives in `Scripts/dmg-settings.py`; the two hold the same slot coordinates seen from
opposite sides, and `Scripts/dmg-settings.py:9` says so in the file itself. Three drawings
exist, chosen by `HELM_DMG_STYLE` with a default at `Scripts/make-dmg.sh:38`: `field`,
squared paper, because measuring is what the app does; `bezel`, the frame the About page
puts the mark in, with ticks closed all the way round and a single chevron pointing at
Applications; and `sweep`, one wedge of that ring opened out towards Applications.

Two facts about the `bezel` drawing are load-bearing. The ring stands far enough off the
icon to clear the name Finder writes under it — the radius is `bezelRadius` at
`Scripts/design/make-dmg-background.swift:43`, and a ring close enough to frame the icon
runs through the word instead. And the chevron is centred in the *corridor* rather than
between the two icons: the corridor runs from the ring's outer edge to the folder's left
edge (`Scripts/design/make-dmg-background.swift:136`), which is the same point as the
midpoint only while the ring is small; placed at the midpoint the chevron reads as
attached to the app.

A dev image marks itself. `Scripts/make-dmg.sh:43` matches `*-dev.*` in the version string
and passes `--dev` to the drawing, so the mark arrives from the version rather than from
anyone remembering a flag — a screenshot of a dev window reaches an issue eventually, and
one without the mark reads as a release.

The window is not asked of Finder. On macOS 26 Finder accepts icon-view options over
AppleScript, reports them back correctly when queried, and draws its default window anyway
— 48 pt icons in a grid, no background — which was seen from a hand-written `osascript`
block and from Homebrew's `create-dmg` alike, so it is the OS rather than any one script.
Only the window's *bounds* still take. `dmgbuild` writes the `.DS_Store` directly instead;
it lives in a virtual environment under `build/dmg-tools` which
`Scripts/make-dmg.sh:65-69` creates on first run, out of the system Python that
Homebrew marks externally managed.
`build/` is git-ignored, so a fresh clone pays for that environment once.
`Scripts/make-dmg.sh:65` asks the tool to **run** rather than to exist, because a venv
records its interpreter's absolute path and moving the repository leaves an executable
that cannot start. `hdiutil` makes and mounts the image around all of that.

Two numbers there announce nothing when wrong. `window_rect`
(`Scripts/dmg-settings.py:31`) is the *window's*, so it is the background's height plus the
title bar, and a window asked for the background's height alone simply does not show the
bottom of the artwork. And `text_size` (`Scripts/dmg-settings.py:42`) has a floor: Finder
writes item names in icon view with no way to turn them off, the smallest value that works
is what that line holds, and a smaller one is written happily by `dmgbuild` and then
rejected wholesale by Finder — no background, no positions, no complaint.

## Design system

`ls Sources/HelmUI/DesignSystem/` is the design system, and
`ls Sources/HelmUI/DesignSystem/ | wc -l` its size. `Package.swift` puts it in `HelmUI`,
which every module's UI target depends on and no engine does.

**Surfaces.** `Sources/HelmUI/DesignSystem/HelmSurfaces.swift` holds `HelmSurface` — a
small set of fills over `Color.primary`, no border among them — `HelmLayout`, `HelmText`,
`HelmSignal`, `HelmIconPlate` and `HelmMetricStrip`. `helmCard()`
(`Sources/HelmUI/DesignSystem/HelmSurfaces.swift:88`) is the one card treatment: a fill,
continuous corners at `HelmRadius.card`, and no border. Half of Helm's pages are macOS
grouped `Form` sections, which the system draws as a plain fill and which cannot be
restyled, so an outlined card of our own reads as a different kind of box on the next page
over. The fill is measured against a real `Form` section on the same background rather
than chosen. A surface that floats over content takes `.glassEffect` rather than an edge —
`Sources/HelmApp/HelmPanel.swift:922` and `Sources/Modules/Disk/UI/RingView.swift:239` are
the two sites — because glass carries its own edge and its own shadow, which is the whole
reason a floating thing wanted one, and a hairline drawn on top is a second silhouette
disagreeing with the first. A token called `HelmSurface.floatingEdge` was named in the
prose for a while and existed nowhere else.

A grouped `Form` insets a section *header* further than the section itself, and a section
header is the one part of such a form drawn on the bare pane that still scrolls — which is
why a hero or a block of cards lives in one. The difference is
`HelmLayout.groupedHeaderOutset`
(`Sources/HelmUI/DesignSystem/HelmSurfaces.swift:292`), negated onto the block, and it is
right for a grid the page draws itself and wrong for a filled field, which is a row that
has not been written yet.

**Ladders.** `Sources/HelmUI/DesignSystem/HelmLadders.swift` holds `HelmSpace` and
`HelmRadius`, and

```bash
command grep -cE '^\s+public static let' Sources/HelmUI/DesignSystem/HelmLadders.swift
```

counts the steps. The steps sit close together where they are small and widen above, so
that a value chosen by eye has one obvious neighbour to round to, and a number off the
ladder is a number somebody has to argue for.
`Tests/HelmUITests/LaddersAreTheStepsTheyClaimTests.swift` holds both halves of that shape,
and `Tests/HelmUITests/SpaceLadderRatchetTests.swift` counts what the tree still spells by
hand and only ever goes down — landing a ladder is not adopting it.

**Type.** `HelmText` carries four named sizes for the settings window — `rowTitle`,
`rowDetail`, `sectionHeading`, `groupLabel` — because a census found six across three
weights, each chosen at its own call site. They are what macOS uses for the same jobs, so a
Helm page and a System Settings pane read at one rhythm, and a size outside these is a
decision somebody argues for rather than types. They are named rather than numbered: a
fixed `.system(size:)` gives a Mac whose owner raised the interface text size a Helm window
that did not follow. `.headline` is not the heading — on macOS it is bold rather than
semibold, so mapping `sectionHeading` onto it would weight every heading a step heavier
with the size unchanged, which no layout test can see. `HelmText.rowDetailNSFont`
(`Sources/HelmUI/DesignSystem/HelmSurfaces.swift:476`) is the same style as AppKit sees it,
for the two places that measure text rather than draw it. `HelmText.figureFont` is the one
face for a figure — a byte size, a count, a version — because a monospaced face and a
tabular proportional one at nominally similar sizes render the same number at visibly
different widths, and no choice of column width reconciles them. SwiftUI draws its own
text throughout; an `NSTextField` appears nowhere.

**Ink.** Ink that means something comes from `HelmSignal` rather than the system palette,
and `Tests/HelmUITests/SignalInkTests.swift` scans `Sources/HelmUI` and `Sources/HelmApp`
for a raw `.orange` / `.green` / `.red` handed to something that paints with it. A *tint*
is not ink and is deliberately uncaught: `Sources/HelmUI/DesignSystem/HelmBadge.swift`
takes one and draws it behind `Color.primary` text, which is why the pill exists. A tinted
figure is darkened in the light appearance by a fraction that is measured against a
contrast floor rather than chosen, and the blend is resolved *inside* the light appearance
— `NSColor(Color)` returns a dynamic colour, so a blend one line outside the block resolves
again against whatever appearance is current.

**Motion.** `Sources/HelmUI/DesignSystem/HelmMotion.swift` holds the tokens, and they are
computed properties rather than constants:

```bash
command grep -nE 'public static (var|func) ' Sources/HelmUI/DesignSystem/HelmMotion.swift
command grep -c 'public static let'          Sources/HelmUI/DesignSystem/HelmMotion.swift
```

is the list, and the second line prints zero. Springs rather than ease curves, because an eased move reads as "smoothed" and a
spring reads as physical; a spring also cannot be handed to a `CAMediaTimingFunction`, and
the eased tokens are named exceptions each carrying its reason. `disclosure` is for
anything whose height is measured and clipped, and it has zero bounce, because an
overshooting height clips its own content for a frame. `interface` is for reordering,
filters, selection and tabs. `emphasis` is for shape morphs. `panelEntrance` is a fade and
nothing else — macOS menu-bar extras neither grow nor scale nor slide — and it is eased
because a spring that short is a spring nobody can see. `reorder` is the one intentional
overshoot in the app: a card getting out of the way of a hand is a physical thing being
pushed. `slotFade` and `wellFade` are what a carried tile leaves behind, eased and slower
than the hand because the overlay covers the slot for the first part of the gesture.
`ringMorph(levels:)` and `spinDown` belong to the disk ring and to a wheel coming to rest.
There is no token for turning forever, and that is the finding: a `repeatForever` linear
rotation leaves the model at its end value while the dial is somewhere inside the turn, so
a stop by retargeting runs backwards; the About bezel drives its angle from
`TimelineView(.animation(paused:))` and coasts forward from the angle actually reached, and
the refresh glyphs turn on `helmSteadySpin`, a symbol effect gated on `HelmMotion.spins`.

Every token collapses to a near-instant cut when `accessibilityDisplayShouldReduceMotion`
is on — `HelmMotion.reduceMotion`
(`Sources/HelmUI/DesignSystem/HelmMotion.swift:27`) is read fresh on each access, since
stored in a `let` it would freeze at launch — because SwiftUI does not honour that setting
for us. A curve written inline is therefore not a token somebody forgot to use; it is an
animation that plays for a person who asked the operating system for none.
`Tests/HelmUITests/MotionTokensAreTheOnlyCurvesTests.swift` holds all three halves of that:
no curve constructor outside the token file, every `Animation`-returning token consulting
the flag, and the flag still being computed.

Three laws sit under the tokens. Identity decides whether anything can animate: SwiftUI
interpolates between two states of *one* view and not between two views, so a `ForEach`
keyed on an index, an `.id()` that changes with the thing being animated, or an `if/else`
inside a `ViewModifier` each ends the question before any transaction reaches it.
`.animation(_:value:)` carries neither a transition nor a layout change: a value the layout
is built from has to be written inside `withAnimation` **where it lands** rather than where
the change was triggered, because `onGeometryChange` hands its value over outside the
running transaction — and the first measurement is not a change, so animating it plays the
view collapsing from whatever the unmeasured layout happened to be. That idiom is one
modifier, `helmMeasuredHeight(_:animation:)`
(`Sources/HelmUI/DesignSystem/HelmAccordion.swift`), taking a `Binding<CGFloat?>` where
`nil` means "nothing has measured this yet", because a real height is nonzero but a real
bar can be; `helmAccordion(open:height:animation:)` builds on it with a frame gated on
`open`, `.clipped()`, and hit-testing and accessibility gates that travel with the clip
rather than being parameters a caller can forget. And what cannot be reached cannot be
fixed: AppKit's drag draws its own translucent snapshot, a system focus ring is drawn round
the frame rather than the shape, and `.borderedProminent` renders grey without a key
window.

Three consequences of that, all about what draws where. A reveal grows rather than fades:
animating `.opacity` puts the subtree in an offscreen layer where hierarchical colours
resolve differently, and dropping the layer at the end makes them jump —
`.compositingGroup()` stops the jump and costs more than it fixes, since inside a permanent
layer the system's own materials stop blending with the card behind them. Inside such a
block a literal `Color.primary.opacity(…)` tracks light and dark by itself where
`.secondary` and `.tertiary` resolve against the rendering context and blink when the layer
goes away. And a reveal by `if` collapses the card's background instantly while the
disappearing rows keep drawing over what sits below.

**The language.** Every screen speaks one visual language derived from the app's subject.
`Sources/HelmUI/DesignSystem/HelmPageHeader.swift` is icon plate, title, one line of what
the screen is for, and the screen's primary control at the far end. `HelmIconPlate` is the
symbol on its category tint, lit from behind, and stands alone in empty states.
`HelmMetricStrip` is an instrument readout — monospaced figures over small-caps labels,
split by hairlines — and it belongs to form screens, where the dials read as state; list
screens leave it aside deliberately, their chrome being one toolbar row with the counts as
a quiet status line in the bottom bar, which costs no vertical space. A metric strip lives
inside the form as its first `Section` rather than pinned above it with `safeAreaInset`, so
it inherits the system's width and container in both appearances instead of overhanging the
rows it summarizes. `Sources/HelmUI/DesignSystem/HelmAppMark.swift` draws the mark from
`Resources/Icon/Helm.icon/Assets/helm-ring.svg` — the artwork the app icon is built from,
copied in by `Scripts/package-app.sh:269` — rather than reading the icon back, because macOS
26 resolves `.icon` variants at the system level and the light variant's white slab reads
as a hole inside Helm's surfaces. `Sources/HelmUI/DesignSystem/HelmBadge.swift` is the one
pill, its tint colouring the fill and nothing else, because contrast is not something a
caller should be able to get wrong. The About page's bezel rotates only while an update
check is in flight: motion means work rather than decoration. The menu-bar panel stands
outside this language — it is a transient surface with its own layout rules.

The settings row answers two questions in one row: what is happening now, and what is
configured. `Sources/HelmUI/DesignSystem/HelmSettingRow.swift` is mark, title, note,
control, and the mark reports *the world* rather than the switch beside it — a rule that is
off gets `HelmRowMark.space`, not a grey dot, because a dot for "off" is the row saying one
thing twice in two alphabets. `.space` holds the mark column so a card of mixed rows keeps
one left edge, and the question `of(enabled:satisfied:inCardWithMarks:)` asks is whether a
mark *can* appear in this card rather than whether one is there now, so the indent arrives
when somebody flips a switch rather than when a condition comes true. Title and note
combine into one VoiceOver stop; the control stays its own, because that is the part a
person navigates to. Every control carries a name and a glyph is not one — a `Button` whose
whole face is an `Image(systemName:)` reads aloud as "button" — and an empty page is drawn
by `HelmEmptyState` or `HelmBusyState` inside `HelmCenteredContent` rather than by a
hand-rolled `VStack` with two bare `Spacer()`s;
`Tests/HelmUITests/NamedControlsTests.swift` scans for both, since each describes a defect
nobody sees at runtime unless they are the person it locks out.

`Sources/HelmUI/DesignSystem/HelmBanner.swift` is a statement with at most one verb beside
it, on a field of the signal colour, and its ink is measured against *that fill* rather
than against the card — the same tone reads far better on a card than on the banner, so the
card's number is the one that would ship unreadable. `fillsWidth` is false for a notice
inside a centred block, where a full-width field takes the section header's inset and
matches neither the card below nor the buttons above.

`Sources/HelmUI/DesignSystem/HelmWrappingRow.swift` is a `Layout` and has to be one: an
`HStack` places every child on one line by construction and compresses them when the line
is short, so a long translation truncates a button rather than moving it down.
`sizeThatFits` and `placeSubviews` walk one shared line computation, which is how the
classic defect in a hand-rolled flow layout is avoided by construction, and children are
proposed `.unspecified` rather than the remaining width — a button asked to fit a narrow
remainder answers with its truncated width and stays on a line it does not fit.

## What else to read

Three documents stand beside this one in the root of the tree:

- `README.md` — what Helm is, the module table, how it is installed and built.
- `CLAUDE.md` — the commands, the traps and what a session does before it changes
  anything. It is the imperative half of this document.
- `CHANGELOG.md` — one section per release, for the person who updated.

One addition is declared:

- `NOTICE.md` — the third-party artwork Helm ships and the terms it carries.
  `Sources/Modules/Layout/UI/Flags/` is the material it covers.

`Tests/HelmRuntimeTests/DocumentsNameTheTreeTests.swift` reads the standing documents and
fails where the tree lacks a backticked type, member, file name or file-and-line they name.
Four properties make it a check rather than a habit. A name can be carried by a file as
easily as by a line, so both spellings are searched. A path is checked as a path and a bare
name as a name — a bare mention claims nothing about location, a full path claims exactly
one. A line number is a claim about a file's length and is checked as one. And the check's
own contents are excluded from the tree it scans while its own name is not, because reading
itself would otherwise make the tree contain precisely what it had been told was missing.
Two curated lists carry the exceptions, spelled differently on purpose: one for what
macOS owns, one for what the documents name **because** it is gone. Swift reaches
that check through `Tests/Support/SwiftSource.swift` with comments blanked and string
literals kept, so a name only a comment writes is not in the tree and a name a literal
writes is; the other extensions are read whole, since `#` is not a comment in a plist and
`//` is half of every URL in one.
