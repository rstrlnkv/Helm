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

## Motion (HelmUI/DesignSystem/HelmMotion.swift)

Springs, not ease curves — an eased move reads as "smoothed", a spring reads
as physical. Four tokens, and the choice between them is a safety decision as
much as a taste one:

- `disclosure` (`.smooth`, zero bounce) — anything whose height is measured and
  clipped: the panel's utilities accordion, Keep Awake's ⋯ block. A bouncy
  spring overshoots, and an overshooting height clips its own content for a
  frame; that is the panel glitch class described below. Verified in slow
  motion after switching.
- `interface` (`.snappy`) — reordering rows, filters, selection moves.
- `emphasis` (`.spring(0.42, 0.78)`) — shape morphs (a pill growing into a
  card). Currently unused; it is what the notch module used.
- `contentFade` (short ease-out) — content appearing inside a container that is
  already animating. Two springs against each other read as wobble.

Steady rotation (the About bezel during an update check) stays linear: motion
with no destination is the one place a linear curve is right.

Two rules earned by the panel, both about *what draws where* rather than timing:

- **Composite before fading.** Animating `.opacity` puts a subtree in an
  offscreen layer, and hierarchical colours (`.secondary`, `.tertiary`) resolve
  differently inside one. Dropping the layer at the end of the animation makes
  those colours jump. `.compositingGroup()` ahead of `.opacity` keeps the
  rendering path identical during and after.
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
  labels, split by hairlines. Each screen shows the numbers that matter there
  (About: version/build/modules; Homebrew: packages/updates/casks; Uninstaller:
  apps/leftovers/size; VPN: connections/active/automatic; Keep Awake:
  state/timer/automations).
- `.helmCard()` — the one card treatment: `primary.opacity(0.05)` fill,
  `primary.opacity(0.08)` hairline border, 12pt continuous corners.
- The About page's bezel around the app icon rotates **only** while an update
  check is in flight — motion means work, never decoration.
- `AppIconImage.dark` draws the app icon forced into `.darkAqua`: AppKit
  resolves icon variants at draw time, and the light variant's white slab reads
  as a hole inside Helm's surfaces.

The menu-bar panel deliberately does NOT follow this: it is a transient
surface with its own hard-won layout rules (see the panel section above).
