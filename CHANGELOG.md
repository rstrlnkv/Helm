# Changelog

All notable changes to Helm are documented here. The format is loosely based on
[Keep a Changelog](https://keepachangelog.com/). Version-bump rules: see
[VERSIONING.md](VERSIONING.md) — MAJOR = global changes, MINOR = new/polished
features, PATCH = fixes.

## [Unreleased] — 0.7.2

### Added
- **The disk map answers VoiceOver.** A `Canvas` is one opaque rectangle to the
  accessibility system, so the ring said nothing at all and drilling into a
  folder was a double-click with no keyboard equivalent.
  `accessibilityChildren` now supplies the elements the drawing implies: one
  per wedge of the innermost ring, each reading its name, its size and its
  share of the folder, each with a way in; plus the hole in the middle, which
  goes up a level. The list beside the ring gained the same drill as a named
  accessibility action and a context-menu item — the double-click still works
  and is no longer the only way.

### Changed
- **Failures say enough to be triaged.** `HelmFailure` unwraps an `NSError` to
  its domain, code, message, failing path and — the part that usually holds the
  answer — the error underneath it; `osStatus` and `posix` name their codes
  instead of printing a bare integer. `warn` and `error` capture
  `#fileID`/`#line`/`#function`, because one wording can come from four call
  sites and the wording is what reaches a bug report. Redaction happens inside
  the describer, so a failing path arrives as `~/Documents/…` rather than not
  at all — including the home path spelled the other way, as
  `/System/Volumes/Data/Users/…`, which `Redact.path` had never matched and
  which a disk scan can be pointed at by hand. Disk's trash loop, the duplicate
  search's unreadable files and a missing flag-artwork bundle now log at all,
  having been silent.

### Fixed
- **Two hotkey recorders could be armed at once.** A page can hold more than
  one and the keyboard page has since 0.7.1; a mouse click is not a key press,
  so arming the second never disarmed the first. One keystroke landed in both,
  or a monitor sat swallowing every keypress in the window with nothing on
  screen to say so.
- **Double-clicking a file in the disk list did nothing** — the primary
  gesture on the primary surface, no action and no feedback. It reveals the
  file in Finder, which is what "open" means for a file.
- One oversized failure could erase the log it was written to: `helm.log`
  rotates at 2 MB keeping one previous file, and a message went in at any
  length. Messages are capped, and the characters a *reader* obeys — a lone
  carriage return, U+2028/9, the bidi overrides that reverse everything after
  them in a pasted bug report — are neutralised along with the line breaks.

## [0.7.1] — 2026-07-26

### Added
- **Layout** — a seventh module. It notices a word typed in the wrong keyboard
  layout, rewrites it and moves the input source with it, and it can be undone.
  A word is only converted when it is not a word as typed **and** is one once
  swapped; a word that is valid as typed is never touched. Terminals and
  password managers are refused before the dictionary is consulted, secure input
  suspends it, and nothing typed reaches the log or the disk. Needs
  Accessibility, and says so where it is switched on rather than appearing to
  work.

  Four methods studied from open-source implementations (no code taken), each in
  one place: the tap is listen-only so it can neither delay nor swallow a
  keystroke; replacement is synthesised Unicode rather than the clipboard, which
  fails in Electron and VS Code and destroys what the user had copied;
  translation goes through `UCKeyTranslate` against the layouts actually
  installed; and Helm's own events carry a marker and are dropped on the way in,
  or the tap reads its replacement back as typing forever.
- **A duplicate finder inside Disk** — the second look. It walks the folder the
  ring is focused on, nominates candidates by size (1 MB floor), thins them
  with a 128 KB prefix hash and confirms with a full SHA-256, so distinct
  files are never read in full. Hard links are collapsed by inode before
  grouping — two names for one file free nothing when deleted, so they are
  never offered. One copy per group is marked as staying; extras go to the
  basket and deletion runs through the engine's removal scope like every
  other Disk deletion. Cancelling returns no answer rather than a partial
  one presented as complete. Hashing runs across size groups in parallel —
  a real home directory measures ~70 GB of worst-case full-hash volume, which
  single-threaded is the difference between a moment and a wait — the walk
  stays on the root's volume rather than descending into mounted drives, and
  progress is throttled to 0.35 s the way the disk scan's partials are.
- The keyboard module can put its own input-source indicator in the menu bar,
  with the choices the system's one does not offer: letters, letters filled,
  letters outlined, or a flag, at the same sizes the app icon
  uses, and a menu that lists the installed layouts. Off by default, because
  macOS still shows its own. A flag appears only where the input source itself
  names a region — a language is not a country.
- **A real flag for every layout.** Helm drew them itself for a while — a
  table of bands, crosses, cantons and emblems — and it reached fifty regions
  before the model ran out: an eagle, an armillary sphere and a set of
  trigrams are not shapes a table holds, and half a dozen flags were
  approximations because of it. The artwork now comes from **flag-icons**
  under the MIT licence (`NOTICE.md`, credited on the About page), rendered
  from its 4:3 SVGs at authoring time by `Scripts/flags/fetch-flags.sh`.
  Rendering happens through WebKit, not `NSImage`: `NSImage`'s SVG support
  does not resolve `<use xlink:href>`, and China's stars are defined that way
  — CoreSVG drew a plain red rectangle and reported success. A layout that
  names no country still keeps its letters in a frame. `package-app.sh` now
  copies SwiftPM resource bundles into the app and fails loudly if there are
  none: without them `Bundle.module` finds nothing and every flag would
  quietly become letters.
- **One key for both fixes.** Right ⌘, ⌥, ⌃ or ⇧, pressed and released on its
  own: the first tap fixes the last word, the next puts it back. Two shortcuts
  for "fix this" and "no, put it back" are two things to remember for one
  thought. The key keeps working as a modifier — a tap only counts when nothing
  else happened with it, so ⌘S is still ⌘S, holding it is not a tap, and a
  second modifier before or after cancels it. Only right-hand keys are offered,
  so the twin on the other side is untouched whatever you bind. Off by default;
  the two separate shortcuts are still there for anyone who prefers them.
- An optional sound when a word is fixed, and a "never this word" button beside
  the last change.

### Changed
- The slower update channel is Beta, not Stable: Helm is before 1.0 and nothing
  shipped has earned the word. The About page carries a BETA badge for the same
  reason, and a stored `"stable"` preference reads as beta rather than resetting.
- Wording pass across the keyboard module after a localization review: the
  triggers say which key they mean, the badge styles describe the badge rather
  than the letters, the state metric answers on one scale in all eight languages
  (it read "yes" in three of them), and the shortcut button says Set rather than
  Record, which means audio recording in four.

### Fixed
- **The icon shape and size previews were invisible in the light theme.** They
  are `NSImage`s drawn with `lockFocus`, which bakes `labelColor` against
  whatever `NSAppearance.current` happened to be — and inside a SwiftUI body
  nothing sets that, so a light window got white glyphs on a white card. The
  neutral ones are drawn as templates and tinted by `foregroundStyle` now; the
  keyboard badge previews, which have the same shape of defect through a lazy
  drawing handler, are rasterized in the view's appearance via a new
  `HelmAppearance` helper.
- **An unreadable file could be reported as a duplicate.** Hashing broke out of
  its read loop on failure and returned the digest of whatever it had — for a
  first-slice failure, the digest of nothing, which is identical for every such
  file. Two same-size unreadable files (iCloud-evicted, a dying disk, truncated
  between the walk and the hash) grouped as duplicates and the sheet offered to
  trash content nobody had read. Short reads answer nothing now and leave the
  running, which is what the module claims everywhere else.
- A modifier already held when the bound key went down produced no event inside
  the tap's window, so the machine could not know about it and a chord fired as
  a tap. The plumbing reads the live flags at press time.
- The VPN engine seeded its running-app state on the calling thread while the
  reload it had just enqueued wrote the same object on its work queue — the
  same unsynchronised shape as the crash `RunningApps` was written for.
- **Corner rounding was thrown away by two flags.** `setClip()` replaces the
  clip instead of intersecting it, so the Union Jack and the taegeuk squared
  off the badge — GB and AU were the two flags in the set with different
  corners. Found by a pixel test that reads the corners; the existing opacity
  test sampled the middle column, where every flag is opaque by design.
- **A `..` in a path walked straight through the deletion gate.**
  `DiskSafety.isRemovable` ran string prefix tests on the raw path, so
  `~/Documents/..` was not the home directory as a string while `trashItem`
  resolves it to exactly that. It standardizes the path first now, as
  `RemovableScope` already did for the other modules.
- Layout cleared two of the three places a word lives when secure input turned
  on. The third could later be typed back by the shortcut into whatever field
  was focused.
- Keep Awake dropped its workspace observer tokens, so switching the module off
  and on stacked another pair of callbacks each time.
- **A crash.** `NSWorkspace.runningApplications` is main-thread-only, and the VPN
  engine read it from its own serial queue. AppKit copies that list under a lock
  while the main thread mutates it, so an application quitting at the wrong
  instant took the process down inside `_cow_copy`. `RunningApps` now refreshes
  on the main thread and every other thread reads a snapshot; Keep Awake's
  identical read goes through the same door.
- After an update, Helm checks every permission its enabled modules declare
  rather than only Full Disk Access — which no module declared, because
  `ModulePermission` had no case for it, so the one thing being checked was
  attributed to nobody. Each thing that stopped working is named, with a button
  to the pane that fixes it.
- `VPNEngine` was the one engine with no background bridge. `scutil` is a
  subprocess, and a connect polls it up to 25 times through
  `DispatchQueue.main.asyncAfter`, so one connect could stall the main thread
  for over two seconds in slices; `activate()` shelled out at launch before the
  window existed, and auto-connect ran from AppKit's running-applications
  notification straight into a synchronous keychain read that can raise a modal
  panel. All of it goes through an injected work queue now.
- The same class carried `@unchecked Sendable` with no synchronisation while
  `connections` was written from the transport handler, the poll and the
  application observer. `KeepAwakeEngine` had the mirror image: every observer
  that writes its state delivers on main and only the command handler arrived on
  a concurrency pool. `LocalTransport.setHandler` wrote the one field its class
  did not guard.
- `ModuleViewModel` — the type every module is handed — published five values
  and decoded a `state` payload of one shape, and that shape was Keep Awake's.
  VPN emits an event of the same name with a different shape, so the decoder
  failed on every poll and left all five at their defaults forever; five modules
  of six carried five dead `@Published` properties. Keep Awake has its own view
  model; the status item follows a publisher the descriptor supplies.
- Eleven icon-only controls had no accessibility name: `.help()` fills the hint,
  not the name, so VoiceOver read them all as "button". Collapsed disclosures
  stayed in the accessibility tree, so the panel read out its utilities list and
  Keep Awake its automation block while both were shut.
- The shortcut recorder's key monitor swallowed Escape and Tab, so a recording
  started from the keyboard could only be left with the mouse. The icon shape,
  icon size and both colour pickers were `onTapGesture` — no button trait, no
  focus, no keyboard path — and the swatches' only name was
  `rawValue.capitalized`, the one user-visible string that skipped `L()`.
- `HelmApp` declared a direct dependency on all six engines and imported one of
  them without using a symbol from it.
- Opening App Uninstaller took 4.0 s warm and 9.4 s cold, on every visit,
  because listing apps measured each bundle — a full walk per app, 3.2 s for
  Xcode alone. Listing without sizes is 10 ms; the sizes arrive behind the list,
  measured concurrently. `ScanResult.appSizeBytes` walked every bundle a second
  time at a median 49 ms each and was never read by anything.
- Five `Process` wrappers become one. `waitUntilExit()` polls a run loop in
  50 ms steps, so every shell call paid about 67 ms whether or not the child had
  finished — 70.6 ms for `/usr/bin/true` against 1.3 ms for a bare spawn. Two of
  the five also waited before reading the pipe, which deadlocks on any output
  past the buffer.
- The leftovers scan launched `systemextensionsctl` twice and parsed the same
  output twice: ~313 ms → ~110 ms.
- The disk cache is 7 MB and 42 000 nodes — 95 ms to decode, 81 ms to encode,
  both on the main actor. Both are detached now.
- `AppLanguage.current` read CFPreferences on every call and every string
  property is computed, so hovering a 200-row list hit it hundreds of times per
  frame; `HelmBytes` built a fresh `NumberFormatter` per size (14 µs of 16);
  `DiskSafety` asked for the home directory once per row per frame.
- A grouped `Form` caps its content at 704 pt and centres it, so above a 994 pt
  window its leading edge walked away from everything Helm draws itself — 36 pt
  at 1070, 181 pt at 1360 — while switching to a list screen shifted the content
  103 pt sideways. The forms are capped so the system stays on its constant-20
  branch, and the page header matches it.
- The "What's New" badge had a fixed width that wrapped half the languages onto
  a second line; the metric strip's captions measured 1.87:1 and a tinted figure
  2.03:1 in light appearance; Homebrew's bottom bar was 11 pt shorter than the
  two screens beside it; two of three empty states drew a bare glyph instead of
  `HelmIconPlate`; Homebrew marked 46 of 47 rows "formula".
- `DiskSafety` allowed every top-level directory of the boot volume, so a scan
  of `/` put `/Users` one click from the Trash. Nothing at the root of a volume
  is a file anyone means to delete; its contents still are.
- A `*` in `CFBundleIdentifier` turned every leftover glob into a
  match-everything pattern, and a glob is never `matchedByName`, so the results
  arrived pre-ticked: one app could offer up every container in `~/Library`. The
  empty-id case was closed earlier; this closes the class.
- A leading dot carried Apple's own domains past the skip list —
  `.com.apple.finder.plist` still splits into three components and then matches
  no prefix test.
- `RemovableScope` allowed the shared `~/Library` folders themselves. The gate
  that exists to survive a defect upstream must not be looser than the code it
  guards.
- `DiskEngine` dropped a refused path into neither list and then announced
  "Removed — N freed" over a file still sitting there.
- An extension's host was matched by prefix without a separator, so an installed
  `com.acme` marked `com.acmecorp.vpn.ext` as in use — and an empty id in the
  installed set marked every extension on the machine as in use.
- `LaunchAgentReader` cut `.plist` wherever it appeared:
  `com.vendor.plistwatcher.plist` became `com.vendorwatcher`, an identifier that
  matched no installed app and that `launchctl disable` would aim elsewhere.
- `make-dmg.sh` staged through `build/`, inside the synced checkout, so the dmg
  shipped a bundle `codesign` rejects while the zip beside it was fine. It
  stages in `TMPDIR` and verifies the seal before packing.
- `isSudoersInstalled` read a file installed 0440 root:wheel and so answered
  "not installed" every time: the admin prompt returned every session, and the
  removal added alongside it could never run.
- The sudoers rule staged at a fixed path, and the privileged read happens after
  the password prompt — an unbounded window for anything already running as this
  user to rewrite it. Each attempt gets its own 0700 directory.
- The VPN credential purge marked itself done before doing anything; at login the
  keychain can still be locked, which would have left the readable item forever.
- `helm.log` still held every line written before redaction existed, next to a
  button whose purpose is pasting it into a bug report. Discarded once.
- Turning the Disk module off and on left its cached view model talking to a
  deallocated engine: every request answered empty, with no error, until restart.
- A rescan cleared the whole selection, so switching one login item off threw
  away every other tick.
- "Last checked" was stamped before the check ran, and a manual check never moved
  it at all.
- Keep Awake counted `manual` and `timer` among the automatic rules, and the
  countdown on the settings page had no tick of its own.
- The menu-bar button had no accessibility label — the only entrance to the app
  was an unnamed button among twenty others.
- Reduce Motion was honoured nowhere, including a bezel that rotates forever.
- The last hand-rolled badge sat on the screen shown after every update, drawing
  orange text on orange fill at about 1.6:1.
- Full Disk Access and Accessibility are named as macOS 26 names them in ru, de,
  es and zh: Helm was sending people to look for a row that does not exist.
- Eight German strings had slipped into "Sie"; macOS speaks du.
- The leftovers matcher pasted a bundle id or display name straight onto a
  shared `~/Library` folder. An empty `CFBundleDisplayName` — a free-form plist
  string — therefore claimed `Application Support` itself, an empty id collapsed
  every glob to `*`, and a name carrying `..` walked out of the folder entirely;
  all three arrived pre-ticked next to a Trash button. Candidates are now
  refused unless they sit strictly inside their own kind folder, and both
  engines re-check the scope before removing anything, rather than trusting the
  view model that built the list.
- Leftovers matched by display name are no longer pre-selected and carry a "by
  name" badge; a guess costs a click to accept instead of a click to refuse.
- The Keep Awake clamshell rule was written into `/etc/sudoers.d` through an
  AppleScript-quoted shell string built from the account name, was never checked
  with `visudo`, and was never removed. It is now staged from Swift, validated,
  installed with `install(1)`, and taken back out when the option is switched
  off.
- `helm.log` recorded VPN connection names, app names and absolute home paths.
  It uses stable short tags and `~`-relative paths now.
- Quitting an app disconnected whatever VPN its rule pointed at *now*, so a quit
  with no matching launch, a repeated quit, or a rule remapped under a running
  app tore down a connection Helm never raised.
- `brew search` no longer prints its `==> Casks` header, so every cask was
  labelled a formula and installed without `--cask`. Helm asks one kind at a
  time.
- An extension host was matched by prefix without a separator, blaming
  `at.obdev.littlesnitch`'s extension on `at.obdev.littlesnitchmini` and hiding
  the real reason.
- An incomplete IOKit power dictionary was reported as 0%, which the battery
  guard read as a critical charge and used to end the Keep Awake session.
- `package-app.sh` signed the bundle inside the repo, where a file provider
  re-stamps `com.apple.FinderInfo` faster than `xattr -c` clears it: signing
  succeeded or failed by luck, and an unsigned bundle has no cdhash for TCC to
  bind Full Disk Access to. The bundle is now assembled and signed outside the
  synced tree, and the signature is verified before the script reports success.
- The Homebrew installer ran as `eval "$(curl …)"`, which exits 0 on a failed
  download and reported a successful install of nothing.
- The disk confirmation listed localized folder names, which cannot tell
  `/Library` from `~/Library`; it lists paths. The scan cache directory is
  created 0700.
- Three screens announced "Removed — N freed" whether or not macOS had refused,
  and threw the failure list away. `HelmRemovalOutcome` names what stayed and
  why, with a way to reveal it and to grant the missing permission.
- "Select all" in Login Items & Extensions ticked rows hidden by the filter,
  and the counter counted them too; both now follow what is on screen, and
  hiding a kind drops its selections.
- The Disk Space basket was a count with no list: its contents can be opened
  and cleared item by item, and the confirmation names what it is about to
  remove.
- Homebrew removed a package — a whole app, for a cask — on a single click.
  It asks first, like every other destructive action in Helm.
- The permission notice was shown once ever: the "already shown" flag was set
  before the check, so a first launch that happened to have access silenced it
  for good. It is keyed to the version now, which is what an ad-hoc build
  needs, and every page re-reads permissions when Helm returns to the front.
- A VPN rule naming a connection that no longer exists says so instead of
  silently never firing.
- The icon menu listed disabled modules, whose pages only say they are disabled.
- Opening the Uninstaller sized every installed bundle — nine seconds of disk
  walking on this Mac — and the leftovers scan paid it again for data it threw
  away; it asks for bundle ids only.

### Added
- Each item in Login Items & Extensions offers what the system actually allows:
  turn off (any non-Apple agent), delete (only where the folder is writable —
  the user's own Library, not /Library), reveal, or a link to System Settings
  for extensions. Deleting something in use asks first and says the app may
  recreate it.
- Login items can be turned off rather than only deleted, through launchd's own
  disabled list (`launchctl disable gui/<uid>`) — no files are moved, the state
  survives reboots, needs no admin, and System Settings shows the same thing.
  Offered only for user-domain agents that are not Apple's.
- A kind filter in Login Items & Extensions, so system extensions (or anything
  else) can be hidden while reviewing.
- Login Items & Extensions lists system extensions themselves, with the status
  their host app implies. They are never selectable: Helm cannot remove an
  extension by moving a file, so the row opens the system pane instead.
- Keep Awake's per-app rules take conditions: an app can hold the Mac awake
  always, or only with an external display, only on power, or both. Existing
  app lists migrate to unconditional rules.
- `PermissionNeed` maps each gated feature to the grant it needs. The settings
  section is generated from it, and Disk Space, App Uninstaller and Login Items
  & Extensions warn in place when Full Disk Access is missing, the way Keep
  Awake does for the pointer nudge.

### Removed
- `module.app.panelLayout`, left in defaults by the removed grid layout, is
  purged at launch.
- Dead code: an unused centred-message modifier, the `contentFade` motion token,
  the scanner's superseded ResultBox, an Apple-bundle check the vendor rule
  replaced, and the About page's now-unused opener.

### Fixed
- The Uninstaller's leftovers scan listed the files of installed apps, with
  everything pre-selected. It decided "installed" from a listing of
  /Applications, which sees neither apps one folder down (Adobe Acrobat DC/)
  nor helpers nested inside other bundles (OneDrive.app carries the SharePoint
  helper). It now asks LaunchServices, and nothing is pre-selected: on this
  machine 112 entries belonged to apps the system does find.
- Keep Awake's status strip was static: the page held its view model in a plain
  property, so SwiftUI never saw the published state change and the figures
  froze at whatever they were when the page opened.
- "Leftovers" filters by status rather than by what Helm can delete, so an
  extension whose app is gone appears there too.
- Accessibility is now listed among the permissions, and Keep Awake flags it at
  the pointer-nudge setting. macOS drops synthetic mouse events from an
  untrusted app, so that switch could be on while nothing moved, with nothing
  in the app saying why.
- The module order is applied everywhere it should be. The sidebar and the
  icon's menu listed modules in registry order while the panel and the settings
  list used the arranged one; the sidebar now sorts each category by the same
  order. The setting is renamed to "Module order" to say so.
- An abandoned drag no longer strands the settings list. The order was written
  back only in `performDrop`, which never fires for a drag released outside the
  list — so the list kept showing an order nothing else knew about, and the
  dragged row stayed dimmed. The order is now persisted as it moves, and
  reopening the page re-reads it.

### Changed
- Per-app rules are one row each — the app, one menu for when the rule applies,
  and the remove button — in both Keep Awake and VPN. The two switches they
  replace were never independent: "display and power" means both, and a VPN
  rule with neither switch on does nothing, which the menu can now say.
- The system-extension count left the Permissions section. It was neither a
  permission nor Helm's, and a bare number could not tell you which app it
  meant; the module named after extensions lists them by name instead.
- Settings sections follow how often they are needed: general, module order,
  menu-bar icon and panel first; permissions and diagnostics last. They used to
  sit in the reverse order, with troubleshooting above appearance.
- Keep Awake gathers all four automatic rules — external display, power, closed
  lid, low battery — into one Automation section; they were spread across three
  sections with unrelated ones between them. The global shortcut, set once,
  moved to the end.
- One container treatment across the app. Helm's own cards dropped their border
  to match the macOS grouped-form sections that make up half the app's
  surfaces — the About page had been showing a bordered card and an unbordered
  one side by side.
- A module's metric strip now sits inside the form as its first section, so it
  shares the system's width instead of overhanging the rows below it at the
  window's own margin.

## [0.7.0] — 2026-07-26

### Added
- **Disk Space module** — a sunburst ring showing what filled the disk. Scans a
  whole volume or any folder with `getattrlistbulk` and a parallel walk (a
  310 GB volume in about a minute), draws the ring while the scan is still
  running, and drills in by clicking a wedge. Folders carry the names Finder
  gives them in the user's language. Anything to remove collects in one list
  and goes to the Trash together, and system paths can never be collected.
- **Disk Space recommendations** — known cache folders past 100 MB, Downloads
  items untouched for a month, and files over 1 GB untouched for half a year,
  ranked by size behind one toolbar button.
- **Disk Space remembers the last scan** — the tree is written to Application
  Support and restored on open, labelled with when it was measured; deleting
  updates the tree in place instead of re-walking the disk.
- **Login Items & Extensions module** — everything that loads with the Mac,
  marked in use, system, or leftover. Only leftovers can be selected.
- **App Uninstaller: two-step flow** — tick the apps, then review the files
  found for each before anything moves. Running apps are flagged and removed
  only with an explicit force quit.
- **Permissions section** — whether Helm has Full Disk Access, plus installed
  system extensions read from `systemextensionsctl`. When a file cannot be
  moved, Helm names the real reason and links to the right setting.
- **Module reordering** — drag modules into the order they take in the panel.
- **Diagnostics** — an optional log of what Helm does, reachable from Settings.
  Dev builds always log.
- Update channels (Stable / Dev), and a dev-first release flow: see
  [VERSIONING.md](VERSIONING.md).

### Changed
- Every screen leads with its icon and its own key figures, on one layout.
- Sizes are formatted once for the whole app: 1000 to the kilobyte as Finder
  counts, and in the user's own units — "432,95 ГБ", not "432,95 GB".
- Counted nouns follow each language's rules, including Russian's three forms.
- Wording reviewed across all 334 strings: shorter labels, one name per thing,
  duplicate labels split apart, explanations cut to their point.

### Fixed
- VPN rows no longer spin forever; the status is polled until it settles.
- Uninstalling reports what actually happened: real failure reasons instead of
  guesses, no duplicate paths queued twice, and Reveal falls back to the
  enclosing folder when the item is already gone.
- The Settings window no longer stretches to the height of the screen.
- Sections no longer flicker when a disclosure finishes opening.

## [0.6.3] — 2026-07-25

### Changed
- Redesigned About: the icon sits in a bezel that turns while updates are
  checked, version and build read as instrument dials, and the update controls
  live in one card.

### Fixed
- The update status no longer claims you are current when no check has run — it
  shows when the last check happened.

## [0.6.2] — 2026-07-25

### Added
- Update channels: stay on finished releases, or switch to Dev in About to get
  early builds.

## [0.6.1] — 2026-07-25

### Fixed
- VPN rows no longer show an endless spinner: the status is re-checked until the
  connection settles.

## [0.6.0] — 2026-07-25

### Added
- **App Uninstaller module** — list installed apps, scan their leftovers
  (caches, preferences, containers, logs, …) by bundle id and exact name, and
  move everything to the Trash; a Leftovers tab finds files from apps that are
  already gone. User-domain only, always reversible.
- **Homebrew module** — installed formulae and casks with one-line
  descriptions, updates with per-package and bulk upgrade, search and install,
  a live console for long operations, and an in-app Homebrew installer for
  machines without brew.
- **Menu-bar timer** — while a timer runs the ring empties clockwise, with an
  optional remaining-time label and a dedicated timer colour.
- **Panel** — utility modules collapse behind an animated Utilities row;
  optional Settings/Quit buttons; the icon's right-click menu jumps straight to
  any module's settings page.
- In-app changelog is now structured, localized in all eight languages, and
  badged New/Upd/Fix.

### Changed
- Keep Awake's ⋯ controls open inline in the card (custom timer with a
  durations menu and free-form entry, automation toggles, Stop button in the
  countdown row); the module toggle turns orange while an automation rule is
  holding the session.
- Settings window: the app pane is now Settings; utility pages get a larger
  window; module lists use the macOS 26 inset style; copy reviewed in all
  languages.
- Store writes now announce themselves, keeping the panel and the Settings
  window in sync in both directions.

### Fixed
- The panel no longer jumps or slides when disclosures open (window is sized
  once per open; content animates inside it).
- The menu-bar countdown ticks reliably (state was read before it landed).
- brew calls and filesystem scans no longer stall the app's async machinery.
- The updater's retry button works after a failed install.

## [0.5.1] — 2026-07-24

### Fixed
- Silent update now cleans up its temp files (downloaded zip, unzipped bundle,
  swap script) after installing, leaving nothing behind.

## [0.5.0] — 2026-07-24

### Added
- **Silent in-app updates** — "Update & Relaunch" downloads the new version,
  installs it into place, and relaunches, with no manual drag and no Gatekeeper
  prompt (the app downloads the release zip itself, so it isn't quarantined).

## [0.4.0] — 2026-07-24

### Added
- **Custom active icon for Keep Awake** — Settings → Keep Awake → Active icon lets
  you pick a shape shown in the menu bar (in the active tint) while Keep Awake is on.

### Changed
- **Reworked menu-bar icon pickers** — glyph-forward swatches with the selected
  option's name below the row; the size picker previews each shape at its real size.
  Preview glyphs are now theme-neutral (match the menu-bar icon) instead of blue.
- **Icon sizes** are now Tiny/Very small/Small/Medium/Large (9–18pt): dropped the
  largest sizes, added smaller ones, and replaced XS/S/M codes with words.

### Removed
- The "Helm" (ship's wheel) menu-bar glyph.

## [0.3.0] — 2026-07-24

### Changed
- **Update check moved into About** — the version status and "Check for Updates"
  button now live in Settings → About, next to the version, instead of a separate
  section under General.

### Fixed
- **Panel toggle stuck off while a module was active.** A module that turned on
  automatically at launch (e.g. Keep Awake on power) held correctly but its panel
  toggle read off, because the view model subscribed to the engine's event stream
  after the initial state was emitted. The transport now replays the last state to
  late subscribers.

## [0.2.0] — 2026-07-24

### Added
- **GitHub updates** — Helm checks the public repo's latest release once a day
  and from Settings → General → Updates, surfacing a download link when a newer
  version is out.
- **What's New** — About → "What's New" renders this changelog in-app; About now
  shows the version, build number, and enabled-module count.

## [0.1.0] — 2026-07-23

### Added
- **Keep Awake module** — prevent sleep manually, by timer (presets + custom
  minutes with a live countdown), or automatically when an external display or
  power is connected, or when chosen apps run. Optional "keep display on",
  pointer jiggle, closed-lid (clamshell) mode via `pmset`, battery guard, a
  global toggle hotkey, and a configurable menu-bar tint color.
- **VPN module** — connect/disconnect system VPNs (`scutil`), per-app
  auto-connect rules, and silent L2TP/IPSec connect via a one-time keychain
  read cached in Helm's own keychain.
- **Menu-bar panel** — Control Center-style, per-module tiles, screen-edge
  clamping, quick automation toggles in a popover.
- **Settings** — System Settings-style window (AppKit split view), per-module
  enable switches, menu-bar icon shape/size, launch at login.
- **Liquid Glass app icon** built with Icon Composer.
- **Localization** — English, 中文, Español, Français, Deutsch, 日本語,
  Русский, Português.

[0.6.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.6.0
[0.5.1]: https://github.com/rstrlnkv/Helm/releases/tag/v0.5.1
[0.5.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.5.0
[0.4.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.4.0
[0.3.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.3.0
[0.2.0]: https://github.com/rstrlnkv/Helm/releases/tag/v0.2.0
[0.1.0]: https://github.com/rstrlnkv/Helm
