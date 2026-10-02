# Disk

`Sources/Modules/Disk/` answers where the space went, so it is the one module
whose reading may not leave the largest folder out. The reasons live on the doc
comments of the code that carries them:

- both APFS mounts share a `dev_t`, and the firmlink skip set: `FirmlinkMap.swift`; the skip set matches only while paths are joined through `ScanPath.swift`; the signed `st_dev`: `BulkWalk.DeviceID`;
- folder names on screen, and why eligibility is by path: `SystemFolderNames.swift`;
- the unattended refusal of media-library bundles, by name and never by reading: `ScanRoot.refusesDescent`, used by `DiskScanner.swift`; a person watching the ring gets the whole volume, and the `~/Library` refusal is applied at the report, not at the descent: `UnattendedAdvice.swift`;
- a scan has an identity, a token only its owner can spend: `ScanRegistry.swift`; every event names its scan: `ScanTick.scan` and `PartialScan` in `DiskEngine.swift`;
- the three cache folders whose *contents* are regenerable, and the children swapped in for them: `DiskAdvisor.swift`, `DiskRemovalPlan.swift`, then `UserFileScope.partition` and `HelmTrash.remove` like any other path;
- the ring lays out one level more than it draws, and the drill lands before the animation starts: `RingView.visibleRings`, `RingView.open`.
