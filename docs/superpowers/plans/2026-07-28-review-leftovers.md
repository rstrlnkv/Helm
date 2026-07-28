# What the review pass left open — 2026-07-28

The ten-reviewer / four-fixer pass that produced 0.7.2-dev.28 closed twenty-one
defects and the localization sweep. This is the remainder: everything that was
found and deliberately **not** fixed, plus the fixes that shipped without a test
holding them. Nothing here is a release blocker for dev.28 — it is the list to
work through once the log triage is done, so none of it has to be re-derived.

Order below is the order worth doing them in, not severity: the two that need
`Package.swift` unlock the tests for several of the others. Items 7 and 8 came
from the user watching the app rather than from the review.

**Item 0 is not like the others.** It is a memory leak the user hit at 48 GB, it
is reproducible on an idle machine, and it blocks the beta this dev build was
supposed to graduate into. Everything below it can wait; that cannot.

---

## 0. Memory leak — RELEASE BLOCKER, do this first

**Reported** (user, 2026-07-28): while using Login Items & Extensions, Helm grew
to **48 GB** of memory.

**What I measured** on 0.7.2-dev.28, before touching anything:

- The app was **idle** — no scan running, no page open, nothing in the log after
  launch — and RSS went **468 → 507 → 524 → 527 MB across 60 seconds**, three
  samples, monotonic. A later 45-second window was flat (558 → 554 MB), so the
  growth is bursty rather than a steady drip; whatever drives it is not
  continuous.
- Half a gigabyte resident on an idle accessory app is itself the wrong order of
  magnitude — this is a menu-bar utility with nothing on screen.
- `vmmap --summary` shows **13,299 `Malloc Small (empty)` regions holding 49.5 GB
  of reserved address space**, and `Malloc Metadata metadata` at 203 MB across
  406 regions. That is the signature of enormous allocation churn — memory taken
  and given back so hard that the allocator keeps thousands of emptied regions —
  not of one big retained buffer.
- `heap`, `leaks` and `sample` all returned nothing against the running process
  under the current permissions. Whoever picks this up will need Developer Tools
  access granted, or a locally-signed build attached to Instruments.

**Excluded already** (checked, so nobody re-checks): `LocalTransport` is *not* an
unbounded buffer — it keeps the last event **per name** plus a name list, so it
is bounded by the number of distinct event names an engine emits.

**Prime suspect, and the first thing to test.** `LocalTransport.subscribers` is
pruned only by `continuation.onTermination`. Every access to `.events` builds a
fresh stream and registers a new continuation, and Settings tears a module's page
down and rebuilds it on every sidebar visit. If the `for await` task behind a
rebuilt page is not cancelled, its subscriber stays registered for the life of
the app — still receiving every event, still holding whatever it captured. That
would grow with page switches and with event volume, which fits both the churn
signature and a leak that shows up "while using a module".

**How to work it:**

1. Reproduce with a counter, not a hunch: log `subscribers.count` per transport
   on a timer in a debug build, then open and leave a module page twenty times.
   If the count climbs, the diagnosis is done.
2. If it does not climb, bisect by module: watch RSS with each module enabled
   alone. The user hit it on Login Items & Extensions; that module runs
   `launchctl` and `systemextensionsctl` and reads bundles, so its scan path and
   its process output are the next place to look.
3. Whatever it turns out to be, the regression test is a count that must not
   grow — a subscriber count, a task count, an allocation count — not a memory
   figure, which is too noisy to assert on.

**Note for the beta decision:** dev.28 must not graduate until this is
understood. It is the one defect in this file that costs the user something
today.

## 1. A UI test target for Uninstaller and Homebrew

**Why it is here.** Two fixes shipped without a test because neither module has
a UI test target, and adding one edits `Package.swift` — which three branches
were holding at the time.

- `HomebrewViewModel.refreshAfterOp()` must also refresh `status`, or the page
  stays on the install screen after Homebrew is installed.
- `UninstallerViewModel` / `HomebrewViewModel` are cached per `ModuleViewModel`
  (the `DiskViewModel.shared(vm:)` pattern), **and** the page's `@State` moved
  into the view model — a cached view model feeding a list the page discards is
  not a cache.

**Do:** add `Module_Uninstaller_UITests` and `Module_Homebrew_UITests` following
the existing `Tests/Modules/Layout/UITests` shape, then write the two tests:
after `opState(.done)` the status is re-read; a second `shared(vm:)` for the same
view model returns the same instance and keeps its loaded list.

**Watch:** a test target whose directory holds no tracked file breaks the
manifest for every checkout but the one that wrote it (CLAUDE.md § Rules).

## 2. Widen the keyboard-reachability guard

`Tests/HelmUITests/KeyboardReachableControlsTests` scans only
`Sources/HelmUI/DesignSystem/` for controls whose only affordance is
`.onTapGesture`. The three sites outside it were fixed or judged fine by hand,
which is exactly the state that rots:

- `KeepAwakeSettingsPage` swatches — now real `Button`s.
- `RingView` (`Canvas` tap) and `DiskResultView` (double-click to drill) — keep
  their taps, and both have a keyboard path beside them (`List(selection:)`,
  Return, ⌘↑). The guard needs an allow-list with those two named and the reason
  written down, not a blanket exemption.

**Do:** widen the scan to `Sources/Modules/**/UI`, with the allow-list above.

## 3. The sidebar has no width guard

`ModuleMetadata.shortName` exists because "Объекты входа и расширения" was cut
mid-word in the sidebar. Nothing stops the next long name: the sidebar column
width is not a constant a test can reach, unlike `HelmPickerWidth`, which is
pinned against `NSPopUpButton.sizeToFit`.

**Do:** give the sidebar a named width constant in `HelmUI`, then a test in the
`HelmPickerWidth` style: every module's `shortName`, measured at the system font,
fits the column minus the icon and the insets, in all eight languages.

## 4. Shared plumbing that got written twice

Both were deliberate — the branches could not reach each other's files — and both
are the duplication CLAUDE.md's "read `ls Sources/HelmRuntime` first" rule exists
to prevent.

- `LogRoot` in `Modules/Disk/Engine/Logic/` **and** `Modules/Duplicates/Engine/Logic/`.
  It tags the volume or account name in a scan root so the log carries neither.
  It belongs beside `Redact` in HelmRuntime.
- The AppleScript escaper in `KeepAwake/Engine/Logic/SudoersRule.swift` and in
  `Homebrew/Engine/SystemPorts.swift` (`OSAPrivilegedRunner.runAdmin`). Two
  copies of the escaping that stands between a string and root's intent is one
  copy too many; the real shape is a shared privileged runner in HelmRuntime that
  owns both the escaping and the `do shell script … with administrator
  privileges` call.

## 5. Accessibility left in the middle

- **Escape does not close the Autopilot rule editor.** `SettingsWindow`'s
  What's New sheet got `.keyboardShortcut(.cancelAction)`; `RuleEditor.swift`
  did not, and it is the sheet where a keyboard user has furthest to travel —
  Tab past every condition row's picker and field to reach Cancel.
- **Composite rows read as up to five VoiceOver stops.** `.accessibilityElement(children: .combine)`
  is applied in Disk, Autopilot, Duplicates and the history section, and missing
  in `LeftoversSettingsPage` (name + two badges + path + missing-target note, on
  a list that can hold dozens), `HomebrewSettingsPage.pkgRow` (name, cask badge,
  version, description — on all three of its screens), `VPNSettingsPage` and
  `LayoutSettingsPage`.

## 6. `LocalTransport`'s replay window

`LocalTransport.events` subscribes under the lock, then unlocks **before**
replaying buffered events. A concurrent `emit()` in that window could deliver a
live event to the new subscriber ahead of the replayed ones, so a stale state
could arrive last and look current. No caller currently emits and subscribes in a
pattern that overlaps it, and no repro was built — which is why it was not fixed
blind. **Do:** either hold the lock across the replay (measuring what that costs
at activate time, since every module subscribes there), or stamp events with a
sequence number the subscriber can order by. A test that fails first.

## 7. The ring's drill animation tears, and the third level pops in

**Reported, not yet reproduced** (user, 2026-07-28): going from folder to folder
in Disk looks ragged, and the third level of the ring appears abruptly on
arrival instead of growing with the rest.

What the code does today, as far as reading it goes:

- `RingView.open(_:)` sets `pivot` to the wedge and animates `unfold` 0 → 1 with
  `HelmMotion.emphasis`; only in the completion does it call `onSelect(hit)`,
  reset `unfold` and clear `pivot`. The comment above it states the intent
  exactly: the ring you end up looking at is the one you watched grow.
- `RingUnfold.ring(_:isDescendant:progress:)` is what makes that true for the
  levels that are already on screen — a descendant's ring index slides from `N`
  to `N - t`, so the pivot's children walk inward as the pivot widens.

The suspicion, in the order worth testing:

1. **The new outermost level has no start state.** During the unfold the ring
   draws what the old view had: the pivot and its children. The level that
   becomes ring 3 after the drill — the grandchildren — was never drawn, so it
   cannot slide inward from anywhere; it is simply there when the tree swaps at
   completion. If so, the fix is to draw one level deeper than is shown and let
   it enter at zero width, rather than to lengthen the animation.
2. **Or the data is not there yet.** Drilling into a folder the walk had not
   measured issues a second scan (`measureAndDrill`), and the grandchildren
   arrive when that scan returns — which is after the animation has finished, at
   a moment nothing is animating. That would look like the same defect and needs
   a different fix (hold the transition, or bring the level in when it lands).
   Which one it is depends on whether the folder was already measured, so
   **reproduce both ways before touching anything.**
3. `.animation(HelmMotion.interface, value: segments.count)` animates on the
   *count* of segments. Two different rings with the same number of wedges get
   no animation at all, and a count that changes for an unrelated reason gets
   one. That is a plausible source of the "ragged" half of the report,
   independent of the level that pops.

**Do:** reproduce with the env-gated harness (ARCHITECTURE.md § Dev loop) on a
folder that is already measured and on one that is not, slow the motion token,
capture frames and **measure the ring radii across them** rather than judging by
eye — that is what the house rule exists for and what caught the last subtle one.
Only then decide between the three above.

## 8. Small, and honestly optional

- **`TreeBuilder.directory(for:)`** recurses toward `/` with no base case other
  than finding the root in its index. Every current caller descends from the root
  via `ScanPath.child`, so it is not reachable — a `guard` costs nothing.
- **Keep Awake's "short" units are not short**: `minutesUnitShort` is `Min.` in
  German (identical to the long form), `分钟` in Chinese, `分` in Japanese. They
  were measured and they fit (37.5 pt in a ~41 pt cell), so this was left alone
  rather than forced into `时`, which reads oddly. Revisit only if a pill grows
  something else.
- **`LeftoversScanner.owner(of:)`** is a linear scan over installed bundle ids
  per leftover item — sub-millisecond at realistic counts, and the only
  non-set-based membership check in the file.
- **Autopilot's rule preview** re-reads the whole watched folder on most
  keystrokes while a condition is being edited. Deliberate, and documented where
  it happens; it only becomes a problem against a folder with thousands of files.
