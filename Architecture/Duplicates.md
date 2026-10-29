# Duplicates

`Sources/Modules/Duplicates/` decides which of several identical files is the extra
one, and that decision is a belief rather than a fact the disk holds. The two
beliefs, `byPlace` (the default) and `byDate`, are `KeepPolicy.swift`; one ladder
answers both what stays and why (its doc comment, read by `SurvivingCopy.swift`).

A group's size is what `CloneShare.reclaimable` (`Sources/HelmRuntime/CloneShare.swift`)
says removing it returns, not the sum of its files.

Acting on a finding re-reads the pair: `DuplicateVerification` is its own phase
beside the removal. `DuplicateVerification.Batch` memoises the survivor's reading
only, for the life of one press; the copy about to stop existing is read from disk
in full every time.

The unattended walk is narrower than the watched one: it asks
`ScanRoot.refusesDescentInHome` of every directory it meets, so the `~/Library`
subtrees macOS guards with TCC stay out of the 0600 journal
(`DuplicateScanner`'s `unattended`).

Words: `Sources/Modules/Duplicates/UI/Localizable.xcstrings`; interpolated ones in inline tables in `DuplicatesStrings.swift`; shared words through `L()`, and what Disk says too — the basket bar's two lines, moved to the Trash, mark a named file — through `HelmBasket` in `Sources/HelmUI/BasketStrings.swift`.

Every control on the toolbar and the basket row keeps its label at every width: no pane the settings window gives is narrower than the widest row (`DuplicatesLayout.swift` has the numbers), and the `worst` state below is where a longer string would show.

## How Duplicates' model reaches its engine

`DuplicatesViewModel` is built with the engine by the descriptor's `makeModule` and held
by the host. It calls `find`, `cancel`, `trash`, `stopRemoval` and `backgroundScan`
through its `DuplicatesWork` port, which the engine conforms to, and each is answered by
return: a search that was stopped answers nil, a removal that was stopped answers
`cancelled`. The progress of a search and of a removal goes to a sink the model hands
over with that call, an `AsyncStream` that keeps the newest tick and that the model
drains while it awaits the answer, so there is no stream on the engine and two calls in
flight need no name to be told apart. The gates stay in the engine: `trash` partitions
through `KeptCopies` and `UserFileScope`, re-reads each pair through
`DuplicateVerification`, and only then hands the path to `HelmTrash.remove`;
`DuplicatesRemovalGateTests.testAPathTheGateRefusesIsRefusedByTheEngineAndNotAttempted`
holds that a refused path is reported and never handed to the `trashing:` port, which
production sets to `HelmTrash.moveToTrash` and no test leaves to a default.

The model asks the keychain for the stored keep policy in `appear()`, which the page
calls from its `.task`, not in `init`: `makeModule` runs when the module starts. On the
person's switch and on quit the host calls the descriptor's `stop(_:)`, after which the
model reaches no work, shows no search answer still in flight and asks the keychain
nothing more except by saving a chosen folder or policy, which `stop` does not refuse;
a removal already handed to the engine still lands, and what moved before the stop is
reported. The model keeps no state for a reply that never
arrives: an answer is always a return.

A background scan and a search the person started share the engine's one finder slot, so
one begins by cancelling the other.


## The states of the Duplicates page

The page id is the module id, `duplicates`, and a state is shot with its file `duplicates-<state>-<light|dark>[-<fr|de|ru>].png`:

    bash Scripts/shoot.sh duplicates \
      [--press "<control name>" [--nth <n>]]... \
      --arg module.app.barAppearance flat --arg module.app.appearance <light|dark> \
      [--arg module.app.interfaceLanguage <fr|de|ru>] \
      --name <state>-<light|dark>[-<fr|de|ru>] --out <dir>

A scratch tree of planted duplicates is enough for every state that shows a result. Nothing is removed to reach a state:
`confirm`, `removing` and `removal-report` are not shot; `removing` is held by `AStopDuringARemovalReachesTheEngineTests` and `ATickReachesOnlyItsOwnBarTests` (optional), the question is held by no test; the copies the press then names as staying, by `ThePageNamesEveryCopyItKeepsTests` (optional), and the figure the outcome banner counts as freed — a clone of the copy that stays is not counted — by `TheBannerCountsWhatTheDiskGivesBackTests` (optional, engine).

| state | the page shows | reached by |
|---|---|---|
| `start` | «Pick a folder and Helm will read what is in it…» with Choose folder; no toolbar | no folder stored |
| `start-folder` | the folder in the toolbar, the policy row, «Helm will read what is in this folder…» with Search now | a scratch folder: `--arg module.duplicates.folder "${TMPDIR}helm-dup-scratch"` (`TMPDIR` ends in `/`; `"$TMPDIR/…"` gives `//` in the toolbar path) |
| `no-disk-access` | the Full Disk Access note over any phase | Helm Dev without the grant (real use; the crew changes no grant) |
| `searching` | `HelmBusyState` with the count of files read, Stop scan in the toolbar | `--press "Search now" --nth 2` on `start-folder` (transient: on a 7-file scratch tree it is over before the instrument, which waits 1 s after a press, shoots; not shot there) |
| `search-stopped` | «Search stopped — the folder was not read to the end.» | Stop scan mid-search |
| `nothing-found` | «No duplicates here…» and the 1 MB note | a search of a scratch folder with no duplicates |
| `result` | the 1 MB note, the «Groups: N · …» line, one section per group, its first copy marked as the one that stays | a search of a folder with planted duplicates |
| `chosen` | «Restore the recommendation» in the header, «your choice» beside «stays» | `--press "Keep this copy" --nth <n>` on `result` |
| `preview` | the Quick Look sheet over the list | Space on a selected row, or Quick Look in the row's menu: reached only through AXShowMenu or Space, which `--press` (AXPress only) cannot do; by hand |
| `basket` | the bar with the marked count and size, Clear the marks, Move to Trash | `--press "Mark every extra copy"` on `result` |
| `marks-note` | «Skipped: N files — Helm may not remove those» or «Unmarked: N — those copies stay now» above the count | a mark that passes over a system item, or a policy change or Restore the recommendation that makes a marked copy the one that stays |
| `confirm`, `removing`, `removal-report` | the question, the progress with Stop removal, the outcome | a removal: not shot |
| `worst` | fr, de and ru at the minimum window with the sidebar at its widest: the toolbar and the basket row keep every label | `--arg module.app.interfaceLanguage fr`, `de` or `ru`, with `basket` pressed; not rendered — the instrument sets neither window size nor sidebar width — and checked by arithmetic: `DuplicatesLayout.swift`'s doc comment, the widest row under 772 pt |

The two Search now buttons share one name: `--nth 2` is the empty state's, the toolbar's is the first in `HelmReadout ax` order.
