# Removal

`HelmTrash.remove` owns the batch itself, whichever module handed it the paths: the
order, one outcome per path, one set of file ids so a hard link counts once, and the
reading of a path's size before it moves. A module keeps its gate and whatever it
knows that macOS's error does not say. The phase a removal runs under is composed
rather than literal — `HelmTrash.remove` builds `"\(module).trash"` from the caller's
id — so the shared removal path carries the name of whichever module is deleting.

Refusals are values rather than silences: `TrashFailure.Reason`
(`Sources/HelmRuntime/PermissionCheck.swift`) names each reason, and `outOfScope` is
Helm refusing before anything was attempted. `TrashFailure` classifies from the Cocoa
error code rather than from the shape of a path.

A folder's size never comes from `totalFileAllocatedSize`, which is zero for a directory
on APFS (`FileWeight`); the folder is walked. What a removal returns counts a clone
family once (`Sources/HelmRuntime/CloneShare.swift`), and a file whose family id cannot
be read counts as its own, since under-reporting is the safer error. The engine's own
gate has the last word on what is deleted, because the engine takes a list of strings
and deletes them: an empty display name once claimed `~/Library/Application Support`
itself, so a scope never widens without a test naming the new path
(`Tests/HelmRuntimeTests/RemovableScopeTests.swift`,
`Tests/HelmRuntimeTests/UserFileScopeTests.swift`).

## One removal at a time

Four modules send a `trash` command — Disk, Duplicates, Leftovers and the
Uninstaller — and a second press while the first is in flight is not a second
removal, because the files it would name are already gone: what a repeat can
only be is a refusal, and the reply that lands second overwrites the model's report
of the one that landed first. That refusal has to live in the model and not only in a
dimmed control, because a control's disabled state lags the redraw and never reaches a
row's own context menu, which draws from the same data. The model refuses; the page
dims. Both, or neither is reliable. `DiskViewModel.toggleBasket` declining while `busy`
is the same guard read from the basket's own door.

`Tests/HelmAppTests/OneRemovalAtATimeEverywhereTests.swift` fails on any file under
`Sources/Modules/` that sends a removal without the guard; the files it finds are the
output of `command grep -rln "guard !busy" Sources/Modules/`, since the count itself
does not belong in this sentence (CLAUDE.md § Where things go). Its doc comments say
why it scans by what a file **sends** rather than by what a type is named.
