# What the review pass left open — 2026-07-28

The ten-reviewer / four-fixer pass that produced 0.7.2-dev.28 closed twenty-one
defects and the localization sweep. This is the remainder: everything that was
found and deliberately **not** fixed, plus the fixes that shipped without a test
holding them. Nothing here is a release blocker for dev.28 — it is the list to
work through once the log triage is done, so none of it has to be re-derived.

Order below is the order worth doing them in, not severity: the two that need
`Package.swift` unlock the tests for several of the others.

---

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

## 7. Small, and honestly optional

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
