# The third all-agent pass — 2026-07-29

Eleven reviewers over 0.7.2-dev.34 at `8e97d42`: architecture, product critique, innovation,
adversarial testing, performance, security, visual design, interaction and copy, accessibility,
localization, and a dead-code hunt. Baseline before any of them touched the tree: **1218 tests,
0 failures, 6 skipped, working tree clean.**

Everything below was **re-checked by hand** before it was written down. The previous pass taught
that agents are right often enough to be worth running and wrong often enough to be worth
checking — this time two reports were corrected (see *Corrections* at the end).

Order is by what it costs the user, not by how interesting it is. The tiers are meant to be
cut from the bottom: tier 0 alone is a defensible release, tier 0+1 is the one to aim for.

---

## Tier 0 — defects the user can hit today

Each of these is small. Six of them already have a failing test written.

### 0.1 The events task retains its view model forever — `dropWhenDisabled` frees nothing

**Done** — `ebd38c1`, 2026-07-29. Stream captured outside the loop, `self` re-acquired per event,
every view model cancels its task on the way out; `LocalTransport.subscriberCount` pins the
regression as a count that must not grow. ARCHITECTURE.md § Memory updated.

`Sources/HelmContract/LocalTransport.swift:34-46` and six view models
(`VPNViewModel.swift:14`, `KeepAwakeViewModel.swift:42`, `LayoutViewModel.swift:26`,
`HomebrewViewModel.swift:48`, `DiskViewModel.swift:108`, `DuplicatesViewModel.swift:35`).

Every one of them starts its event loop as `Task { [weak self] in await self?.observeEvents() }`.
The weak capture resolves **once**, on entry; `observeEvents()` is an instance method whose
`for await` never returns, because `LocalTransport` never calls `.finish()`. So the running task
holds a strong `self` for the life of the app.

Two consequences, both proven rather than argued:

- `ModuleUICache.dropWhenDisabled` — shipped in dev.29 *to fix the 48 GB incident* — drops the
  cache reference and frees nothing. ARCHITECTURE.md § Memory's claim that it "hands the pages
  back" is false once the page has been visited.
- `DuplicatesViewModel`'s `deinit { eventsTask?.cancel() }` (`:38`) is unreachable code. `deinit`
  cannot run while the object retains itself, so the cancel it contains never executes.

Duplicates is worst: its page is a plain `@StateObject`, so it leaks a whole view model per
sidebar visit rather than per module disable.

**Do:** cancellation has to come from *outside* the object — an explicit `stop()` that
`dropWhenDisabled` calls before releasing the reference. Check first whether `Task.cancel()`
alone unblocks the `for await`; `onTermination` should fire on consumer cancellation, which
would make this small.
**Pinned by:** `Tests/Modules/{Disk,Duplicates}/UITests/EventsTaskRetainTests.swift` — both red today.
**Risk:** low-medium. It changes lifetime, so re-measure with `HelmLog.memory` after.

### 0.2 `ReleaseDigest.sha256` has the same unfixed hash-loop defect

**Done** — `ebd38c1`, 2026-07-29. Pool moved inside the `while`; the footprint test is a gate now
instead of a report. ARCHITECTURE.md § Memory and CLAUDE.md both updated (a report-only test is
not a regression guard).

`Sources/HelmRuntime/ReleaseDigest.swift:54` — `while let chunk = try handle.read(upToCount: 1 << 20)`
with no `autoreleasepool`, and unlike `DuplicateScanner.hash` it is not even inside
`concurrentPerform`, so it leaks on a plain serial call. Measured in-repo: **1204 MB of growth
hashing a 1200 MB file; 1.0 MB with a pool.** It runs on every silent-update digest check.

This is the only place in the codebase currently violating CLAUDE.md's own autoreleasepool rule.

**Do:** the pool goes *inside* the `while`. **Risk:** none. **Pinned by:**
`Tests/HelmRuntimeTests/ReleaseDigestFootprintTests.swift`.

### 0.3 Quit leaves `pmset disablesleep 1` set, system-wide

**Done** — `ebd38c1`, 2026-07-29. `applicationWillTerminate` now calls `deactivate()` on every
live engine.

`Sources/HelmApp/AppDelegate.swift:84-86` only writes a log line. What disengages clamshell is
`KeepAwakeEngine.deactivate()` (`:83-100`), and nothing calls it on quit. The recovery exists —
but only in `activate()` (`:66-73`), i.e. on the *next launch of Helm*. Quit during a clamshell
session and the Mac cannot sleep until Helm is launched again. Delete Helm while it is set and
the setting, and the `/etc/sudoers.d` rule, outlive the app.

**Do:** `applicationWillTerminate` deactivates every live engine. That fixes the class, not the
instance — assertions, observers and the event tap are all released the same way.
**Watch:** `disengageClamshell` shells out on the terminate path (`sudo -n`, non-interactive, so
it is fast) — measure it.
**Verify:** enable the lid option, start a session, Quit, `pmset -g | grep SleepDisabled` reads 0.

### 0.4 VPN talks to a dead engine after the module is switched off and on

**Done** — `ebd38c1`, 2026-07-29. `VPNDescriptor` now caches `(vm: ModuleViewModel, model:
VPNViewModel)` and checks identity, the same shape `KeepAwakeViewModel.shared(vm:)` has.

`Sources/Modules/VPN/UI/VPNDescriptor.swift:15,27-32` — `cachedVM` is returned regardless of the
host view model it was handed. `ModuleHost.enable` (`ModuleHost.swift:45-53`) builds a new engine
and a new `ModuleViewModel` every time, so the cached `VPNViewModel` keeps the dead transport,
whose handler is `[weak self]` and answers every command with empty `Data`. The panel tile and the
settings page come back frozen, silently, until restart. VPN is also the only cached view model
that never registers `ModuleUICache.dropWhenDisabled`.

This is the same defect `DiskViewModel.shared(vm:)` documents at `:84-90` and fixed there. It
survived in VPN because the commit that fixed KeepAwake cited *VPN* as the exemplar to copy.

**Do:** the identity check `KeepAwakeViewModel.shared(vm:)` already has. **Risk:** low — the only
path that changes behaviour is the one that is broken.

### 0.5 The keyboard gesture converts a word the caret has already left

**Done** — `ebd38c1`, 2026-07-29. `.navigation` and `.chord` are both asked the same question,
once, off the event itself; `GestureAfterNavigationTests` is green.

`Sources/Modules/Layout/Engine/LayoutEngine.swift:210`. `handle()` clears `lastCompleted` for
`.click` and `.focusChange`; `.navigation` falls into `default` and *stores* the word the arrow
key just ended. Type `ghbdtn`, press ←, tap the bound modifier: six backspaces and `привет` typed
wherever the caret now is.

The undo half of this was fixed (`:196-199`); the convert half was left open, though
`RememberedWord`'s own doc claims it makes "the same check" `UndoRecord` does.

**Pinned by:** `GestureAfterNavigationTests`. **Risk:** low, and the window is one event wide.

### 0.6 An Autopilot rename rule renames the same file every hour on exFAT

**Done** — `ebd38c1`, 2026-07-29. `RenameShape` added; `RenameIdempotenceTests` (5 cases) green.
Autopilot has not shipped to a stable release yet, so this fix has no CHANGELOG.md/ChangelogData
user-facing entry — see the third-pass documentation report for why.

`Sources/Modules/Autopilot/Engine/RuleRunner.swift:114`. Tolerating a stamp that will not stick
(`:96` names exFAT) leans on "re-runs an idempotent action on an unchanged file" (`:75`) — but
rename is not idempotent. The only guard is `target.path != url.path`, which catches the bare
`{name}` pattern and nothing else: `{date}-{name}` feeds the previous run's output back into
`{name}`, producing 24 names a day, a 274-character component, and then a `moveItem` that throws
forever. Also hits `{name} {date}`, `{name}{counter}`, `scan-{name}`, `{name}-copy`.

**Pinned by:** `RenameIdempotenceTests` (5 cases, one through the real runner on a real folder).

### 0.7 Keep Awake: stacked password prompts, and an orphaned sudoers rule

**Done for the two cases pinned by the test** — `ebd38c1`, 2026-07-29. `sudoersInstallInFlight`
guards the double prompt; `sudoersInstallFinished(granted:)` calls `releaseSudoersIfUnneeded()`
once the prompt resolves, closing the "clamshell toggled off while the prompt is up" case.

**Still open, found during verification of this fix and not covered by any test:** the completion
handler captures `[weak self]`, so if the whole module is switched off (not just the clamshell
setting) while the prompt is on screen, `deactivate()` tears the engine down, `self` is `nil` by
the time `installSudoers`'s callback fires, and `sudoersInstallFinished` — the only place that now
calls `releaseSudoersIfUnneeded()` — never runs. A person who types their password after disabling
the module is left with a passwordless-sudo rule and no live engine to ever remove it. Needs its
own fact the same shape as `sudoersInstallInFlight`, held somewhere that survives the engine (or a
`deactivate()` that waits for or cancels the in-flight prompt before tearing down).

`Sources/Modules/KeepAwake/Engine/KeepAwakeEngine.swift:276` and `:297`. One missing fact causes
both: "an install is in flight" is state the engine keeps nowhere, and the file the question is
about does not exist until the password is typed.

- `isSudoersInstalled()` is still false while the first prompt is up, so any stop/start of the
  session — or *any* settings change — launches a second `osascript … with administrator
  privileges`. Two dialogs for one decision, both writing the same staging file.
- Turn clamshell off while the prompt is up, then type the password:
  `releaseSudoersIfUnneeded` already looked and saw no file, `reallyEngageClamshell` correctly
  declines, and `/etc/sudoers.d/helm-keepawake` stays forever — a passwordless-sudo rule for a
  feature that is off. Precisely what the method's own doc (`:290-296`) exists to prevent.

**Pinned by:** `SudoersPromptInFlightTests`, including a control that a *declined* prompt must
still be askable again.

### 0.8 Stop leaves the abandoned scan's folders in the basket, and credits them to the wrong disk

**Done** — `ebd38c1`, 2026-07-29. `StopLeavesNothingBehindTests` (2 cases) green.

`Sources/Modules/Disk/UI/DiskViewModel.swift:217`. `newScan()` and `rescan()` clear the basket;
`cancel()` — the Stop button — does not, and `newScan()` clears it *after* calling `cancel()`,
which is where the omission is legible. The basket bar is drawn outside `switch dvm.phase`
(`DiskSettingsPage.swift:35`), so the screen becomes the volume picker with a basket of a vanished
tree and a Trash button under it. Then `emptyBasket` (`:363`) adds the freed bytes to the *current*
volume's free space.

**Pinned by:** `StopLeavesNothingBehindTests` (2 cases, including the cross-volume credit).

### 0.9 The Uninstaller pre-ticks another application's data

**Done** — `ebd38c1`, 2026-07-29. `AppLister.installedPaths(forBundleID:)` added (default
implementation on the protocol; `WorkspaceAppLister` overrides it) and routed through both the
sibling check and the exact-candidate ownership check. `NestedSiblingTests` (3 cases) green.
ARCHITECTURE.md § Removal scope updated — this is a distinct gap from the glob-prefix bug fixed in
an earlier pass (already in CHANGELOG.md's 0.7.2 section); both are folded into one user-facing
line in ChangelogData.swift since a user should not read two near-identical bullets for one
release.

Three reviewers reached this from three directions; it is one seam.

- `UninstallerEngine.swift:73` answers "is this another installed app?" from `installedBundleIDs()`,
  which is `contentsOfDirectory` over four folders matching top-level `*.app`. `AppLister.isKnownToSystem`
  exists for exactly this gap and is wired into `scanOrphansSync` (`:135`) but **not** into `scanSync`.
  So an app in `/Applications/Adobe Acrobat DC/` is invisible, and its container, caches,
  Application Scripts, LaunchAgent and group container are all claimed. Because a glob hit is never
  `matchedByName`, `UninstallPlan.defaultSelection` arrives with them **pre-ticked**.
- `UninstallerEngine.swift:69-70` applies `LeftoverOwnership.claims` only when `c.isGlob`. The
  *exact* candidates — `Containers/<id>`, `Preferences/<id>.plist`, `HTTPStorages`, `WebKit`,
  `Cookies`, `Saved Application State` — go through nothing, so an app declaring someone else's
  bundle id gets that app's data pre-ticked.

**Pinned by:** `NestedSiblingTests` (3 cases, including the pre-ticked one).
**Do:** make `installedBundleIDs()` return id → `[bundle paths]` (it is already read once per
scan), use it for both questions, and route both modules through one installed-apps lister — see 1.5.

### 0.10 Chinese never gets the system folder names

**Done** — `ebd38c1`, 2026-07-29. `SystemFolderNames.systemDirectory` maps `"zh"` → `"zh_CN"`;
`SystemFolderNamesTests` loops all eight languages now. ARCHITECTURE.md § Localization updated.

`Sources/HelmRuntime/SystemFolderNames.swift:51` builds `<language>.lproj` from
`AppLanguage.zh.rawValue` = `"zh"`, and the system ships only `zh_CN.lproj`, `zh_TW.lproj` and
`zh_HK.lproj` — I listed the directory. The table never loads, so the Disk ring shows a Chinese
user `Applications` where Finder says 应用程序, and `Users` where it says 用户. Every other
language's lproj name happens to equal its raw value, which is why this survived.

The module's whole premise is that folders carry the names Finder gives them, and it is false in
exactly one of eight languages. `SystemFolderNamesTests.swift:49` tests Russian only — the
regression test has to loop all eight.

---

## Tier 1 — safety and truthfulness

### 1.1 Autopilot's rule set is attacker-writable, and the module is on by default

**Done** — `ebd38c1`, 2026-07-29. `RuleSeal` (HMAC, keyed from a secret in Helm's own keychain
item) added; `AutopilotSealTests`, `RuleSealTests` green. `WatchScope` left as wide as designed, per
the "do not narrow" instruction below. ARCHITECTURE.md § Autopilot updated with the fourth
guarantee and the corrected (now only-half-true) narrowness argument.

`module.autopilot.folders` is plain data in `~/Library/Preferences/com.helm.app.plist`;
`AutopilotEngine.folders` (`:65`) decodes it with no authenticity check, and `startSweepTimer`
re-reads it on every hourly tick (`:100`), so no relaunch is needed. `WatchScope` refuses
`~/Library` and **allows** `~/Desktop`, `~/Documents`, `~/Downloads` — the reviewer compiled it
unmodified and printed the truth table.

So any unsandboxed process running as the user, **holding no TCC grant of its own**, plants a
move-or-trash rule and borrows Helm's Full Disk Access, unattended, on a timer. `Rule.enabled` —
the flag behind "new rules ship off" — lives in the file the attacker wrote.

**Do:** HMAC the encoded folders with a key created once in Helm's own login keychain (the
`SecItemAdd` access-list treatment `KeychainCredentials.helmCacheWrite` already uses at
`VPN/Engine/SystemPorts.swift:152`); the getter returns `[]` on mismatch plus one `HelmLog.error`.
**Do not** narrow `WatchScope` — those are the folders people actually want sorted.

### 1.2 The removal gates judge the path as spelled; the trash follows symlinks

**Done** — `ebd38c1`, 2026-07-29. `PathCanonical.resolvingAncestors` added (new file), wired into
`RemovableScope` and `UserFileScope`; leaf deliberately left unresolved. `ScopeFollowsLinksTests`
green. ARCHITECTURE.md § Removal scope updated.

`RemovableScope.isRemovable` (`:50`) and `UserFileScope.isRemovable` (`:24`) use
`standardizedFileURL` / `standardizingPath`, which collapse `..` but do **not** resolve symlinks —
while the comment at `RemovableScope.swift:48` claims "Resolve first". `HelmTrash.trashItem`
(`:114`) does follow them: the reviewer measured trashing `root/link/keep.txt` and watched the
real file leave its directory.

Reachable through `LeftoversScanner.plugins()` (`:113`), which enumerates four `~/Library`
directories that do not exist on a stock install and can therefore be created as symlinks by any
user process. The same shape covers a TOCTOU swap of any enumerated ancestor between the scan and
the click.

The correct answer is already in this repo: `WatchScope.canonical` (`:85`) resolves the deepest
existing ancestor and puts the missing tail back, precisely because "the question is where a path
*leads*".

Checked and clean, so nobody re-checks: `DiskScanner` skips `VLNK` (`:305`), and
`FileManager.enumerator` neither descends symlinked directories nor reports them as regular files.

### 1.3 `Redact` does not redact

**Done** — `ebd38c1`, 2026-07-29. Per-install 16-byte salt in a `0600` file beside the log,
mixed into the FNV-1a loop; `RedactSaltTests` green. ARCHITECTURE.md § Diagnostics log updated.
The related `LogRoot.swift:31` `~`-rooted scan-root name was **not** addressed by either commit —
still open.

`Redact.tag` (`:42`) is **unsalted** FNV-1a truncated to 16 bits, over values drawn from small
public dictionaries: bundle ids, VPN provider names, Homebrew formulae. The reviewer inverted it
against the 104 bundle ids on this Mac: **104 of 104 tags resolve to exactly one application.**
ARCHITECTURE.md § Diagnostics log claims this is what `Redact` prevents. It does not — and the
log is a thing the user is invited to paste into an issue.

**Do:** a per-install random salt in a `0600` file beside the log (or the keychain), mixed in
before the FNV loop. Cross-restart comparison — the property FNV was chosen for — is unaffected;
cross-machine dictionary inversion stops working. Extend the comment at `:41` to say why a
*keyless* hash was not the answer either.

Related, smaller: `LogRoot.swift:31` writes a `~`-rooted scan root into the log verbatim, so
`~/Documents/AcmeCorp Migration` is logged in full — the file's own header argues that a chosen
name "names an employer", and that argument does not stop at the home directory.

### 1.4 A root shell resolves bare command names through the inherited `PATH`

**Done for `mkdir`/`chown`** — `ebd38c1`, 2026-07-29: both now run by absolute path
(`/bin/mkdir`, `/usr/sbin/chown`). **Still open:** whether the privileged trampoline itself
inherits `PATH` was not tested (needs the user's password) — this is a hardening fix, not a
verified-closed vulnerability. The AppleScript-escaper newline/U+2028/U+2029 gap is also **still
open** — neither commit touched the shared escaper.

`HomebrewEngine.swift:189` runs `mkdir -p /opt/homebrew && chown -R '<user>':admin /opt/homebrew`
inside `do shell script … with administrator privileges`. The user name is correctly validated and
quoted; the two **bare command names** are the gap. The reviewer demonstrated that `do shell script`
inherits the caller's `PATH` and resolves unqualified names through it, and Helm inherits its
environment from the launchd GUI session, which any user process can rewrite.

Whether the privileged trampoline also inherits `PATH` was **not** tested — that needs the user's
password. If it does, this is a clean user→root escalation. Every other privileged string in the
repo already uses absolute paths (`SudoersRule` names `/usr/bin/printf`, `/bin/chmod`,
`/usr/sbin/visudo`). **Do:** `/bin/mkdir` and `/usr/sbin/chown`. One line.

Also: the shared AppleScript escaper neutralises `\` and `"` but not newlines or U+2028/U+2029.
Not reachable today — both callers pass validated names and constants — but it is the shape that
fails the moment leftovers-plan item 4 gives it a third caller. Reject newlines in the shared
runner rather than escape them; escaping would change what root runs.

### 1.5 "Freed" is not freed

**Done** — `ebd38c1` (Disk's "Moved to the Trash" + stop-crediting-free-space) and `1734fac`
(Duplicates, Login Items & Extensions, Uninstaller strings, and the Leftovers-bottom-bar /
VPN-dial mismatches), 2026-07-29. In CHANGELOG.md and, curated, in ChangelogData.swift.

Six strings and one piece of arithmetic tell the user that disk space came back when the files are
in `~/.Trash`, on the same volume: `UninstallerStrings.swift:53,54,18`, `LeftoversStrings.swift:49,60`,
`DiskStrings.swift:30` — and `DiskViewModel.emptyBasket` (`:365`), where
`freeBytes: previous.freeBytes + freed` makes the ring agree with the false caption. The button one
click earlier says "Move to Trash", so the app contradicts itself inside one screen.

ARCHITECTURE.md § "What 'freed' means" is about *measuring* a folder's size on APFS, not about
this — the question has not been decided before.

**Do:** say what happened ("Moved to the Trash — 4 KB"), and stop adding the bytes to free space
(the tree is already pruned, so the used total falls correctly on its own).

Two more places where the readout contradicts what is under it: the Leftovers bottom bar mixes a
*found* count with a *selected* size (`LeftoversSettingsPage.swift:240`), and the VPN dial reads
"0 / AUTO" directly above one visible rule because it counts live auto-connections rather than the
rules the person wrote (`VPNSettingsPage.swift:39`).

### 1.6 The last screen before deletion does not name what it deletes

**Done** — `1734fac`, 2026-07-29. `UninstallPlan.ReviewRow`/`reviewRows(_:)` added; the bundle is a
non-tickable first row per group. `ReviewRowsTests` green. Homebrew's mildest-confirmation wording,
Leftovers' "Delete…" ellipsis and Duplicates' richer confirmation were fixed in the same commit;
Safari/system-app marking too.

`UninstallerSettingsPage.swift:242-310` — seen on the running app. The review screen shows the app
name as a section header, "no additional files found", and a bottom bar. Nothing on it says the
application bundle itself is going, and there is no dialog after it. The group header's icon at
18 pt reads as an unticked checkbox, so the screen can honestly be read as "nothing is selected".

**Do:** a first, non-tickable row per group for the bundle, with its path and a caption naming it.

Nearby, same tier: Homebrew's uninstall is the **only irreversible deletion in the app** and has
the mildest confirmation (`HomebrewStrings.swift:17`) — say that it does not go to the Trash. The
Leftovers row menu's "Delete…" trashes on the click for orphaned items (`needsConfirmation` is
`status != .orphaned`), so the ellipsis promises a step that never comes. Duplicates confirms with
a count and a size in the module that deletes a person's own photos, where Disk three files away
names up to four paths. And Safari is in the removable list, tickable, at "0 B" — the
`com.apple.` test that would mark it already exists in `LeftoverActions.available`.

### 1.7 The permission the app asks for is described as less than it is

**Done** — `ebd38c1`, 2026-07-29. `accessibilityWhy` now names both Keyboard and Keep Awake; the
first-launch "again" wording and the Settings list asking for a permission no enabled module needs
are both fixed in the same commit (`PermissionAudit.swift`, `PermissionNeed.swift`).

`AppStrings.swift:48` — the standing caption in Settings → Permissions explains Accessibility as
"needed for Keep Awake to nudge the pointer". That grant is also what the entire Keyboard module's
system-wide `CGEventTap` runs on. Line 80 of the same file, the alert shown when the grant lapses,
gets it right. The permanently-visible caption — the one a person reads *while deciding* — does
not. Same fix in `PermissionNeed.swift:57-63`.

Two more in this area: on the very first launch the alert says permissions must be granted
**"again"** (`PermissionAudit.swift:56`, because `shouldSpeak` fires when `lastSeenVersion` is
empty), and the button labelled "Grant…" opens System Settings and grants nothing.

---

## Tier 2 — state the user loses, and work the app repeats

- **The Uninstaller's ticks, review step, scanned groups and failure report are `@State` on the
  page** (`UninstallerSettingsPage.swift:31-40`) — verified live: tick an app, click Disk, click
  back, the count is zero. The same click during the review step discards a scan of every ticked
  app; on the failure report it discards the only record of what macOS refused and why. This is
  exactly the "a cached view model feeding a list the page throws away is not a cache" note in
  ARCHITECTURE.md, applied to the state that matters most.
  **Done — `1734fac`, 2026-07-29.** State moved into the (already-cached) view model.
  `StateOutlivesThePageTests` (behavioural + a source-shape test, so a sixth `@State` can't slip
  past the behavioural one alone) green.
- **Duplicates and Leftovers use a page-scoped `@StateObject`** while five other modules use
  `shared(vm:)` — so a sidebar click throws away the most expensive scan in the app (and every
  checkbox in Leftovers). Duplicates has no on-disk cache either; Disk has `ScanStore`. Leaving the
  page during a search also fails to cancel the engine, which keeps hashing with nobody watching.
  **Done — `1734fac`, 2026-07-29.** Both take `shared(vm:)`. `SharedViewModelTests` (Duplicates,
  Leftovers) green.
- **`UninstallerEngine.appSizes()` (`:47-52`) calls `installedApps()` a second time**, re-enumerating
  and re-parsing every `Info.plist` seconds after `listApps()` did. The list is already in the view
  model; pass it in the command payload.
  **Done — `1734fac`, 2026-07-29.** `AppListEnumeratedOnceTests` green.
- **Disk's "Stop" throws away a partial tree** the user watched build for up to a minute
  (`DiskViewModel.swift:217-225`). Either keep the partial, marked as partial, or rename the control.
  **Still open.** `ebd38c1` fixed the basket/wrong-volume-credit half of Stop (item 0.8); this
  distinct design question — keep the partial tree, marked partial, or rename the control — was not
  addressed by either commit.
- **`DiskNode` carries the full path beside the name** — measured over a 1.5 M-node array with
  realistic paths: **92 MB name-only against 437.6 MB name+path**, i.e. ~345 MB, larger than the
  earlier estimate. Store the component and derive the path.
  **Still open.** Neither commit touched `DiskNode`.

**Answered, so it can be struck off the leftovers plan:** "then check every other loop that reads
or stats in bulk" — done, and the answer is negative. Every `resourceValues(forKeys:)` loop was
measured, not assumed: a serial 100 000-file walk grows 0.3 MB without a pool; an 8-way
`concurrentPerform` over 480 000 files grows 1.8 MB. `URLResourceValues` bridges to small value
types, not to a retained buffer the way `FileHandle.read`'s `Data` does. **Do not add pools there.**
Recorded in ARCHITECTURE.md § Memory. `ReleaseDigest.sha256` (item 0.2) turned out to be a second,
non-parallel instance of the class this question was about — fixed the same way, pool inside the loop.

**Still unexplained:** the +177 MB when the Uninstaller page opens. Both of the leftovers plan's
hypotheses are now falsified — the per-app icons cost **3.9 MB** for this machine's 39 apps at the
row's real 28×28 (and load through a virtualized `List`), and bundle sizing costs single-digit MB.
The next step is the instrumentation that caught the hash loop: `HelmLog.memory` deltas around page
navigation in a live build. **Still open** — neither commit measured or explained this.

---

## Tier 3 — code that can go, and duplication that has earned its removal

*A separate dead-code/consolidation pass over `Sources/` is running concurrently with this list's
upkeep (2026-07-29) — check its result before re-deriving any of the "Consolidate" items below.*

Proven dead (the declaration is the only hit; greps re-run by hand):

- `AppStrings.swift:26,27` — `permissionAuditTitle` and `permissionAuditBody`, superseded by
  `permissionsChanged` + `permissionReason(_:)`. Two dead strings times eight languages.
  **Done — `ebd38c1`, 2026-07-29.**
- `HelmLog.swift:2` — `import os`, with no `os` API used in the file. The only such import in the package.
  **Done — `ebd38c1`, 2026-07-29.**
- `HelmLog.swift:9` — `LogLevel.debug`, never constructed, no wrapper.
  **Done — `ebd38c1`, 2026-07-29.**
- `ScanPath.normalize` (`:14`) and `UninstallPlan.allLeftoverPaths` (`:62`) — tests only.
- `HelmBytes.localizedUnits` (`:50`) — tests only, **but** its 15 asserts are the only direct
  coverage of the per-language unit table. Re-point them at `HelmBytes.string` first, then delete.

Consolidate:

- `children(of:)` is byte-identical in `Leftovers/SystemPorts.swift:11` and
  `Uninstaller/SystemPorts.swift:100` → `HelmRuntime`, beside `FileWeight`.
- `string(_ source: TISInputSource, _:)` is duplicated between Layout's UI (`:50`) and its engine
  (`:216`) — same module; making `InputSources` public drops ~15 lines of UI, including a
  re-implemented `kTISPropertyUnicodeKeyLayoutData` filter.
- `confirmTrash(_:_:)` is byte-identical in `DiskStrings.swift:31` and `UninstallerStrings.swift:13`,
  in all eight languages.
- `TapKey.deviceMask` (`ModifierTap.swift:42`) and `CGEventTapPort.modifierMasks`
  (`Layout/SystemPorts.swift:70`) hold the same nine hardware bit values twice — and the comment at
  `:64-66` is now false, since it says left-side only and the table holds all nine.
- `DiskRemoval` (`DiskEngine.swift:206`) and `DuplicateRemoval` (`DuplicatesEngine.swift:88`) are
  field-identical to `HelmTrash.Result`, which both engines already build and then unwrap and re-wrap.
  `typealias` both; leave `LeftoversRemoval`, which downgrades the typed reason to a string and is a
  second edit.
- Five copies of `shared(vm:)` hand-type the module id as a string literal into
  `ModuleUICache.dropWhenDisabled` — a typo compiles and produces exactly the leak the cache exists
  to prevent. Replace each with `XDescriptor.id.rawValue`; the compiler becomes the test. Same for
  the four descriptors that re-derive their store namespace from a literal on the fallback path.

Keep, deliberately: `HelmFailure.posix`, `RunningApps.hasSnapshot`, `FrontmostApp.setForTesting`
(consider `#if DEBUG` — it is public API on a shared singleton), `InMemoryKeyValueStore`,
`VPNAutoConnectCore.activeVPNs`, `LayoutEngine.boundTapKey`, `VPNSettings.setRulesJSON`.

Needs a decision rather than a delete: `PermissionNeed.Feature` + `PermissionNeed.of(_:)` is a
designed-but-never-wired safety table (production reads `moduleMetadata.permissions` instead) —
wire it or delete it with its tests. `StaleItem.canToggle` is the named form of a rule the UI
writes out inline (`LeftoversSettingsPage.swift:178`) — better to *use* it than to delete it.

Clean, nothing to report: `grep -r HELM_DEBUG Sources/` is empty; the v0.7.0 Island revert left
nothing behind but the live `ObsoleteDefaults` migration, which is covered by tests; there are zero
`#available`, zero `#if`, zero TODO/FIXME and zero commented-out code blocks in `Sources/`.

---

## Tier 4 — design, accessibility, localization

*Nearly all of this tier is Done — `1734fac`, 2026-07-29 — with per-item notes below. The bundle
still declares no `CFBundleLocalizations` and ships no `.lproj`, and the Advice popover's
context-menu-only reveal, the Autopilot dry-run preview's fragmentation and the CJK/Latin spacing
question are all **still open** — see the notes inline.*

**Contrast, which is correctness rather than taste.** Literal `.orange` / `.green` where
`HelmSignal` exists, measured in light mode: system `.orange` **2.31:1**, `.green` **2.22:1**,
against `HelmSignal.warning` **4.54:1** and `.success` **4.58:1**. Worst instance is body text at
10 pt (`DiskResultView.swift:348`); the About page's update card draws two vocabularies 340 lines
apart from its own permission rows. `HelmMetricStrip`'s tint blend at 0.30 gives 3.85–3.99:1 — under
the floor at 16 pt medium; 0.40 gives 4.69–4.97:1. `LeftoversSettingsPage.swift:156` uses SwiftUI's
`.secondary` (3.95:1) for row names where `HelmText.quiet` (4.62:1) is the token.
**Done — `1734fac`.** `SignalInkTests`, `MetricTintTests` green; the metric-strip blend's second
defect (resolved against `NSAppearance.current` rather than the SwiftUI environment, so it
darkened *dark* mode's own colour half the time) was found while fixing this — see CHANGELOG.md.

**Screens that read as two products.** Disk's start screen sits 32.5 pt off its own header at the
default window and 202.5 pt off at 1400 — the same 203 the `HelmPageHeader` doc records as the
reason `bleeds` was invented. Homebrew hand-rolls a second, larger empty state that the
`OneEmptyStateTests` guard cannot see, and the *same pane* shows both one click apart. One event —
"we are working" — has four different shapes, one of which is a bare spinner with no words while
250 app icons load. Three sheets have three mastheads. Byte sizes appear in four different
typefaces across adjacent lists (measured: 27% width difference).
**Done — `1734fac`** for the header offset (`StartScreenColumnTests`), the Homebrew second empty
state (guard widened to the shape, not just the component; `HelmBusyState` gained an `actions:`
slot so Disk's Stop button stopped needing a fourth loading shape) and byte-size typeface
consistency (`FigureFontTests`). Mastheads and general spacing/hairline/tint consistency also
addressed across the Uninstaller, Leftovers, Homebrew and About pages.

**Accessibility.** The Disk basket button's label says "Add" even when the item is already
basketed, so a VoiceOver user is told the opposite of what pressing it does. The Uninstaller's
lists never got the `combine` sweep — four to five stops per row in a list of hundreds. The Advice
popover has a context-menu reveal with no `.accessibilityActions` counterpart, unlike its sibling
row which documents exactly why one is needed. The Autopilot dry-run preview — the list whose whole
purpose is making the consequence visible — reads as loose fragments, and its Done button has no
`.defaultAction`.
**Done — `1734fac`** for the basket button label, the Uninstaller/Leftovers/Autopilot-preview/VPN
`combine` sweep, and disclosures announcing expanded/collapsed plus the panel's Utilities row
regaining its module count (`ResultViewAccessibilityTests`, `NamedControlsTests`). **Still open:**
the Advice popover's context-menu-only reveal (no `.accessibilityActions` counterpart) and the
Autopilot dry-run preview's fragmentation/Done-button `.defaultAction` — neither commit touched
`Modules/Disk/UI` advice popover or `Autopilot/UI/RuleEditor`'s preview list for this.

**Localization.** Beyond 0.10: the bundle declares no `CFBundleLocalizations` and ships no `.lproj`,
so every AppKit panel (the folder picker's "Open"/"Cancel"/"New Folder" and sidebar, the text-field
context menu, VoiceOver's window titles) is English inside a Russian or Japanese app — three modules
open one. `Quoted` uses ordinary spaces inside French guillemets where Apple uses a no-break space
(1127 occurrences to zero across 80 system tables), and it is the shared helper. Russian has three
names for "keyboard shortcut" and one of them is slang; Spanish still says "Timer" where macOS says
"Temporizador" and Helm itself says "temporizador" seven lines later; German's `.tagged` is "Tag",
which is the German word for *day*, in a module whose `unitDays` is "Tage". Counts are interpolated
as raw `Int`, so a scan of `/` reports `1499308 files in 75,2 s` — the seconds go through a
formatter and the count does not. A changelog date prints as the literal `2026-07-28`.
**Done — `1734fac`** for `Quoted`'s French/Spanish/Japanese marks (`QuotedTests`), the Russian
keyboard-shortcut/genitive-day wording, Spanish "Temporizador", German's tag verb, raw-`Int` counts
(`HelmBytes.grouped`, `GroupedCountTests`) and the changelog date (`HelmDates.day`,
`ChangelogDateTests`). **Still open:** the missing `CFBundleLocalizations`/`.lproj` declaration —
this needs an `Info.plist`/build-script change, and neither commit touched packaging.

Coverage itself is sound: 649 `L()` calls, all seven tables each, zero placeholder mismatches, zero
English left in a non-English slot, and nothing overflows in German or Russian at the measured widths.

---

## Tier 5 — argued against, recorded so it is not re-derived

- **`ScanRegistry` (Disk) and `FinderBox` (Duplicates)** look like one mechanism written twice and
  are not: `current` means "the latest scanner" and `inFlight` means "all of them", so `deactivate`
  and `cancel` change meaning. Both were fixed within the last two weeks and both are correct today.
  A refactor here buys risk and nothing else.
- **The `ModuleDescriptor` protocol change** to pass `store` into `settingsPage`/`menuBar` touches
  all nine modules for tidiness. Not in a pass whose stated priority is not breaking anything.
- **The hotkey registration list in `AppDelegate`** — do it the day a third module needs a shortcut.
- **Splitting `SettingsWindow.swift`** (943 lines, four screens) — only as its own commit with
  nothing else in it; the file is dense with earned layout facts and a dropped modifier is a visual
  bug only the screenshot harness catches.
- **Pinning a digest for Homebrew's `install.sh`** — it moves weekly and this is the official
  installation route. Worth a comment saying it was decided, not overlooked.
- **Adding `autoreleasepool` to `resourceValues` loops** — measured, unnecessary; see tier 2.
- **The CJK/Latin spacing question** (172 ja and 168 zh sites): Apple does not put a space and Helm
  does, but this is a genuine house-style debate and Helm is inconsistent with itself. Fix the
  internal inconsistency; let a ja/zh reader pick the rule. **Do not** touch the `HelmBytes` join —
  Apple's own key really does carry a space there.

---

## Corrections to the agent reports

- The performance reviewer called the 27 failures it saw "pre-existing, unrelated to this session".
  They were not: they are the testing reviewer's new files, written concurrently into the same tree.
  The baseline run before any agent touched anything was **1218 tests, 0 failures**. Nothing was
  already red.
- The testing reviewer noticed that the baseline test *count* is not stable (1218/6 skipped on the
  first run, 1219/7 after). One env-gated test decides to skip on machine conditions. Pre-existing,
  and a report rather than a gate.

## Untracked test files now in the tree

Nine files, from the testing and performance reviewers. They encode tier-0 defects and should be
kept, but note that `Package.swift` has no UI test target for five modules, and CLAUDE.md's rule
about a test directory with no tracked file applies to every one of them.

```
Tests/HelmRuntimeTests/ReleaseDigestFootprintTests.swift
Tests/Modules/Autopilot/EngineTests/RenameIdempotenceTests.swift
Tests/Modules/Disk/EngineTests/ScanFootprintTests.swift
Tests/Modules/Disk/UITests/EventsTaskRetainTests.swift
Tests/Modules/Disk/UITests/StopLeavesNothingBehindTests.swift
Tests/Modules/Duplicates/UITests/EventsTaskRetainTests.swift
Tests/Modules/KeepAwake/EngineTests/SudoersPromptInFlightTests.swift
Tests/Modules/Layout/EngineTests/GestureAfterNavigationTests.swift
Tests/Modules/Uninstaller/EngineTests/NestedSiblingTests.swift
```
