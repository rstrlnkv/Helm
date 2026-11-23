# Leftovers

`Sources/Modules/Leftovers/` finds login items and plug-in files whose owner is
gone. Its boundary is what it will *offer*, and the rules err toward leaving things
alone: `Sources/Modules/Leftovers/Engine/Logic/StaleItemRules.swift` names what it
keeps.

Its removal path goes through `RemovableScope.partition` inside
`Sources/Modules/Leftovers/Engine/LeftoversEngine.swift` and then through
`HelmTrash.remove`; why the gate gets the engine's own `home` is on that `home`.

Turning a login item off is not deleting it, and the switch is aimed at a launchd
*label*, which is not a file: `Sources/Modules/Leftovers/Engine/Logic/LaunchctlDisabled.swift`
says why the per-user disabled-label list is the switch, and
`Sources/Modules/Leftovers/Engine/Logic/LaunchClaims.swift` says how many files
claim one label.

`LeftoversEngine` keeps its own record of the labels it disabled (`recordKey`, whose
doc comment says why not the system's list), so switching the module off gives back
exactly those; the edge that record cannot close is in ARCHITECTURE.md § Giving everything back.

Writability is asked of a directory rather than of each item in it
(`LeftoversFilePort.isWritableDirectory`).

The question before a deletion names the reason it is asked. `LeftoverActions.askBeforeDeleting` gives the
reason a row is asked about (`loadedNow`, `cannotBeRead`, `cannotBeChecked`), or nil for a leftover, which is
moved without a question, and `LfStr.confirmDelete` switches over it with no `default:`. A row Helm could not read is asked about being unreadable, never told it is loaded.

Words: `Sources/Modules/Leftovers/UI/Localizable.xcstrings`; shared words through `HelmWord`.

## How Leftovers' model reaches its engine

`LeftoversViewModel` is built with the engine by the descriptor's `makeModule` and
held by the host. It calls `scan`, `trash` and `setDisabled` through its
`LeftoversWork` port, which the engine conforms to; each is answered by return, and
there is no stream because the engine emits nothing. The last word on a path and on a
label stays in the engine: `trash` partitions through `RemovableScope` before
`HelmTrash.remove`, and `setDisabled(_:)` asks `LaunchLabel.mayBeSwitched` and the
two agent folders before it reaches the switch, so a caller of the model cannot go
round them. On the person's switch the host calls the descriptor's `stop(_:)` after
`willDisable()` has given the switches back, and the model stops sending presses.
«Reset all settings» runs `willDisable()` on every live module too, and its `stop(_:)` waits for `shutdown()` on the way out of the relaunch. A press in that window, and a press already in flight when `willDisable()` runs, are refused by the engine's latch: `willDisable()` sets `handedBack` under `switchLock` before it reads the record, and every press checks it under the same lock, so no switch lands and no record is written after the give-back. The same lock makes two presses one at a time, so neither loses the other's label.

The port answers with a `SwitchAnswer`, read from launchd: a label is left out of the record only on `.refused`, and a label whose enable did not answer `.accepted` stays in it, so a timed-out call neither records a switch launchd refused nor forgets one it may have applied. Each `launchctl` call runs under a ten-second deadline (`ActiveExtensions.launchctlDeadline`), which is what bounds the main thread when `willDisable()` runs there.

## Reads, predicates, guards and files

The engine asks whether a path is there through the port's `exists`, which is `DirectoryListing.exists(atPath:)` (`Sources/HelmRuntime/DirectoryListing.swift`): `nil` for a path it could not answer for, never `false`, so a folder that went unread is not a missing one.

`LeftoverActions.isApplesOrProtected` is the one Apple-or-protected predicate, and both `available(for:)` and `whyDeleteIsWithheld(from:)` stand on it, so the page cannot offer what the reason says is withheld.

`StaleItemRules.protectedPrefixes` is a second protected-prefix list, kept on purpose beside `UserFileScope.protectedPrefixes`: the first judges what the scan offers, the second is the gate a removal of the user's files passes (Leftovers' own removal passes `RemovableScope.partition`, `LeftoversEngine.trash`), and each stays authoritative for its own question (Architecture/WhatIsDeliberatelyNotHere.md, "Not one list of protected prefixes").

Kept tests, one per guarantee:

| guarantee | test |
|---|---|
| a folder that went unread is not a file | `AFolderThatWentUnreadIsNotAFileTests` |
| a source nobody walked is not a clean Mac | `ASourceNobodyWalkedIsNotACleanMacTests` |
| the rules keep what they name | `StaleItemRulesTests` |
| a switch the engine turned off is given back | `ALeftoverSwitchIsGivenBackTests`, `TheEngineRefusesASharedSwitchTests` |
| a switch launchd refused is not recorded, one it may have applied is | `AFailedSwitchIsNotRecordedTests` |
| no switch lands after the hand-back | `ASwitchInFlightIsGivenBackTests`, `APressAfterTheHandBackIsRefusedTests` |
| two presses lose no label | `TwoPressesLoseNoLabelTests` |
| a hidden tick never reaches the Trash | `AHiddenTickNeverReachesTheTrashTests` |
| the removal passes the gate | `LeftoversRemovalTests` |
| one removal at a time | `OneRemovalAtATimeTests` |
| the log does not name the software | `TheLogDoesNotNameTheSoftwareTests` |
| a stopped model reaches no work | `AStoppedModelReachesNoWorkTests` |

The tests live in `Tests/Modules/Leftovers/EngineTests` and `Tests/Modules/Leftovers/UITests`.

## The states of the Leftovers page

Leftovers has no tile of its own: the descriptor answers `.utility` for the menu bar, so its panel entry is a row
in the panel's collapsed «Utilities» list. The page id is the module id, `leftovers`, and a state is shot with its file
`leftovers-<state>-<light|dark>[-<ru|de>].png`:

    bash Scripts/shoot.sh leftovers \
      [--press "<control name>"]... \
      --arg module.app.barAppearance flat --arg module.app.appearance <light|dark> \
      --name <state>-<light|dark> --out <dir>

Nothing on the Mac is switched or removed to reach a state; a state that needs a removal is not shot.

| state | the page shows | reached by |
|---|---|---|
| `not-scanned` | wand mark, «Scan to see…», the intro note, one prominent Scan; no header strip | module just switched on, or a fresh launch |
| `scanning` | the invitation's Scan with a spinner, dimmed | a press on Scan (transient) |
| `leftovers` | «Leftovers» tab, Found caption, the review line, rows grouped by kind, selection line, action bar | a scan on a Mac with leftovers |
| `all` | «All» tab: in-use, system, unreadable and not-checked badges, Turn off/on, «Open Extensions…» on extension rows | the «All» tab |
| `nothing-found` | check mark, «No leftovers found.», Scan only in the header | a scan on a Mac with none (real use) |
| `hidden-by-filter` | filter mark, «Everything found is hidden by the filter.» | the kind menu with every kind off |
| `not-everything-checked` | question mark, «Helm could not check N items.», Scan again | a scan that could not judge some rows (real use) |
| `no-disk-access` | the Full Disk Access note over the content | Helm Dev without Full Disk Access (real use) |
| `confirm-row`, `confirm-batch`, `removal-report`, `busy` | the question dialogs, the outcome row, controls dimmed | a removal: not shot; `busy` and the report held by `OneRemovalAtATimeTests`; the dialogs by no test |
| `worst` | ru and de at the narrowest pane: captions give way through `ViewThatFits`, long paths cut in the middle | `--arg module.app.interfaceLanguage ru` or `de` on `leftovers` and `all` |

The panel row: `--panel` alone shows the «Utilities» list collapsed; expanding it needs a press inside the open panel (`utilitiesExpanded` is `@State`, `Sources/HelmApp/HelmPanel.swift`) that `Scripts/shoot.sh` does not have.
