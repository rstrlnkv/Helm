# Diagnostics log

`~/Library/Logs/Helm/helm.log`, two megabytes and then one rollover (`HelmLog.sizeLimit`),
in a folder created 0700 (`PrivateFile.directory(at:)`). `LogPolicy.isEnabled` answers
whether it logs at all and `LogDestination` where it lives: every `-dev` build logs
whatever was saved, and a beta build stays silent until its owner turns on the «Write a
log file» item of the «More actions» menu on the Log page's window toolbar.

What the installed build says about itself is read from that file rather than assumed: the
lines tagged "permissions" (`Sources/HelmApp/PermissionAudit.swift`) state which grants it
actually holds, which no setting on screen can tell you.

A failure that cannot be triaged is recorded rather than logged: `HelmLog.warn`, `.error`
and `HelmLog.failure` capture where they were called from, and `HelmLog.failure` unwraps
the error through `HelmFailure.describe`; `info` does not capture (the doc comments on
`HelmLog` and `HelmFailure` hold the reasons).

`Redact` is what goes into the file in place of a name — a VPN connection, a bundle id, a
package: names that say whose machine it is and what its owner does with it. A bundle id
names a person's habits, so the app-cleanup modules write `Redact.app` and not the path
alone. The tag is a salted FNV-1a rather than a hash of the bare name, because a keyless
hash of a name drawn from a small public list is an index into that list; the salt is per
install, in a `0600` file beside the log.

Two things follow the file rather than the process. The one-time purge records that it
has run in a file beside the log rather than in `UserDefaults`, which is namespaced per
process: a latch belongs to what it guards, not to whoever asks, and any binary linking
`HelmRuntime` ran the purge again against the one real log. And a test runner writes into
a folder of its own (`LogDestination.directory(home:temporary:underTest:)`), because the
rollover, the purge latch and the salt all belong beside whatever file is real; whether
this is a test runner is answered once, by `TestProcess.isRunning`.

A line is logged for a refusal and never for an absence. A VPN credential cache that macOS
will not hand to a new build is a refusal, logged with its status
(`Sources/Modules/VPN/Engine/SystemPorts.swift`); "no cached credentials" had folded it
with absence, and an investigation went looking for a purge that had run hours earlier.
A line reporting on the state of the
world is run against an ordinary machine and its silences counted before it ships; if the
answer is "rarely", the design is wrong however good the filter is.

## The activity registry

`Sources/HelmRuntime/HelmActivity.swift` is the registry of named phases — what is
running *now*. `HelmActivity.phase(_:_:)` closes the phase on return, on throw and on
cancellation. `begin`/`end` is the pair for a body the closure cannot take. It is used
only with a `defer` on the very next line, and only where the phase is the whole body of
an asynchronous function, because a `defer` ends at the end of the function and so is the
end of the phase only there; the balance-by-hand the phase call replaces caused
cancel-path defects. The label goes on the shared path rather than at each call site, as
`HelmTrash` does with `"\(module).trash"` (ARCHITECTURE.md § Removal), so every module
deleting through `HelmTrash` carries the name and a new one cannot forget to.
`HelmActivity.sweep(module:)` is called from `ModuleHost.shutdown` and
`ModuleHost.disable`, so an interval nobody closed cannot go on naming a module that has
been dropped.

The labels are not listed in prose. What exists is what
`command grep -rhoE 'HelmActivity\.(phase|begin)\("[^"]+"' Sources | sort -u` prints.
An empty registry renders as `no phases running`, which is what the registry knows and no
statement about the app: the SwiftUI render, a VPN refresh, the update check and the trash
sweep all run outside it (`HelmActivity.describe`).

## The memory trail

`HelmLog.memory(_:)` is the other instrument: the process footprint under the `memory`
category, as a delta against the last reading for the same label, with
`HelmActivity.describe` appended. The figure is `phys_footprint`, which `MemoryFootprint`
explains, and `FootprintTracker` holds the accounting and the threshold. The second
overload, `memory(_:grewBy:)`, reports a bounded scope from two readings around it and has
no threshold (`ScopeCost`).

`MemoryFootprint.current()` is the *process* cost. A **per-object** cost is read from
the allocator's own books — `malloc_zone_statistics`' `size_in_use`. Every walk with a
budget carries its ceiling as a file rather than as a paragraph, per entry or per item:
`Tests/Modules/Disk/EngineTests/ScanFootprintTests.swift`,
`Tests/Modules/Leftovers/EngineTests/AScanKeepsWhatItFoundTests.swift`,
`Tests/Modules/Duplicates/EngineTests/WalkFootprintTests.swift` and
`Tests/HelmRuntimeTests/ReleaseDigestFootprintTests.swift`, with
`Tests/HelmRuntimeTests/MemoryTrailCoverageTests.swift` holding the list of phases
obliged to carry a reading at all.

`Tests/Support/ThreadAllocations.swift` judges one call by the requests it made and never
by a high-water sampled from those books, which are the whole process's (its doc comment
holds the measurement). A memory peak is never attributed to a neighbouring log line; the
same signature is looked for in a run where the suspect was idle, and the log that raised
the suspicion usually holds the run that settles it. Bulk phases carry both the named
interval and the memory reading or stay out of the trail, and the trail never says the app
is idle (ARCHITECTURE.md § The activity registry).

## The log pane

`Sources/HelmApp/LogView.swift` is the same lines readable while they are being written,
on every build. It computes nothing about the file: one `write`, one format, and the pane
is a window onto it. Its controls live in the settings window's own toolbar rather than
in a band of the page (`LogView.toolbarContent`), so the place a person is sent to when
they report a problem is the one named after it.

Each launch is **a card** (under a filter, one with nothing to show has none), and what a
launch is comes out of the lines themselves, in pure functions in
`Sources/HelmApp/LogSessions.swift` and not in the view, so a fixture can be handed to them.
Nothing is dropped or reordered on the way: the cards joined are the tail. Which of them the
page draws is a separate matter, below. Two known defects are in the defect log:
`log-earlier-launch-search`, no query finds a card by «Earlier launch», and
`log-span-zh-ja`, a day span across midnight is written by the system's interval
formatter, which in Chinese and Japanese is numerals beside long-form day headings.

`Sources/HelmRuntime/LogTail.swift` is the in-memory tail, bounded by `LogTail.standardLimit` and trimmed
from the front. It is filled from the parts a file line is spelled from rather than by
parsing the line back apart. `Sources/HelmRuntime/LogSeed.swift` is the one exception and
says so in its own first line: a seed has no parts to hold, so it parses — once, in a
type whose name says so, as the exact inverse of the format, and reading a stamp once a
minute rather than once a line. It seeds from this process's log files and their
predecessor on disk, so the pane is not limited to what this process happened to write.

The pane follows the newest line by its identity rather than by the tail's count — the
count is the limit for ever once the tail is full. While Follow is lit and the view is at
the end the scroll view holds it (`defaultScrollAnchor`), and `LogReaderPlace` asks for
the end again when it has been missed; a card's rows are plain up to `LogView.lazyAbove`
and lazy above it, so the height of a large card is an estimate until its rows are drawn.
A reader who is not at the end is held by the line at the top of the view and not by the
scroll offset (`LogReaderPlace`), with one known exception, a line taller than the room
below it, which the hold itself moves; a reader inside a larger card is held no better
than the lazy estimate allows.

Which launches are drawn is bounded, because a stack lays out every row it is given: the
rows laid out at open are those of the newest launches, not of the whole tail. At open the
page draws the newest launch and, before it, the nearest older launches, whole, while those
older ones hold fewer than `LogView.drawnAtOpen` rows between them
(`LogPresentation.drawn(rowsBefore:)`; a launch is never split). The figure is a threshold
reached or passed, so the last launch added may take the older ones well past it, and a log
of many launches each under `LogView.lazyAbove` draws fewer than `drawnAtOpen` plus twice
`lazyAbove` rows at open: a bound that depends on both figures and is not tight. The newest
launch is outside the count and is drawn whole, because it is the only one that grows: a
line entering it cannot move the cut. A line that opens a new launch can, since the launch
that was the newest is counted from then on, and the oldest launches drawn may leave the
page from above.

A reader who comes to rest within a view's height of the top of what is drawn, with a
remembered line or with Follow lit at the end holding the view, asks for earlier launches
(`LogReaderPlace.drawEarlier`; it is made at rest only, never from a scroll). An ask draws
at least one launch more whenever one is not drawn: the page keeps a count of doublings of
`drawnAtOpen` and the ask raises it to the nearest count that adds a launch
(`LogView.earlierAfterAsk`), building the presentation once for it. What is drawn never
shrinks because of an ask. Once every launch is drawn an ask writes no state, so the page is
not redrawn and the toolbar not declared again. A tail at its cap is wholly drawn after
as many doublings of `drawnAtOpen` as it takes to reach `HelmLog.tailLimit`, so at most that many
asks write anything; the next finds nothing to draw. A launch that is not drawn is not in the content and takes no height, so
the place of a drawn line is still a measurement where its rows are plain (a card over
`lazyAbove` rows is lazy and its height an estimate), and the hold above is as exact as it
was.
«Copy log» and the footer's counts are
over the whole presentation, not over the cards drawn.
