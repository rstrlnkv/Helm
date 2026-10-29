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

Words: `Sources/Modules/Leftovers/UI/Localizable.xcstrings`; interpolated ones in inline tables in `LeftoversStrings.swift`; shared words through `L()`.

## How Leftovers' model reaches its engine

`LeftoversViewModel` is built with the engine by the descriptor's `makeModule` and
held by the host. It calls `scan`, `trash` and `setDisabled` through its
`LeftoversWork` port, which the engine conforms to; each is answered by return, and
there is no stream because the engine emits nothing. The last word on a path and on a
label stays in the engine: `trash` partitions through `RemovableScope` before
`HelmTrash.remove`, and `setDisabled(_:)` asks `LaunchLabel.mayBeSwitched` and the
two agent folders before it reaches the switch, so a caller of the model cannot go
round them. On the person's switch the host calls the descriptor's `stop(_:)` after
`willDisable()` has given the switches back, so a press that late writes nothing nobody gives back.

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
| `confirm-row`, `confirm-batch`, `removal-report`, `busy` | the question dialogs, the outcome row, controls dimmed | a removal: not shot; `busy` and the report held by `OneRemovalAtATimeTests`, the bar's figures by `LeftoversPageContractTests`; the dialogs by no test |
| `worst` | ru and de at the narrowest pane: captions give way through `ViewThatFits`, long paths cut in the middle | `--arg module.app.interfaceLanguage ru` or `de` on `leftovers` and `all` |

The panel row: `--panel` alone shows the «Utilities» list collapsed; expanding it needs a press inside the open panel (`utilitiesExpanded` is `@State`, `Sources/HelmApp/HelmPanel.swift`) that `Scripts/shoot.sh` does not have.
