# Disk

`Sources/Modules/Disk/` answers where the space went, so it is the one module
whose reading may not leave the largest folder out. The reasons live on the doc
comments of the code that carries them:

- both APFS mounts share a `dev_t`, and the firmlink skip set: `FirmlinkMap.swift`; the skip set matches only while paths are joined through `ScanPath.swift`; the signed `st_dev`: `BulkWalk.DeviceID`;
- folder names on screen, and why eligibility is by path: `SystemFolderNames.swift`;
- the unattended refusal of media-library bundles, by name and never by reading: `ScanRoot.refusesDescent`, used by `DiskScanner.swift`; a person watching the ring gets the whole volume, and the `~/Library` refusal is applied at the report, not at the descent: `UnattendedAdvice.swift`;
- a scan has an identity, a token only its owner can spend: `ScanRegistry.swift`; what a scan says while it runs goes to the sink of that one call, so no update has to name its scan: `DiskScanUpdate` in `DiskEngine.swift`; the model drops what a scan says once the screen no longer belongs to it: `DiskViewModel.apply`;
- the three cache folders whose *contents* are regenerable, and the children swapped in for them: `DiskAdvisor.swift`, `DiskRemovalPlan.swift`, then `UserFileScope.partition` and `HelmTrash.remove` like any other path;
- the ring lays out one level more than it draws, and the drill lands before the animation starts: `RingView.visibleRings`, `RingView.open`.

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
