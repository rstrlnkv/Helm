# Helm — Architecture

Swift 6 / SwiftPM, AppKit + SwiftUI, macOS 26+, zero external dependencies.

## Targets

```
HelmContract   protocols + wire types: ModuleEngine, EngineTransport,
               EngineCommand/Event, StatusAppearance, LocalTransport
HelmRuntime    shared plumbing, no UI: NamespacedStore, UpdateVersion/UpdateCheck,
               ReleaseDigest, HelmLog + Redact, PermissionCheck + TrashFailure,
               RemovableScope, SystemExtensionParser, SystemFolderNames,
               ModuleOrder, Plural, HelmBytes
HelmUI         design system (RingIcon, IconPickers, panel cards,
               HelmCenteredContent), L() localization, ModuleViewModel,
               TransportClient, ModuleDescriptor protocol
Module_<X>_Engine   headless module logic + ports (no UI imports)
Module_<X>_UI       descriptor, settings page, panel tile, view model
HelmApp        executable: AppDelegate, ModuleHost/Registry, StatusItem,
               HelmPanel, SettingsWindow, UpdateService/Installer, Changelog
Tests/…        one test target per engine + HelmContract/HelmRuntime
```

## Module pattern

Every module is a **descriptor** (metadata + UI factories, in `Module_<X>_UI`)
plus an **engine** (headless logic, in `Module_<X>_Engine`). They talk only
through an `EngineTransport` channel:

- **Request/response**: `transport.send(EngineCommand)` returns `Data` (JSON).
  UI side wraps this in `TransportClient` (typed request/fire helpers).
- **Events**: engines `emit(EngineEvent)`; `LocalTransport.events` is a
  broadcast stream that **replays the last event to late subscribers** — the
  engine emits its initial state during `activate()`, before any view model
  exists. Without replay, toggles show stale defaults at launch.
- Engines never import UI; production side effects live behind **ports**
  (protocols with system implementations in `SystemPorts.swift` + fakes in
  tests). Pure decision logic (parsers, matchers, progress math) sits in
  `Engine/Logic/` and is unit-tested (TDD).

`ModuleHost` owns lifecycle: reads the enabled flag from the module's
`NamespacedStore` (`module.<id>.*` in UserDefaults), builds the engine, calls
`activate()`, wraps the transport in a `ModuleViewModel`. `ModuleRegistry.all`
is the single list — a new module = add its descriptor there.

**Store change notifications**: every `NamespacedStore.set` posts
`.helmStoreChanged` (always on the main thread) with the full key. Views that
mirror store values into `@State` re-read on it — this is what keeps the panel
and the Settings window in sync in both directions.

**Blocking work**: transport handlers run on the Swift-concurrency pool. Any
blocking call (Process + waitUntilExit, recursive file scans) must hop through
the engine's `blocking { }` bridge (dispatch queue + continuation), or it parks
a pool thread for seconds.

## UI shell

### Menu-bar panel (`HelmPanel`) — read before touching

The panel looks simple and is not. Three facts, each earned through
frame-by-frame debugging; violating any of them reintroduces visible glitches:

1. **The window frame is set once per open and never changes while visible.**
   It covers a transparent strip from the status item to the bottom of the
   screen; the card is top-pinned inside and all size changes are pure SwiftUI
   animation. Moving/resizing a transparent layer-backed window mid-animation
   drags the composited surface ahead of the SwiftUI redraw (both with
   `animator()` and with instant `setFrame`).
2. **`panel.makeKey()` after `orderFrontRegardless()`.** A non-activating panel
   does not tick SwiftUI animations until it is key — without this not even a
   chevron rotation renders.
3. **No custom `hitTest`.** An earlier pass-through override compared
   superview-space points against flipped-view bounds and swallowed every
   click. Clicks below the card are handled by a transparent SwiftUI tap area
   that posts a dismiss.

Disclosures (panel Utilities row, Keep Awake's ⋯ block) use the measured-height
accordion: content always in the hierarchy, natural height captured via
`onGeometryChange`, animate `frame(height: expanded ? h : 0)` + `.clipped()`
on the block itself. Animating to `nil` height or relying on insertion
transitions desynchronizes the card from its content. `.move(edge:)`
transitions paint rows over the header — fade only.

### Status item

`StatusItemController` redraws from `statusAppearance(vm)` of the first active
module: tint, optional glyph override, timer progress (countdown arc) and
title (remaining time). Redraw is keyed/bucketed; a 1 s timer runs only while
a countdown is live. Subscriptions come from `objectWillChange`, which fires
**before** the value is written — always hop to the next main-actor turn
before reading state. The right-click menu is assigned to `statusItem.menu`
and opened via `performClick` (hand-positioned `popUp` breaks once the menu
grows: it opens pre-scrolled).

### Settings window

AppKit `NSSplitViewController`; sidebar is the vibrant source list. Both panes
own their top strip (`safeAreaRegions = []` + fixed spacer) — otherwise
content scrolls under the floating traffic lights and picks up the system
scroll-edge fade.

**The window's size belongs to the user — `sizingOptions = []` on both
hosting controllers.** By default `NSHostingController` feeds SwiftUI's ideal
size into auto layout, and any pane whose ideal height is unbounded (a
Spacer-centred empty state, a plain VStack outside a Form) silently grows the
window to the full screen. With sizing options off, panes fill whatever the
window gives them and never the reverse. One default size for every page
(940×660, measured against the densest row), `contentMinSize` 860×540, frame
autosaved. Never resize the window per page — switching pages must not move
it under the cursor.

`show(selecting:)` opens directly on a module's page (used by panel utility
rows and the status-item menu).

## Permissions

`PermissionCheck` (HelmRuntime) probes Full Disk Access by READING protected
files (`Safari/Bookmarks.plist`, `Messages/chat.db`, several fallbacks —
`TCC.db` does not exist on macOS 26). A write probe is wrong: creating files
in `~/Library/Containers` is refused even when access IS granted.

**Ad-hoc signing gotcha:** these builds have no Team ID, so macOS ties a
granted permission to the exact binary. Every rebuild invalidates the grant
while the checkbox in System Settings stays ticked. The Permissions section
says this to the user; the real fix is Developer ID signing (needs a paid
Apple account — user's call). `TrashFailure` classifies removal failures from
the actual Cocoa error code, never by guessing from the path shape.

`SystemExtensionParser` + `SystemExtensionCLI` (HelmRuntime) are the single
source for `systemextensionsctl list` — the uninstaller, the leftovers
scanner and the Settings audit all parse through them.

## Diagnostics log

Dev build logs, beta builds stay silent unless the Diagnostics switch is on.
`~/Library/Logs/Helm/helm.log`, 2 MB then one rollover, 0700.

**A failure that cannot be triaged is not logged, it is merely recorded.** The
log had thirteen error sites across seven modules and most of them named the
event without naming anything actionable: "refused out-of-scope path" (which
path?), "the app refused the replacement" (which app?),
`error.localizedDescription` — which for a Cocoa error is usually "The
operation couldn't be completed", with the domain, the code, the failing path
and the underlying error all discarded.

So:

- `HelmLog.warn` and `.error` capture `#fileID`/`#line`/`#function`
  automatically and print them after the message. `info` does not: it describes
  an event, not a fault, and the source location is noise on every line of a
  healthy log.
- `HelmLog.failure(category:what:error:)` is the common shape — something threw
  and the thrown thing is the report.
- `HelmFailure.describe` unwraps an `NSError` to domain, code, message, failure
  reason, failing path and **the underlying error**, which is nearly always the
  actual answer. `HelmFailure.osStatus` adds the name macOS knows for the code;
  `HelmFailure.posix` names an errno. A bare integer is a number to paste into
  a search engine, not a fact.
- Redaction still applies, and applies *inside* the describer: a path in a
  failing error is the most useful thing in it and the most private, so it goes
  in as `~/Documents/…` rather than not at all.

The rule about names is unchanged (see below): counts, outcomes, redacted paths
and tags are free; names are not.

## Layout switching

The `layout` module reads every keystroke and types into other applications,
which is a larger claim on the machine than anything else Helm does. Four things
make it workable, and each is somewhere specific:

- **The tap is listen-only** (`SystemPorts.swift`, `CGKeyTap`). It reports keys
  and can neither delay nor swallow them, so nothing here can freeze somebody's
  typing — an active tap that hangs does exactly that.
- **Replacement is synthesised Unicode**, `CGEvent.keyboardSetUnicodeString`,
  never the clipboard. Clipboard replacement fails outright in Electron and VS
  Code, and it destroys whatever the user had copied.
- **Translation goes through `UCKeyTranslate`** against the layouts actually
  installed, cached per source. A hard-coded ЙЦУКЕН↔QWERTY table supports
  exactly two layouts and silently mangles a third.
- **Helm's own events carry a marker** (`CGEventSource.userData`) and are
  dropped on the way in. Without it the tap reads its own replacement back as
  typing and converts it again, forever.

The decision to convert is `LayoutVerdict`, and it is written as a list of
reasons to decline with one way through: the word is not a word as typed **and**
is one once translated. A word that is valid as typed is never touched, whatever
else is true of it. Secure input, password fields, terminals and password
managers are refused before the dictionary is even consulted.

Nothing typed is written down: no key content in the log, no buffer on disk, and
the buffer is cleared when secure input turns on. The log records that a
conversion happened and in which app (redacted), never what was converted.

## Running applications — read before touching

`NSWorkspace.runningApplications` is main-thread-only, and reading it anywhere
else does not return stale data — it crashes the process. AppKit keeps the list
in a mutable array behind `NSWorkspaceApplicationKVOHelper`; `-applications`
copies that array under a lock while the main thread mutates it as programs
launch and quit. The VPN engine read it from its own serial queue for four
releases and took the whole app down the moment the two overlapped:

```
Thread 0  -[NSWorkspaceApplicationKVOHelper removeApplication:]   ← mutating
Thread 9  -[NSWorkspaceApplicationKVOHelper applications]         ← copying
          __NSArrayM_copy → _cow_copy → EXC_BAD_ACCESS at 0x0
```

So nothing reads it directly. `RunningApps` (HelmRuntime) refreshes on the main
thread — from the KVO callback and the workspace notifications, which arrive
there already — and every other thread reads the snapshot. `refresh()` off the
main thread refuses rather than asserting its way to the same crash.

There is no safe way to offer "the live list, right now, from a background
queue", so `RunningApps` does not offer one. A caller off the main thread wants
a set of bundle identifiers as of a moment ago, which is what it gets.

## Removal scope

A view model builds the plan; a view model is not allowed to be the last word on
what gets trashed. The engine takes a list of strings and deletes them, so any
defect upstream that produces a bad string produces a deleted folder — an empty
bundle id once collapsed every glob to `*`, and an empty display name claimed
`~/Library/Application Support` itself.

`RemovableScope` (HelmRuntime) is the gate inside `LeftoversEngine.trash` and
`UninstallerEngine.trashSync`. The rule is positional, not a blocklist: a path is
removable only if it sits strictly inside a folder an app is allowed to leave
things in (`~/Library`, `/Library/LaunchAgents`, `/Applications`, …), minus
`/System`, `/Library/Apple` and `/Applications/Utilities`. Anything else —
`~/Documents`, a home directory, a volume root — is refused whether or not
anyone thought to name it. A `.app` bundle is removable wherever it lives
(people keep apps in `~/Downloads`, on external volumes, in Setapp's folder) as
long as it is not a top-level directory. Paths are `standardizedFileURL`-resolved
first: `..` is invisible to a prefix test and not to the filesystem.

Refusals are reported, never dropped: they come back as
`TrashFailure.Reason.outOfScope`, which is Helm refusing, not macOS — nothing was
attempted. The disk module learned this first and re-checks
`DiskSafety.isRemovable` inside its own engine; this is the same discipline.

## Updater

`UpdateService` (networking + published state) → `UpdateCheck.evaluate`
(pure, tested: 404 = up-to-date, asset selection zip/dmg) →
`Installer.installZip`: the app downloads the release **zip** itself (so it
carries no quarantine), `ditto -x`, then a detached script waits for the
process to exit, swaps `/Applications/Helm.app`, relaunches, and removes every
temp artifact including itself. Works under ad-hoc signing. Releases must
attach the zip or the updater falls back to opening the release page.

**Nothing installs silently without a published digest.** The updater strips
quarantine on purpose and the app is ad-hoc signed, so `codesign --verify`
proves nothing — any ad-hoc signature passes, and TLS protects the transport,
not the contents. So the release notes carry `sha256 <asset> <64 hex>`, and
`ReleaseDigest.parse`/`matches` (HelmRuntime) checks the downloaded file against
it: no digest for this exact asset name → the release page opens, the row says
why, and the user decides; a digest that disagrees → the install is refused
outright. `Installer.installZip(at:expectedVersion:)` then re-reads the unpacked
bundle's `CFBundleShortVersionString`, so a mislabelled asset cannot be swapped
in either. `make-zip.sh` and `make-dmg.sh` print the line to paste.

## Changelog

In-app "What's New" renders `ChangelogData.swift` — structured entries,
localized via `L()`, badged New/Upd/Fix. `CHANGELOG.md` in the repo is the
canonical English record; it is **not** bundled.

## Localization

Code-based: `L("English", [.ru: …, …])` in `HelmUI/L10n.swift`; per-area string
enums (`AppStr`, `KAStr`, `VPNStr`, `UnStr`, `HbStr`). Every user-visible
string carries all eight languages. No .strings files.

## Disk scanning on APFS volume groups

`/` is the read-only System volume with the Data volume's directories
firmlinked in, and **both mounts report the same `dev_t`** — a device check
cannot tell them apart. Every user file is therefore reachable twice
(`/Users/…` and `/System/Volumes/Data/Users/…`), and a parallel walk charges
the bytes to whichever path a worker reached first. Symptom: "System" holding
327 GB while "Users" showed 1.5 MB, differing between runs.

`FirmlinkMap` reads macOS's own table at `/usr/share/firmlinks` and skips the
Data-side duplicates — and it only works if paths are joined through
`ScanPath.child`: `"/" + "/" + "System"` yields `"//System"`, every descendant
inherits the doubled slash, and the skip set silently stops matching in the one
case it exists for. Assert on tree *structure*, never on sizes, when testing
this: which side of a duplicate path wins is a race, so a size assertion passes
by luck (it did, once). Do not "fix" this by skipping the whole
`/System/Volumes/Data` mount: directories with no firmlink live only there
(the Spotlight index, `macOS Install Data`) and would vanish from the total.
`dev_t` is signed — see `DeviceID`; never convert it to an unsigned type.

Folder names shown to the user come from `SystemFolderNames` (HelmRuntime),
which reads macOS's SystemFolderLocalizations table so `/Applications` reads
"Программы" like it does in Finder. Eligibility is decided by path, never by
name: a project folder called "Documents" keeps its name.

## Dev loop

```bash
swift test                              # 411 unit tests, pure logic, seconds
bash Scripts/package-app.sh             # build + sign → $TMPDIR/helm-package/Helm.app
rm -rf /Applications/Helm.app
ditto "$TMPDIR/helm-package/Helm.app" /Applications/Helm.app
codesign --verify --deep --strict /Applications/Helm.app   # must pass
xattr -dr com.apple.quarantine /Applications/Helm.app && open /Applications/Helm.app
```

**Sign outside the checkout.** This repo lives under `~/Documents`, which a file
provider syncs, and the provider stamps `com.apple.FinderInfo` onto the
directories it manages faster than `xattr -c` strips it. `codesign` refuses a
bundle carrying it ("resource fork, Finder information, or similar detritus not
allowed"), so signing in place succeeds or fails by luck. An unsigned bundle has
no cdhash for TCC to hang Full Disk Access on — which is why the permission kept
coming loose after every rebuild. `package-app.sh` assembles and signs in
`$TMPDIR/helm-package` (not synced) and verifies the seal there; the copy it
leaves in `build/` is for inspection and must never be installed or packaged
from.

**Visual self-verification** (the app is an accessory; automation tools can't
click its status item): add a temporary env-gated harness in `AppDelegate`
(auto-open the panel/settings, toggle a disclosure on a repeating timer), slow
the animation to ~1.4 s, launch with the env var, capture with
`screencapture -x -o` in a loop, crop with `sips`, and inspect the frames.
Remove the harness before committing. This loop caught every panel bug that
pure reasoning missed.

Design records for the larger modules live in `docs/superpowers/specs/`, the
step-by-step build plans in `docs/superpowers/plans/`.

## Surfaces (HelmUI/DesignSystem/HelmSurfaces.swift)

**One container, and it has no border.** Half of Helm's pages are macOS
grouped `Form` sections, which the system draws as a plain fill and which we
cannot restyle. An outlined card of our own therefore reads as a different kind
of box on the next page over — which is exactly what happened: the About page
carried one bordered card and one unbordered one, side by side. `helmCard()` is
the only card; it matches the system's treatment. `HelmSurface.floatingEdge`
exists for things that float *over* content (the disk tooltip), which do need an
edge.

**Metric strips live inside the form, not above it.** They used to be pinned
with `safeAreaInset` at the window's own 20pt margin while the content below sat
at the system's much wider form insets — so the strip visibly overhung the rows
it summarized. As the form's first `Section` it inherits the system's width and
container for free, in both appearances.

## Motion (HelmUI/DesignSystem/HelmMotion.swift)

Springs, not ease curves — an eased move reads as "smoothed", a spring reads
as physical. Three tokens plus one steady-rotation helper, and the choice
between them is a safety decision as much as a taste one:

- `disclosure` (`.smooth`, zero bounce) — anything whose height is measured and
  clipped: the panel's utilities accordion, Keep Awake's ⋯ block. A bouncy
  spring overshoots, and an overshooting height clips its own content for a
  frame; that is the panel glitch class described below. Verified in slow
  motion after switching.
- `interface` (`.snappy`) — reordering rows, filters, selection moves.
- `emphasis` (`.spring(0.42, 0.78)`) — shape morphs (a pill growing into a
  card). Used throughout `DiskResultView`.

Steady rotation (the About bezel during an update check) stays linear: motion
with no destination is the one place a linear curve is right.

Two rules earned by the panel, both about *what draws where* rather than timing:

- **Don't fade a reveal — grow it.** Animating `.opacity` puts the subtree in
  an offscreen layer, where hierarchical colours resolve differently; dropping
  that layer at the end of the animation makes them jump (the "Automation"
  heading did exactly this). `.compositingGroup()` stops the jump but costs
  more than it fixes: inside a permanent layer, system materials — dividers,
  switches, bordered buttons, coloured symbols — stop blending with the card
  behind them and visibly wash out. The reveal needs no fade at all: animate
  the measured height and `.clipped()`, and the content slides out from under
  the edge with every colour native.
- **Literal colours inside animated blocks.** `.clipped()` needs a layer of its
  own while the height animates, and hierarchical styles (`.secondary`,
  `.tertiary`) are resolved against the rendering context — so they resolve
  again when that layer goes away, which reads as a blink at the end of the
  reveal. Inside such a block use `Color.primary.opacity(…)`, which tracks
  light and dark by itself and does not care about layers.
- **Never reveal with `if`.** Removing rows from the hierarchy collapses the
  card's background instantly while the disappearing rows keep drawing over
  whatever sits below. Keep the content mounted, animate a measured height, and
  `.clipped()` — then the block's edge always contains its content.

## Design language (HelmUI/DesignSystem/HelmSurfaces.swift)

Every screen speaks the same visual language, derived from the app's own
subject (Helm = the wheel you steer by):

- `HelmPageHeader` — icon plate + title + one line of what the screen is for,
  with the screen's primary control (usually the on/off switch) at the far end.
- `HelmIconPlate` — the symbol on its category tint, lit from behind by a soft
  radial glow. Also used standalone in empty states.
- `HelmMetricStrip` — instrument readout: monospaced figures over small-caps
  labels, split by hairlines. **Form screens only** (About, Keep Awake, VPN):
  there the dials read as state. List screens (Uninstaller, Homebrew,
  Login Items) deliberately do NOT use it — their chrome is one toolbar row
  (segments · search · refresh) and the counts live as a quiet status line in
  the bottom bar, which costs no vertical space.
- `.helmCard()` — the one card treatment: `primary.opacity(0.035)` fill, **no
  border**, 12pt continuous corners. The fill is measured against a real `Form`
  section on the same background: the system's section sits 7 L from the panel
  in both themes, and the card must sit there too.
- The About page's bezel around the app icon rotates **only** while an update
  check is in flight — motion means work, never decoration.
- `HelmAppMark` draws Helm's mark from `helm-ring.svg` — the same artwork the
  app icon is built from — rather than reading the icon back. macOS 26 resolves
  `.icon` variants at the system level, so the app can only ever get the variant
  matching the current appearance, and the light variant's white slab reads as a
  hole inside Helm's surfaces. Composing it here also lets the mark sit in
  deliberate contrast to its window. `package-app.sh` copies the svg in for this.
- `HelmBadge` — the one pill: a short word, `caption2`, fill at
  `tint.opacity(0.20)`, text at `Color.primary.opacity(0.85)`. The tint colours
  the fill and nothing else. There were seven hand-rolled variants, two of them
  30 px apart in the same row, one drawing orange text on orange (about 1.7:1 at
  11 pt); contrast is not something a caller should be able to get wrong.

The menu-bar panel deliberately does NOT follow this: it is a transient
surface with its own hard-won layout rules (see the panel section above).
