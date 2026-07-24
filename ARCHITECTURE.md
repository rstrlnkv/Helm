# Helm — Architecture

Swift 6 / SwiftPM, AppKit + SwiftUI, macOS 26+, zero external dependencies.

## Targets

```
HelmContract   protocols + wire types: ModuleEngine, EngineTransport,
               EngineCommand/Event, StatusAppearance, LocalTransport
HelmRuntime    NamespacedStore, UpdateVersion, UpdateCheck (pure logic)
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
scroll-edge fade. The window grows to 1100×740 for `.utilities` modules and
returns to 820×580 elsewhere. `show(selecting:)` opens directly on a module's
page (used by panel utility rows and the status-item menu).

## Updater

`UpdateService` (networking + published state) → `UpdateCheck.evaluate`
(pure, tested: 404 = up-to-date, asset selection zip/dmg) →
`Installer.installZip`: the app downloads the release **zip** itself (so it
carries no quarantine), `ditto -x`, then a detached script waits for the
process to exit, swaps `/Applications/Helm.app`, relaunches, and removes every
temp artifact including itself. Works under ad-hoc signing. Releases must
attach the zip or the updater falls back to opening the release page.

## Changelog

In-app "What's New" renders `ChangelogData.swift` — structured entries,
localized via `L()`, badged New/Upd/Fix. `CHANGELOG.md` in the repo is the
canonical English record; it is **not** bundled.

## Localization

Code-based: `L("English", [.ru: …, …])` in `HelmUI/L10n.swift`; per-area string
enums (`AppStr`, `KAStr`, `VPNStr`, `UnStr`, `HbStr`). Every user-visible
string carries all eight languages. No .strings files.

## Dev loop

```bash
swift test                              # fast, pure-logic suites
bash Scripts/package-app.sh             # rebuild bundle
rm -rf /Applications/Helm.app && cp -R build/Helm.app /Applications/Helm.app
xattr -dr com.apple.quarantine /Applications/Helm.app && open /Applications/Helm.app
```

**Visual self-verification** (the app is an accessory; automation tools can't
click its status item): add a temporary env-gated harness in `AppDelegate`
(auto-open the panel/settings, toggle a disclosure on a repeating timer), slow
the animation to ~1.4 s, launch with the env var, capture with
`screencapture -x -o` in a loop, crop with `sips`, and inspect the frames.
Remove the harness before committing. This loop caught every panel bug that
pure reasoning missed.

Design records for the larger modules live in `docs/superpowers/specs/`, the
step-by-step build plans in `docs/superpowers/plans/`.

## Island window (module `island`)

Two windows, both static-frame (the panel rules apply here too):

- **Sensor** — permanent invisible panel strictly over the notch rect
  (`NotchMetrics.notchRect`): hover tracking + `NSDraggingDestination`.
  Clicks are safe because nothing clickable lives in the notch strip.
- **Island** — `NotchMetrics.windowRect` (notch + margins, 360pt down),
  ordered in only while the state machine is not `.hidden`, so an idle island
  never swallows clicks; `makeKey()` on expand. All motion is SwiftUI inside
  the static frame; the opaque black card needs an explicit
  `.compositingGroup()` before its background or it renders translucent.
- **macOS 26 gotcha:** dwelling with a drag at the top screen edge triggers
  Mission Control. Primary drag-in is therefore a global monitor
  (`IslandDragMonitor`: drag-pasteboard changeCount + mouse events) that
  reveals a drop zone *below* the menu bar the moment a drag starts; the
  notch-strip destination is a secondary path.
- Event sources (power / CoreAudio / AppleScript now-playing) call
  `showEvent(id:text:symbol:ttl:)`; `IslandStateMachine` (pure, tested) folds
  hover/drag/events into hidden→peek→expanded with an explicit grace window.
