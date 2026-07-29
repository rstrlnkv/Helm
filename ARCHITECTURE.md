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

`HelmRuntime` is the answer to "has this been written already", and the list of
what is in it does not live here — it went stale twice, which is the exact
duplication the list exists to prevent. **`ls Sources/HelmRuntime` before
writing a helper inside a module.** Twenty-eight files today; `HelmTrash`,
`FileWeight`, `HelmProcess`, `OffTheCooperativePool`, `RunningApps` and
`UserFileScope` were each written two to five times in modules before they
moved there.

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
`offTheCooperativePool` (HelmRuntime — a dispatch queue + continuation), or it parks
a pool thread for seconds.

**A module's state belongs to its view model, not to its page.** Leaving a
module's page in Settings tears down the type-erased subtree and every
`@StateObject` in it; coming back builds a new one and runs `.task` again.
`DiskViewModel.shared(vm:)` and `KeepAwakeViewModel.shared(vm:)` cache per
underlying `ModuleViewModel` for exactly this reason, and Uninstaller and
Homebrew have the same now — the uninstaller's own comment measures what it was
paying: four seconds for 39 bundles, nine on a cold cache, on every sidebar
click. Caching the view model is only half of it: whatever the page keeps in
`@State` (the app list, the loading flag) dies with the page, so a cached view
model feeding a list the page throws away is not a cache.

**`ModuleMetadata.shortName`** is what the sidebar shows, defaulting to `name`.
The sidebar column is fixed and truncates mid-word; page headers, the panel and
the icon menu take the full name. Only a module named after a macOS pane with a
compound name has needed it so far — and macOS ships both forms for that pane,
so the short one is looked up rather than shortened by hand.

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

One pure rule decides what the icon shows: `StatusPlan.choose` reads every
enabled module's `statusAppearance(vm)` — tint, optional glyph override, timer
progress (countdown arc), title, `spinUntil` — and returns, in order: the
module whose spin is still running, else the first that tints, else the first
that carries a title. **A module asking to spin borrows the icon for the
length of its spin** (`StatusPlan.spinDuration`; the newest spin wins when two
overlap).

The title tier is last on purpose. A module may have a title and nothing else —
VPN names the connection a rule raised for 3 s while its ring turns for 1.2 s,
and it tints nothing, because a tint is a *permanent* presence in the menu bar
(tier two is the fallback whenever no spin runs) and "a rule fired" is a
moment. Without the third tier that name died with the ring; measured in the
menu bar, gone by 1.8 s. Keeping it **below** the tint is the same rule the
countdown's suppression of the spin encodes: Keep Awake tints while a countdown
runs, and a moment must not interrupt continuous state. A name that arrives
while another module owns the icon is simply not shown — its spin still
happened, and that is the half that carries the news.

A live countdown and Reduce Motion each suppress the movement and keep the
title (`StatusPlan.spins`). Reduce Motion is read fresh per redraw, like
`HelmMotion` — it changes while the app runs.

Redraw is keyed (`StatusPlan.redrawKey`, progress bucketed) and **the frame
index is part of the key**, or the key suppresses the animation. Two
`RepeatingTick`s: 1 s while a countdown runs, 1/30 s while a spin does. The
spin tick drives the refresh that decides whether it is still wanted, so it
disarms itself within a frame; `RepeatingTick` is where the invalidation is
tested, because the controller needs a real status bar to exist at all.

Subscriptions come from `objectWillChange`, which fires
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
(1060×700 — the Disk screen's bar-with-statement needs an 810 pt detail pane,
which 940 does not give), `contentMinSize` 860×540, frame
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

**A tag has to be salted, or it isn't redaction — it's an index.** `Redact.tag`
hashed a name with no salt, over values drawn from small public dictionaries
(bundle ids, VPN provider names, Homebrew formulae): inverting it against the
104 bundle ids installed on one Mac identified **every one of them**, which is
the opposite of what this section claimed the function did. The salt is now
random per install, 16 bytes in a `0600` file beside the log rather than the
keychain — the threat this guards against is someone reading a log the user
handed them, not someone with the user's disk, and a keychain prompt for a
logging detail is the wrong trade for that. Salting does not cost the property
FNV-1a was chosen for: the salt is stable per install, so a line from yesterday
still compares equal to a line from today, while a tag pasted into a bug report
means nothing on anyone else's Mac.

**A latch belongs to the file it guards, not to whichever process asks.** The
one-time purge that discards logs written before redaction existed used to
record that it had run in `UserDefaults` — namespaced per *process*, not per log
file. Any other binary linking `HelmRuntime` (a test target, a script) therefore
ran the purge again against the one real `helm.log` and wiped it, with nothing
in the (now-empty) file to say why — this cost the third review pass a dev
build's own triage evidence mid-session. The latch is a file beside the log now.

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

**Undo has a precondition, and it needs two kinds of key event to tell it
apart.** The record of what was converted is only good while the caret has not
moved: sending backspaces after the caret went elsewhere edits text nobody
asked about. But the Carbon hotkey that *invokes* undo is itself a chord, and
the head-inserted tap sees it before Carbon dispatches it — so the shortcut
would kill its own precondition. That is why one navigation event used to be
forgiven. The tap could not tell that chord from a bare arrow key, and both
spent the same budget: press ←, tap the modifier, and the undo fired at the new
caret. A modified key now arrives as `.chord` and a bare navigation key as
`.navigation`; only the chord softens, a bare key invalidates. The tap still
cannot tell ⌘← from the shortcut, and does not need to — both are chords, and
forgiving one is what the budget is for.

### The one exception, added with the selection actions

`AXSelection` (Layout/SystemPorts) reads and writes the *selection* rather than
the last typed word, and it has two routes: `AXSelectedText` where the app
answers, and ⌘C/⌘V where it does not — which is most Electron apps and most web
views. So the sentence above holds for the word conversion and not for the selection.

`restore(_:)` puts back a *string*, so a clipboard holding an image, a file
promise or RTF would come back as plain text or as nothing — the exact harm the
no-clipboard rule was written against. Both routes now refuse rather than
borrow: `PasteboardSafety.canBorrow` gates the paste and, since it destroys just
as thoroughly, the ⌘C read as well. It was on the write only, which is the half
that is easier to think of.
That used to be contained by the selection shortcuts shipping unbound, so only
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
main thread asserts **and** refuses: the trap catches the caller in a debug
build, the refusal keeps a release build alive. The doc used to say "refuses
rather than asserting", which reads to a test author as inert and traps.

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
long as it is not a top-level directory. Paths go through `PathCanonical`
first, which resolves every **symlinked ancestor** in the path and deliberately
leaves the leaf alone: `standardizedFileURL`/`standardizingPath` collapse `..`
but do not resolve symlinks, while `trashItem` follows them, so a link planted
in an allowed root (the leftovers scan enumerates four `~/Library` plug-in
directories that do not exist on a stock install, and can therefore be created
by any process as a link) let the gate approve one path and the Trash act on
another. The leaf is left unresolved on purpose — trashing a stale alias has to
remove the alias, not chase it to whatever it points at.

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

**A glob is a guess, and a guess must be checked against what is installed.**
The uninstaller finds leftovers by globbing the bundle id (`com.acme.tool*`
across Caches, Containers, Application Scripts, Group Containers), and a prefix
glob matches a *different* app whose id merely starts the same way —
`com.acme.toolPro`, `com.vendor.App.staging`, the ordinary shape of vendor
namespacing. Worse, a match on the id rather than the display name is the kind
`UninstallPlan.defaultSelection` trusts enough to pre-tick, so a neighbour's
live container arrived on the review screen already selected. Glob results are
filtered against the installed set two ways at once — `AppLister.isKnownToSystem`
asks LaunchServices, and `installedPaths(forBundleID:)` asks the same directory
listing `scanOrphansSync` reads — because a directory listing alone misses an app
nested one folder down (`/Applications/Adobe Acrobat DC/…`), which LaunchServices
still knows about. And the filter is not only for globs: the *exact* candidates
(`Containers/<id>`, `Preferences/<id>.plist`, `HTTPStorages`, `WebKit`, `Cookies`,
`Saved Application State`) went through no ownership check at all until they were
routed through the same filter, because their hazard is a different one — not a
prefix match on a neighbour's id, but an app that simply declares somebody else's
bundle id outright in its own `Info.plist`. **A path that a pattern — or an
id — produced is a candidate, not a finding: something has to say it belongs to
the app being removed.**

## Autopilot — read before touching

The autopilot module acts on somebody's files without being asked each time, so its
four guarantees are load-bearing rather than nice to have.

**A rule may only reach the user's own working files.** Neither shared gate is
right for this: `RemovableScope` is about applications, and `UserFileScope` is a
blocklist that says yes to `~/Library/Messages`, `~/Library/LaunchAgents` and
another account's home. Helm holds Full Disk Access, so `WatchScope` — the
module's own gate — is positional and narrow: inside the home directory, never
inside `~/Library`, or inside a volume under `/Volumes`. It resolves symlinks
first, because a destination chosen through the panel can be replaced by a link
afterwards and the question is where a path *leads*.

Narrowness used to be argued entirely from the rules living in a plist any
process running as the user can write — and that argument is now only half true.
A rule set must be **Helm's own** to be honoured at all: `AutopilotEngine.folders`
decoded the plist with no authenticity check, re-read on every hourly sweep, so
any unsandboxed process could plant a move-or-trash rule and borrow Helm's Full
Disk Access with no TCC grant of its own — on a module that is on by default.
Rules now carry an HMAC keyed from a secret Helm creates once in its own login
keychain item (the `SecItemAdd` access-list treatment `KeychainCredentials.helmCacheWrite`
already uses); a rule set whose seal does not match decodes to `[]`. What says a
migration is due is the absence of the **keychain item**, not the absence of the
seal — a seal is data sitting beside the rules it signs, so an attacker who can
write the file can delete the seal too, and treating a missing seal as
"pre-upgrade, trust it" would undo the whole guarantee. Only a missing *key*
means this Mac has never signed a rule set before. `WatchScope`'s remaining job,
now that authorship is settled elsewhere, is to bound what even a rule Helm
itself wrote and sealed may reach — the folder a rule watches is still user
input relayed through the editor, and a destination can be swapped for a symlink
after the picker closes.

**A rule must not act on the same file twice.** A rule that sorts a file into a
subfolder of the folder it watches sees it again on the next sweep. `RuleStamp`
writes `com.helm.autopilot.stamp` — an extended attribute holding the ids of the
rules that have had their turn — and the runner asks before it acts. An xattr
rather than a list of paths because it travels with the file across a move,
which is exactly the case that matters. A stamp that will not stick is logged
and shrugged off: refusing the file would make a volume without xattrs a volume
where no rule works.

That shrug is only survivable because the action itself is idempotent, and for
sorting it was not: the bucket was computed from the file's current parent, so
on a volume that could not keep the stamp, every hourly sweep sorted `a.jpg` one
level deeper, into `Images/Images/a.jpg`. Sorting and moving now recognise a
file already sitting where the rule would put it and report `.alreadyDone`
whether or not the stamp was written.

**exFAT is no longer the example of a volume that cannot keep it.** That
sentence stood here for a long time and it does not survive being tried: on
macOS 27, `setxattr` on an exFAT volume *succeeds* — measured on a mounted
`hdiutil` image — and macOS stores the value in an AppleDouble `._name` sidecar
beside the file, which then survived both a rename and a move within the volume.
Delete the sidecar and the stamp is gone with it, which is the shape of the real
remaining risk: filesystems that genuinely refuse extended attributes, and the
tools and transfers that drop `._` files. The tolerated loss is still real. Only
its usual example was wrong, and the fallbacks below exist because of the loss,
not because of exFAT.

The stamp's remaining job is narrower than "tagging and renaming":

- **Renaming** can now tell "already done" from "do it again" by looking at the
  file. `RenameShape` asks whether the name is one this pattern could have
  produced — every literal of the resolved pattern, in order, with a non-empty
  hole where `{name}` stands — so `{name} {date}` and `{date}-{name}` are
  recognised alike, where the runner's own `target.path != url.path` only ever
  caught the bare `{name}`. It is not total: the numbered form a collision
  produces (`a-done 2`) is not a name the shape describes, so that file can be
  renamed a second time.
- **Tagging** was always idempotent by inspection — the runner reads the file's
  tags and returns `.tagged` without writing if the tag is already there.

What the stamp still buys, then, is the work and the record rather than the
correctness: without it an unstamped file is re-examined and re-reported on
every sweep, and a history of one file tagged once reads as one row an hour.

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

**Anything the language shapes goes through `HelmUI`, not through `Foundation`
with its defaults.** `Bytes` (sizes), `Decimal` (a bare number, so "1,5 МБ" does
not sit beside "1.5 МБ"), `Quoted` (a language's own quotation marks — «…»,
„…", 「…」), `HelmDates.relative` / `.dayAndMinute`. Each of these existed as a
hand-rolled call somewhere first, and each was wrong in the same way: a
formatter built with no locale answers in the *system's* language, which on a
Mac outside Helm's eight means an English UI with Italian dates spliced into it.
A formatter also must not be a `static let`: the app's language can change while
it runs, so they are cached per language, never once.

**A language code is not always the directory macOS files it under.**
`SystemFolderNames` built `<language>.lproj` from `AppLanguage`'s raw value,
which happens to equal the lproj name for seven of Helm's eight languages — and
is wrong for the eighth: macOS ships `zh_CN.lproj`, `zh_TW.lproj` and
`zh_HK.lproj`, never a plain `zh.lproj`. Loading a table that isn't there isn't
an error, it's an empty dictionary, so this failed silently: a Chinese user's
Disk ring read `/Applications` as literal "Applications" where Finder writes
应用程序. Helm's `zh` is Simplified, so the fixed mapping reads `zh_CN`. Any table
keyed by "the language" has to be checked against what the *system* calls each
one, not assumed equal to Helm's own short code.

**Terminology is looked up, not remembered.** The units, the permission panes
and the module names all come from the tables macOS itself ships —
`FileSizeFormatting.loctable` for `Б`/`ko`/`Byte`, the settings extensions for
"Доступ к диску" and "无障碍", `LoginItems.appex` for the pane this app names a
module after. Three units and four names were invented before anyone opened
those files. When a string names something the system also names, read the
system's spelling out of its bundle rather than translating it again.

**Punctuation is terminology too.** `Quoted` had three of its eight languages
wrong for the same reason the units did. Counted over the 1176 `.loctable` files
macOS ships, for a substituted name between a pair of marks: French writes
`«\u{00A0}%@\u{00A0}»` 3206 times against 12 with ordinary spaces — and an
ordinary space there is a line-breaking one, so the name can end up on the line
below the mark that opens it. Spanish had been given guillemets (macOS: `“%@”`,
2768 to 0) and Japanese corner brackets (macOS: `“%@”`, 3099 to 1). The same
search settles VoiceOver's own vocabulary: `HelmA11y.expanded` says *condensé*,
not *réduit*, and 折りたたまれています, not 閉じています.

**A number is shaped by the language as much as a word is.** `Bytes` (sizes),
`Decimal` (a size's mantissa, grouping deliberately **off** — a separator there
is a second decimal mark), `Count` (a count of things, grouping **on** — a scan
of `/` reported "1499308 files" where macOS writes 1 499 308), `Quoted`,
`HelmDates.relative` / `.dayAndMinute` / `.day`. `HelmBytes`'s formatter cache is
keyed by grouping as well as by language and precision, or a size and a count
are handed the same formatter and whichever asked first wins.

**Fixed widths are measured, not chosen.** `HelmPickerWidth.fitting(labels:
minimum:)` sizes a pop-up from its own titles (chrome is 48 pt at the system
font, pinned by a test against `NSPopUpButton.sizeToFit`). The rule editor's
pickers were sized against English and clipped Spanish, French, Russian — and
English's own longest label. A number chosen for one language cannot survive
eight.

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

**The drill lands before the animation starts, not after it.** The obvious order
— transform the arcs that are on screen, then swap in the new tree when the
transform finishes — cannot be made seamless, and the reason is not fixable by
easing: folding small children into "other" is decided against the parent's
total in the layout being left and against the folder's own total in the layout
being entered, so the two disagree about how many arcs there are and where each
one starts. Measured on the running app, one frame apart:

```
last frame ring0:  5 arcs 0-267 267-318 318-334 334-350 350-353
first frame ring0: 3 arcs 0-288 288-358 358-360
```

Five arcs became three, every boundary moved, and the transformed state did not
even close the circle. So `RingView.open` calls `onSelect` first: the ring is
already showing the layout it will settle on, `leaving` holds a snapshot of the
one being left, and the animation carries that snapshot out over the top while
each staying arc moves from where it was to where it already is. At full
progress every arc is exactly where its layout puts it, because it *is* the
layout — the same log lines now read identically on both sides of the seam. The
reverse is the same journey with the child as the snapshot.

**What "ragged" turned out to be, measured off a screen recording.** Frame-to-
frame change in the ring's own area, sampled every 16 ms, says more than an eye
does — a smooth move is a bell, and every defect below was a spike in it:

- **A spring starts at its highest velocity.** `.smooth` has no overshoot, which
  is why it was chosen, but the first frame of the move already held the largest
  change of the whole animation (193k of a 194k peak) and the rest decayed. That
  is a snap with a tail. `ringMorph` is `.easeInOut`, which starts still.
- **One frame of the destination, before the animation.** The drill lands first,
  so at `progress == 0` the "at rest" branch drew the new layout for a frame and
  the animation then pulled it back where it came from. The guard is `pivot !=
  nil`, not `progress > 0`.
- **One frame of the origin, after it.** Resetting `unfold` in the completion
  alongside `pivot` let a frame render with the snapshot still in place and the
  progress already back at zero. `open` and the fold put it back to zero before
  they animate, where nothing is drawn between the two writes.
- **Two animations on one view.** `.animation(HelmMotion.interface, value:
  segments.count)` is there for the ring growing under a running scan, and
  during a drill it ran a second, shorter curve over the same arcs: every move
  measured as two bursts with a pause between them. It is suppressed while a
  wedge is opening.

The remaining shape is a ramp and a decay per move. It is not perfect — some
transitions still measure as two phases — and the next person to look should
record before changing anything, because none of the four above were visible by
watching.

**A jump of two levels folds into the wedge it went in through.** The code used
to set no wedge for anything further than one step, reasoning that several
levels have no single wedge to fold into. They do: the child of the level being
returned to that leads to where you were, and it is in the layout being entered.
Without it every breadcrumb jump was a hard cut, which is the worst thing the
ring did. The morph is `HelmMotion.ringMorph(levels:)` rather than `emphasis` —
a spring with no bounce, because the arcs travel a long way round the circle and
an overshoot at the end of that reads as a snap, and longer the further the ring
travels, because the same duration for one level and for three reads as a cut
with a blur on it.

**The ring lays out one level more than it draws.** A drill promotes every
level inward — the clicked wedge becomes the middle, its children take the
innermost ring, its grandchildren the next — so whatever becomes the new
outermost ring was never on screen and had nowhere to slide in from. It arrived
whole the instant the tree swapped, which is what "the third level appears
abruptly" was. `RingLayout` is asked for `RingView.visibleRings + 1` levels; the
spare is not drawn and not clickable while the ring is at rest, and during an
unfold it slides inward from outside the drawn area while fading up with the
same progress (`RingUnfold.opacity(isSpare:)`), so it reaches full opacity
exactly where the drill lands and the swap changes nothing that was on screen a
frame earlier. Laying out only what is drawn looks right in every screenshot and
wrong in every animation, which is why this is pinned by a test rather than a
comment.

**A scan has an identity, because there can be two of them.** The engine held
one scanner in one slot, and the slot was last-writer-wins. Drilling into a
folder the walk had not measured yet issues a second `"scan"` — so the second
scanner took the slot, finished, and cleared it, after which `cancel()`,
`newScan()` and switching the module off were all no-ops on a first scanner
still crossing the volume, holding the view model through its progress closure.
The partials had the same hole from the other side: they carried no root, so the
sub-folder's tree repainted the ring as though it were the disk — the volume's
free space drawn against a folder, which is the flat-grey-disc bug a comment
there says was fixed. `ScanRegistry` hands out a token only its owner can spend,
every event names its scan, and the view model draws only its own. The duplicate
finder's search slot had the identical defect and the identical fix.

**Whoever suspends must fence what it wakes into.** `cancel()` and `newScan()`
mutate state while `scan(path:)` is still suspended on the engine request, so
without a generation counter the discarded scan's result arrives afterwards and
replaces the screen the user just asked for. `DuplicatesViewModel` had this
guard from the start; Disk did not, and the volume picker was replaced by the
scan it had dismissed.

## Memory — read before writing a loop that reads or stats in bulk

**A streamed read still keeps everything it read, unless a pool says otherwise.**
`DuplicateScanner.hash` reads a megabyte at a time precisely so a video does not
become a `Data` the size of the video, and that was true of the slice and false
of the process: `FileHandle.read` hands back an **autoreleased** `Data`, and
`DispatchQueue.concurrentPerform` drains no autorelease pool per iteration. Every
slice ever read therefore stayed alive until the whole parallel block finished,
and the footprint tracked the *volume read* rather than the slice size. A scan of
14 580 files took the app past 39 GB at roughly 2 GB per second; a user reached
48 GB. Measured on the same loop over 1.8 GB of reads:

| | footprint at the end |
|---|---|
| loop as first written | **1760 MB** |
| identical loop inside `autoreleasepool` | **6 MB** |

The pool goes **inside** the loop. Around it is not enough: a single 20 GB video
is one iteration of the caller's work, and one file's worth is still gigabytes.
`DiskScanner`'s directory walk had the same defect one framework call further
out — `readDirectory` goes through Foundation, and at 1.5 M entries that was most
of what looked like the cost of the tree. **Any loop that reads file contents or
asks Foundation for resource values in bulk needs a pool inside it.**
`HashingFootprintTests` reads 384 MB and fails at 193 MB of growth without one.

**Freeing is not returning.** A freed allocation goes back to malloc, not to
macOS: after a big scan the process sat on gigabytes of emptied regions — 13 299
of them at one measurement — which is what a person sees as a menu-bar utility
holding three gigabytes half an hour after they last asked it for anything.
`MemoryReclaim.afterHeavyWork` calls `malloc_zone_pressure_relief`, the same path
the system takes when it warns processes about pressure, at the moment we know
the work is over. It is not free — it walks the zones — so it belongs at the end
of an operation the user waited seconds for, never in a loop, and it logs what it
gave back, because a reclaim that silently does nothing would end the hunt for
the next leak.

**A module's UI state outlives its page, not its module.** `DiskViewModel` and
the other cached view models exist because Settings rebuilds a page on every
sidebar visit and losing a minute-long scan — or paying four seconds to measure
39 bundles again — to a sidebar click is hostile. But the cache is keyed to the
view model and nothing cleared it, so a scan tree stayed reachable after the
module was switched off. `ModuleHost.disable` posts `.helmModuleDisabled`;
`ModuleUICache.dropWhenDisabled` (one observer per module id, written once rather
than in each view model) drops the cached instance and hands the pages back. The
on-disk scan cache still holds the result, so this drops the copy in memory, not
the answer.

**That was true of the drop and false of the free, until the retain underneath
it was found.** `dropWhenDisabled` shipped in dev.29 to fix a 48 GB leak, and it
did release the cached view model's own strong reference — but six view models
(VPN, KeepAwake, Layout, Homebrew, Disk, Duplicates) each start their event loop
as `Task { [weak self] in await self?.observeEvents() }`, and that weak capture
resolves **once**, on entry. `observeEvents()` is then an ordinary instance
method holding a strong `self` for as long as it runs, and `LocalTransport`'s
`for await` never returns, because the transport never calls `.finish()`. So the
task itself held the object for the life of the app no matter what
`dropWhenDisabled` released — dropping the cache's reference removed one of two
owners and freed nothing. `DuplicatesViewModel`'s `deinit { eventsTask?.cancel()
}` had been unreachable code for the identical reason: `deinit` cannot run while
the object retains itself. The fix is to capture the stream outside the loop and
re-acquire `self` per event, so a cancelled task actually lets the weak capture
matter, and to cancel every subscriber task on the way out rather than relying on
`deinit`. `LocalTransport.subscriberCount` is what makes the regression guard a
**count that must not grow** rather than a memory figure a test can pass by
luck. The general lesson: a `Task { [weak self] in await self?.method() }` is
only as weak as the moment it starts — everything `method()` touches afterward is
held as strongly as any other call on the stack.

**"Check every other loop that reads or stats in bulk" is answered, and the
answer is negative for `resourceValues`.** Every `resourceValues(forKeys:)` loop
in the codebase was measured rather than assumed: a serial 100 000-file walk
grows 0.3 MB without a pool, and an 8-way `concurrentPerform` over 480 000 files
grows 1.8 MB. `URLResourceValues` bridges to small value types, not to a retained
buffer the way `FileHandle.read`'s `Data` does — **do not add pools there.** The
class that does need one is `FileHandle.read`, and `ReleaseDigest.sha256` (the
digest check run on every silent update check) was a second, simpler instance of
the exact defect the duplicate scanner had: a plain serial `while let chunk =
try handle.read(upToCount:)`, not even inside `concurrentPerform`, so the pool
matters independent of parallelism. Measured: 1204 MB of growth hashing a
1200 MB file, 0 MB with the pool inside the `while`. Its footprint test used to
only print the number for a person to read — a test that logs a measurement and
asserts nothing cannot fail, and this one hadn't. It is a gate now.

**The instrument.** `HelmLog.memory(_:)` logs the process footprint under the
`memory` category as a **delta against the last reading for the same label** —
`phys_footprint`, the figure Activity Monitor calls Memory, not `resident_size`,
which counts shared pages and reads high for reasons nobody can act on. Labels
sit at the end of each scan, walk and measurement, plus an `idle` reading every
fifteen seconds that belongs to no operation at all: growth while the app sits
there is exactly what none of the others can see. Silent below 8 MB of change,
measured from the last *reported* value so a slow drift still crosses eventually.
A total explains nothing on its own — the app is 13 MB at launch and was 39 GB an
hour later, and only the deltas said which phase stood between them. That is how
the leak above was found, in one session, after `heap`, `leaks` and `sample` all
declined to attach.

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

**A stream ends when the pipe is empty, not when the child exits.** The
termination handler used to clear the readability handler and report the exit
immediately, dropping whatever was still buffered — the `🍺 /opt/homebrew/…`
line a `brew install` ends with, gone from the console the person was reading.
And `String(data:encoding:.utf8)` on `availableData` returns nil for a chunk
that ends mid-character, so a single multi-byte character straddling a read
boundary discarded the **whole block**, not the character. Both are only
reachable when the consumer is slower than the producer, which the real one is
(it hops to the main actor and redraws) — a test with an instant consumer passes
over both defects.

**A privileged command carries its content, never a path.** Keep Awake's sudoers
rule was staged in `$TMPDIR` and root was asked to `visudo -cf` and `install`
*that path*. The path stands in `ps auxww` for as long as the password prompt is
up, `visudo` checks syntax and not authorship, and `install` copies whatever is
there when it runs — so any process running as the user could swap the file
between the prompt and the install and be handed permanent passwordless root.
The rule text now travels inside the command (`SudoersRule`, pure and tested for
shape) and every file it touches lives in root-owned `/etc/sudoers.d`. The
command is also escaped for AppleScript the way `OSAPrivilegedRunner.runAdmin`
escapes its own — the two were written separately and only one had it.
**Anything handed to `do shell script … with administrator privileges` is a
place where a string becomes root's intent: no user-writable input, and no
unescaped interpolation.**

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

The second version was blind in a subtler way: it looked for the design system's
own box, so it could only catch somebody who had already found `HelmUI` and then
reached for the wrong piece of it. A page hand-rolled out of a `VStack` and two
bare `Spacer()`s — which is what centres content when you have not found the box
at all — was invisible to it. It now looks for **that shape**: two `Spacer()`s
that are direct children of one `VStack`, indentation deciding what "direct"
means, because a brace counter cannot tell a child view from a closure passed to
one. Widening it turned up a second offender nobody had reported (`Disk`'s
`scanningState` — a spinner, a caption *and* a Stop button, which is why
`HelmBusyState` now takes an `actions:` slot the way `HelmEmptyState` does).

Two lists, spelled differently on purpose: `allowed` is for a page that is
legitimately centred by hand, and every entry carries the reason; `beingFixed`
is for offenders that exist and are already being replaced, keyed by file so
that neither editing one nor fixing one turns the guard red for its author. A
third test asserts every named file still exists, because a ledger nobody prunes
starts excusing names that nothing answers to. **Both lists are empty**, which
is the state they are meant to be in — an entry is a debt, not a permission.

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

**"Ragged", "abrupt" and "too fast" are claims about frames, so measure frames.**
Five defects in the ring's animation were found this way and none of them was
visible by watching it, including two that lasted a single frame each.

```bash
screencapture -v -V 12 -x -R"$x,$y,$w,$h" clip.mov   # window rect from System Events
```

There is no `ffmpeg` on this machine and none is needed: `AVAssetImageGenerator`
pulls exact frames, and the useful number is the **change between consecutive
frames** — sum of absolute difference over a downscaled grayscale crop of the
part that moves. A smooth move is a bell: small, rising, plateau, falling,
nothing. Every defect is a spike in that curve, and each spike has a shape:

- a single frame far above the plateau, at either end → something is drawn once
  in a state the animation does not pass through;
- the *first* frame holding the largest change of the whole move → the curve is
  a spring, which starts at its highest velocity;
- two bursts with a pause between them → two animations on the same view.

Crop to the thing that moves before drawing conclusions — a whole-window
difference is dominated by the list and the breadcrumb changing at the drill,
which is honest but not what is being judged. The scratch tools that do this
are worth rewriting rather than keeping: forty lines of AVFoundation.

Design records for the larger modules live in `docs/superpowers/specs/`, the
step-by-step build plans in `docs/superpowers/plans/`.

## Surfaces (HelmUI/DesignSystem/HelmSurfaces.swift)

**One container, and it has no border.** Half of Helm's pages are macOS
grouped `Form` sections, which the system draws as a plain fill and which we
cannot restyle. An outlined card of our own therefore reads as a different kind
of box on the next page over — which is exactly what happened: the About page
carried one bordered card and one unbordered one, side by side. `helmCard()` is
the only card; it matches the system's treatment.

**A surface that floats over content takes `.glassEffect`, not an edge.** This
paragraph used to name a `HelmSurface.floatingEdge` token for the purpose. There
is no such token and there is no evidence there ever was one: `grep` found the
name in this file and in the doc comment that quoted this file, and nowhere in
the source. Both sites that float over content had meanwhile been built on the
system's material — the menu-bar panel's card
(`HelmPanel.swift`, `.glassEffect(.regular, in: .rect(cornerRadius: 26))`) and
the disk ring's readout (`Modules/Disk/UI/RingView.swift`,
`.glassEffect(.regular, in: .capsule)`). Glass carries its own edge and its own
shadow, which is the whole reason a floating thing needed one; a hairline drawn
on top of it is a second silhouette disagreeing with the first.

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
  labels, split by hairlines. **Form screens** (About, Keep Awake, VPN, Keyboard — examples, not the list):
  there the dials read as state. List screens (Uninstaller, Homebrew,
  Login Items) deliberately do NOT use it — their chrome is one toolbar row
  (segments · search · refresh) and the counts live as a quiet status line in
  the bottom bar, which costs no vertical space. A tinted figure is darkened in
  light appearance by a fraction that is **measured, not chosen**: 0.30 left
  green at 3.85:1, orange 3.99:1 and teal 3.76:1 at 16 pt medium, which is body
  text; 0.40 puts them at 4.80 / 4.97 / 4.69. Resolve the tint inside the light
  appearance *and blend it there* — `NSColor(Color)` returns a dynamic colour,
  so a blend one line outside the block resolves it again against whatever
  appearance happens to be current and silently darkens the wrong green.
- `HelmText.figureFont` / `.helmFigure()` — the one face for a figure: a byte
  size, a count, a version. Sizes were drawn in four faces across lists that sit
  next to each other, and SF Mono 11 renders "1,24 ГБ" 27% wider than SF Pro 10
  tabular, so no choice of column width could have made them agree.
- Ink that means something comes from `HelmSignal`, never from the system
  palette, and `SignalInkTests` scans `HelmUI` + `HelmApp` for the shape "a raw
  `.orange` / `.green` / `.red` handed to something that paints with it". A
  *tint* is not ink and is deliberately not caught — `HelmBadge` takes one and
  draws it at 0.20 behind `Color.primary` text, which is the whole reason the
  pill exists.
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
