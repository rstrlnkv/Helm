# Disk

`Sources/Modules/Disk/` answers where the space went, so it is the one module
whose reading may not leave the largest folder out. The reasons live on the doc
comments of the code that carries them:

- both APFS mounts share a `dev_t`, and the firmlink skip set: `FirmlinkMap.swift`; the skip set matches only while paths are joined through `ScanPath.swift`; the signed `st_dev`: `BulkWalk.DeviceID`;
- folder names on screen, and why eligibility is by path: `SystemFolderNames.swift`;
- the unattended refusal of media-library bundles, by name and never by reading: `ScanRoot.refusesDescent`, used by `DiskScanner.swift`; a person watching the ring gets the whole volume, and the `~/Library` refusal is applied at the report, not at the descent: `UnattendedAdvice.swift`;
- a scan has an identity, a token only its owner can spend: `ScanRegistry.swift`; what a scan says while it runs goes to the sink of that one call, so no update has to name its scan: `DiskScanUpdate` in `DiskEngine.swift`; the model drops what a scan says once the screen no longer belongs to it: `DiskViewModel.apply`;
- the three cache folders whose *contents* are regenerable, and the children swapped in for them: `DiskAdvisor.swift`, `DiskRemovalPlan.swift`, then `UserFileScope.partition` and `HelmTrash.remove` like any other path;
- the move to the Trash is a port with no default: `DiskEngine.init(capacity:trashing:)` takes the move and the descriptor passes `HelmTrash.moveToTrash`, so a construction that forgot it does not build, in the app or in a test; the gate stays first in `DiskEngine.trash`, `UserFileScope.partition` and then `HelmTrash.remove`, and a test hands the engine a recording move and a path the gate refuses (`DiskTrashGateTests`);
- the folder colours: eight swatches keyed by path, each a light/dark pair in an ordinary and an Increase Contrast form, and every folder's wedge, row bar and hover wash is its swatch blended into the window background inside its appearance, so the ring and the list draw one colour for a folder: `DiskPalette.swift`;
- the ring lays out one level more than it draws, and the drill lands before the animation starts: `RingView.visibleRings`, `RingView.open`.

Words: `Sources/Modules/Disk/UI/Localizable.xcstrings`; shared words through `HelmWord`.

## How Disk's model reaches its engine

`DiskViewModel` is built with the engine by the descriptor's `makeModule` and held by
the host. It calls `mountedVolumes`, `scan`, `cancel`, `trash` and `backgroundScan`
through its `DiskWork` port, which the engine conforms to, and each is answered by
return. A scan's progress and partial snapshots go to a sink the model hands over with
that call, an `AsyncStream` it drains while it awaits the answer, so they are applied on
the main actor and all of them before the answer is. There is no stream on the engine:
Disk's events exist only inside a call the model made, so there is no window between
reading a state and subscribing to its changes, and two scans walking at once (the
volume and a folder a drill measures) need no name to be told apart: the volume's walk
hands over a sink of its own, and a folder measurement passes none, so the engine builds
no snapshots for it. The gates stay in the engine: `trash` partitions through
`UserFileScope` before `HelmTrash.remove`, and the basket's `canBasket` asks
`UserFileScope.isRemovable` as well.

The model starts nothing in `init`: `makeModule` runs when the module starts, and the
saved scan (an index of every file on the volume; `ScanStore.loadDetached` says what reading it cost) and the mount observers wait for `appear()`, which the page and
the tile call from their `.task`. On the person's switch and on quit the host calls the
descriptor's `stop(_:)`, after which the model reaches no work.

## The states of the Disk page

The page id is the module id, `disk`, and a state is shot with its file `disk-<state>-<light|dark>[-<ru|de>].png`:

    bash Scripts/shoot.sh disk \
      [--press "<control name>"]... \
      --arg module.app.barAppearance flat --arg module.app.appearance <light|dark> \
      --name <state>-<light|dark> [--panel] --out <dir>

A scan of the home folder or a scratch tree is enough for every state that shows a result; the volume only where the
state needs it. Nothing on the Mac is removed to reach a state: `confirm` and `removal-report` are not shot, and the
tests hold them (`TheDialogDescribesThePressTests`, `TrashIsNotFreedSpaceTests`).

| state | the page shows | reached by |
|---|---|---|
| `start` | «Pick a volume…», one card per volume with its bar and «X free», «Scan a folder…» | module just switched on, or «Choose another…» |
| `no-disk-access` | the Full Disk Access note over any phase | Helm Dev without the grant (real use; the crew changes no grant) |
| `scanning` | `HelmBusyState` «Scanning» with Stop scan, before the first snapshot | a press on a volume card (transient) |
| `growing` | the ring growing, «Scanning…» under the figure, Stop scan in the header | the walk past its first snapshot |
| `scanned` | ring and list, «N files in S s» | a finished scan |
| `restored` | «Measured … ago» | a relaunch with a saved scan |
| `stopped` | «Stopped», the hint naming the count | Stop scan mid-walk |
| `drilled-down` | breadcrumbs, Back, the ring one level in | a click on a wedge or «Look inside» |
| `empty-folder` | «Nothing in this folder.» | drilling into an empty folder |
| `advice` | «Recommendations», reasons per row | a scan that finds a cache or an old download |
| `basket` | the bar «To remove», count and size, the basket popover | marking rows |
| `confirm`, `removal-report` | the question, «Moved to the Trash — …» | a removal: not shot |
| `worst` | ru and de at the narrowest pane: header statement and breadcrumbs give way | `--arg module.app.interfaceLanguage ru` or `de` |
| panel tile | compact, wide; tall only with two or more volumes (`DiskDescriptor.swift`) | `--panel` |

The ring's drill-down and a breadcrumb jump back are motion: a screen recording of each, not a still.
