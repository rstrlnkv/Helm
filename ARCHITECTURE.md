# Helm — Architecture

Swift 6 / SwiftPM, AppKit + SwiftUI, macOS 26+, zero external dependencies.

## Targets

```
HelmContract   protocols + wire types: ModuleEngine, EngineTransport,
               EngineCommand/Event, StatusAppearance, LocalTransport
HelmRuntime    shared plumbing, no UI: NamespacedStore, UpdateVersion/UpdateCheck,
               ReleaseDigest, HelmLog + HelmFailure + Redact, PermissionCheck + TrashFailure,
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

**The window casts no shadow; the glass does.** `panel.hasShadow` is `false`
deliberately. AppKit derives a transparent window's shadow from the alpha of
its content, and the content here is a card floating at the top of a strip
that runs from the status item to the bottom of the screen. Under
`.regularMaterial` the opaque silhouette was the card, so the shadow was the
card's. Liquid Glass paints its backdrop differently, and AppKit began shading
the whole strip — which reads as a hairline tracing the shadow instead of the
card's edge. Glass carries its own shading, so the window's was turned off
rather than fought with; there is nothing left for `invalidateShadow()` to do.

**The strip is wider than the card, on purpose.** A window shadow is drawn by
the window server *outside* the frame, so the strip could once be exactly as
wide as the card. Glass draws its shading *inside* the view, and at equal
widths the card's shadow was cut off flat at the left and right edges — so the
strip carries `helmPanelShadowMargin` on each side and the card is centred in
it. The margin is transparent and behaves like the rest of the strip below the
card: a click there dismisses the panel. Order matters in the modifier chain —
`.frame(maxWidth: .infinity)` must come *after* `.glassEffect`, or the effect
paints the whole strip and the card comes out wider than the tiles inside it.

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

**What must not reach the file.** A VPN connection name announces an employer or
a provider; an absolute path carries the account name; a bundle id names a
person's habits. `Redact` (HelmRuntime) is what goes in instead: `Redact.path`
rewrites the home prefix to `~`, `Redact.vpn`/`Redact.app` give a short stable
tag (`vpn#3f9a`). FNV-1a rather than `Hasher`, which is seeded per process —
yesterday's session would not compare with today's, and comparing across
restarts is exactly what triage does. Log counts and outcomes freely; run any
name or path through `Redact` first. `HelmFailure.describe` strips the home
path from every string it emits, including messages, which carry no key for
`Redact.path` to find them by.

The release process depends on this file: dev builds are triaged against it,
and a build graduates to the beta channel only at zero known problems
(VERSIONING.md).

## Layout switching

The `layout` module reads every keystroke and types into other applications,
which is a larger claim on the machine than anything else Helm does. Four things
make it workable, and each is somewhere specific:

- **The tap is listen-only** (`SystemPorts.swift`, `CGKeyTap`). It reports keys
  and can neither delay nor swallow them, so nothing here can freeze somebody's
  typing — an active tap that hangs does exactly that.

- **An engine reads its settings when it starts, not only when they change.**
  `LayoutEngine` reloaded on the transport's `settingsChanged` and nowhere else,
  so every launch ran on whatever the initialiser held. Most fields have a
  sensible initialiser value and the gap never showed; the tap key has none but
  "no key", so the gesture was bound to nothing on every start and worked only
  in a session where somebody had opened the page. It failed silently, because a
  key bound to nothing refuses before there is anything to log. The test that
  covered the stored defaults sent `settingsChanged` itself first — the one
  thing a launch does not do. **A test that arranges the event whose absence is
  the bug cannot see the bug.** Engines that read the store at the point of use
  (KeepAwake) never had this; engines that cache into fields must reload in
  `activate()`.

- **State kept between events gets stuck; the event already knows.** The tap
  machine used to remember which other modifiers were held, in a set filled on
  each press and emptied on each release. There is no guarantee a release ever
  arrives — the tap starts while a key is held, an event is dropped while the
  tap is re-enabled, a key reports its press and its release under different
  codes. One code left behind spoiled every tap from then on, permanently and
  silently: the key kept working as a modifier, the events kept flowing, and the
  gesture was gone with nothing in the log. Shipped that way in 0.7.2-dev.21.
  Every event carries the live flags; read them and keep nothing. **Before
  storing anything derived from an event stream, ask which event clears it and
  what happens the one time that event never comes.**
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

### The one exception, added with the selection actions

`AXSelection` (Layout/SystemPorts) reads and writes the *selection* rather than
the last typed word, and it has two routes: `AXSelectedText` where the app
answers, and ⌘C/⌘V where it does not — which is most Electron apps and most web
views. So the sentence above holds for the word conversion and not for the three
selection shortcuts.

The cost is real and is not fully paid: `restore(_:)` puts back a *string*, so a
clipboard holding an image, a file promise or RTF is replaced with plain text or
with nothing. That is the exact harm the no-clipboard rule was written against.
That used to be contained by the three shortcuts shipping unbound, so only
somebody who went looking could meet it. When the module was reduced to one
gesture with a default key, that containment disappeared and the defect did not
— for a few hours the app was one tap away from eating an image somebody had
copied, on by default, for everyone.

So the containment is a rule instead of an absence: `PasteboardSafety.canBorrow`
refuses the paste route whenever the clipboard holds anything a string restore
cannot give back, and the selection is left alone. Declining is a correct
outcome that the person can see; silently emptying their clipboard is not. The
honest fix is still to save and restore every representation, and until that
lands this is the guard rather than the cure.

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

The same applies to **who is in front**, and it had to be learned twice.
`FrontmostApp` (HelmRuntime) is `RunningApps` for
`NSWorkspace.frontmostApplication`, and it exists because the Keyboard module
read that property on whatever thread asked. That survived for as long as every
caller was the key tap's own main-thread callback, and stopped surviving in
0.7.2-dev.20, when the fix gesture was moved to a background queue to keep a
slow accessibility call off the main run loop — taking eight call sites with it.
The app went down on the first use of the gesture with text selected.

The rule that would have caught it: **moving work off the main thread is a
change to every AppKit call it can reach**, not only to the one that was slow.
The accessibility probe is what blocks; the frontmost app, the pasteboard and
the sound are AppKit and come straight back to main.

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

There are **three** gates and they answer different questions. `RemovableScope`
asks what belongs to an *application*; `UserFileScope` (also HelmRuntime, and
formerly the disk module's private `DiskSafety`) asks what belongs to the
*user*, and `WatchScope` (Autopilot's own, because a rule runs unattended on
input from a writable plist) asks where a folder rule may reach — everything except `/System`, `/usr`, `/bin`, a home directory itself, a
volume root and a top-level directory. Disk and Duplicates use the
second; Leftovers and Uninstaller the first. Wiring a module to the wrong one is
a real mistake with a misleading symptom: the duplicate finder pointed at
`~/Downloads` under `RemovableScope` disabled every checkbox in its own result,
which reads as a permissions problem rather than a defect.

Refusals are reported, never dropped: they come back as
`TrashFailure.Reason.outOfScope`, which is Helm refusing, not macOS — nothing was
attempted.

**What "freed" means.** `HelmTrash.remove` reads a path's size before moving it,
and for a folder it walks it. `totalFileAllocatedSize` on a directory answers for
the directory entry, and on APFS it answers **zero** — so Disk, whose whole job
is disk space, told people a folder they had just trashed freed nothing, and
Leftovers would have said the same about every plug-in bundle the moment it
stopped keeping its own recursive count. A folder is what these screens delete
most. The walk is bounded by what the person selected and happens once per path.

`LeftoversEngine` and `UninstallerEngine` reach the gate with their own `home`
rather than the process's: an engine handed one home for its scan and falling
back to another for its removal gate is two homes in a type that was given one,
and it makes the removal path untestable outside the real `~`.

## Autopilot — read before touching

The autopilot module acts on somebody's files without being asked each time, so its
three guarantees are load-bearing rather than nice to have.

**A rule may only reach the user's own working files.** Neither shared gate is
right for this: `RemovableScope` is about applications, and `UserFileScope` is a
blocklist that says yes to `~/Library/Messages`, `~/Library/LaunchAgents` and
another account's home. Helm holds Full Disk Access and these rules are JSON in
a plist any process running as the user can write, so `WatchScope` — the
module's own gate — is positional and narrow: inside the home directory, never
inside `~/Library`, or inside a volume under `/Volumes`. It resolves symlinks
first, because a destination chosen through the panel can be replaced by a link
afterwards and the question is where a path *leads*.

**A rule must not act on the same file twice.** A rule that sorts a file into a
subfolder of the folder it watches sees it again on the next sweep. `RuleStamp`
writes `com.helm.autopilot.stamp` — an extended attribute holding the ids of the
rules that have had their turn — and the runner asks before it acts. An xattr
rather than a list of paths because it travels with the file across a move,
which is exactly the case that matters. A stamp that will not stick is logged
and shrugged off: refusing the file would make a volume without xattrs a volume
where no rule works.

**A rule must not overwrite.** An arriving file whose name is taken is numbered
`a 2.pdf`, the way the Finder numbers a copy. This is the one failure the module
could commit that nobody can undo.

**A rule must not run before it has been seen.** New rules are off, and the
editor shows the dry run — the files in the folder right now and what would
happen to each — with the switch beside it. `RulePlan` produces the same value
the runner executes, so what was shown and what happens cannot drift.

Three triggers, and none covers the others: FSEvents (coalesced at one second,
because a download in progress writes many times and acting on the first write
moves a half-written file), an hourly sweep (a rule that says "older than 30
days" comes true with nothing happening), and run-now.

There is **no script action** and there must not be one. Helm is ad-hoc signed
and unsandboxed and its rules live in a plist any process can write; a script
action would turn "a file appeared" into arbitrary execution.

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

## An observer outlives the thing it points at

A module can be switched off. `ModuleHost.disable` calls `deactivate()` and then
drops the engine, so everything the engine owns goes with it — and anything
still holding a pointer to one of those things is holding freed memory.

`IOPSPowerInfo` handed IOKit `Unmanaged.passUnretained(self)` and added a run
loop source that nothing ever removed. Switch Keep Awake off, unplug the
charger, and the callback resolves that pointer into a port that no longer
exists. The port had no `deinit` and `PowerInfoPort` had no stop, so there was
nowhere the teardown could even have been written.

`NotificationCenter` observers hide this: the centre keeps the token and a
block capturing `[weak self]` costs nothing when it fires late. A C callback
taking a raw context does not. **Every observer a module starts has to be
stoppable, and `deactivate()` is where it stops** — with `deinit` as a backstop
for the routes that do not go through it. Removing the source takes it off this
run loop; invalidating it stops a callback already scheduled, which is the one
that would land on the freed object.

## Running other programs

`HelmProcess.run` reads stdout before it waits, because waiting first
deadlocks: the child fills the pipe, blocks in `write(2)`, and never reaches
the exit the wait is waiting for.

**The same is true of the descriptor nobody reads.** stderr was given a
`Pipe()` and never drained, which is the identical deadlock one file
descriptor over — past about 64 KB the child blocks, never exits, never closes
stdout, and the read above it never returns. The comment said the diagnostics
were discarded; discarding is `FileHandle.nullDevice`. A `brew` command with a
deprecation warning per formula passes 64 KB without trying, and every module
that runs a tool was one chatty command away from a parked thread and an orphan
child. Measured before and after: 200 KB on stderr held the caller until a
watchdog killed the child; the same volume through stdout took 19 ms.

`stream` keeps stderr on purpose — a console should show what the tool says.
It is output that gets *parsed* that must not carry diagnostics, which is why
`ShellProcessRunner` merging the two turned a `brew` warning into a row with an
Uninstall button.

## A path that exists is not the path you wrote

`NSString.standardizingPath` does more than resolve `.` and `..`: for a path
that **exists on disk** it rewrites `/private/var/…` to `/var/…`. `UserFileScope`
standardizes before testing its protected prefixes, and the list named
`/private/var/db` — so every real path under it was rewritten out from under
its own prefix and allowed, while `/private/var/db/does-not-exist` kept the
prefix and was refused. The test that covered it used the second kind of path.

`/private` is not a firmlink and `/` and `/private/var/db` share a device, so a
scan of the volume walks it, the ring draws it and the basket accepts it. Both
spellings are compared now. **A gate tested only with paths that do not exist
is tested on the one input the filesystem treats differently.**

## Guards that are tests, not prose

Two rules about the interface are enforced by scanning the source in
`Tests/HelmUITests/NamedControlsTests.swift`, because both describe a defect
nobody sees at runtime unless they are the person it locks out.

- **Every control has a name.** A `Picker("")` or `TextField("")` looks finished
  — the segments say "Installed / Updates / Search" and no heading is wanted
  above them — and reads aloud as a tab group with no name. The Autopilot rule
  editor had nine such controls, so a rule could not be built at all with
  VoiceOver; six more were in five other modules. Satisfy it either by giving
  the control its real label and hiding it (`Picker(Str.thing, …)` with
  `.labelsHidden()`, which is what that modifier is for) or with
  `.accessibilityLabel`. A placeholder is not a name: it disappears the moment
  there is a value to read.
- **An empty page is drawn by one component.** `HelmEmptyState` and
  `HelmBusyState`; `HelmCenteredContent` is the box they sit in and stays inside
  the design system. There were ten empty pages in eight shapes — spacing 10 or
  14, text wrapped at 360, 380, 420 or not at all — and every one was reasonable
  beside the screen it belonged to.

The first version of that scan looked for `HelmCenteredContent(` and was blind
to the trailing-closure form, which is the form all eight offenders used: it
passed green with an offender in the tree. **A guard that has never been seen to
fail is not a guard** — put the defect back and watch it catch.

## Dev loop

```bash
swift test                              # 900+ unit tests, pure logic, seconds
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
