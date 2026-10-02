# Background scans

A few modules can measure with nobody watching. `ScanRunner.scannableModules`
(`Sources/HelmRuntime/ScanRunner.swift`) is a literal list of their ids, spelled out
because a module gaining a scan costs a walk of the volume. The list and the
capability are tied by a test: a scanning module conforms its engine to
`BackgroundScanning` (`Sources/HelmRuntime/ScanReport.swift`) and enters the list, and
`Tests/HelmAppTests/ListsAgreeWithTheTreeTests.swift` fails on either half missing.

The clock and the decision are in different targets.
`Sources/HelmApp/ScanCoordinator.swift` owns the one-minute tick, the notification
observer, the reading of live system counters and the transport call;
`Sources/HelmRuntime/ScanSchedule.swift` and `ScanRunner.swift` are pure and decide.
Every refusal is a named verdict (the cases of `ScanSchedule.Verdict`), and it is logged on
change only, because a line per module per minute would push everything else out of the
bounded tail.

Two of the conditions are less obvious than they look. Helm resets the idle counter
itself through Keep Awake's pointer jiggle, so `ScanRunner.advance` keeps an estimate
across ticks rather than trusting one reading, and stays at or above the counter. And
idleness is not evidence under fast user switching, so the console session and the
lock state are read as well.

What crosses the transport is deliberately thin: `ScanReport` is bytes, a count and a
list of path and size, the shape unlike scanners can all speak, and nil is not an empty
report. `ScanJournal` keeps the numbers for the last scans per module and the item lists
for the newest two, stores no localized text, and redirects itself out of the real
Application Support under test. It sweeps its own abandoned siblings, and the risk is in
the judgement rather than the removal: `abandonedTestJournals` is pure and tested,
liveness is asked of the kernel, and the sanity check on the number lives inside the
decision rather than beside the kill.

`ScanComparison` is the arithmetic on those two lists and carries whether there was a
previous one at all; `ScanNews` turns that into something worth saying, measured on
appeared bytes alone, and reaches macOS through the one notification conversation in
`NoticeChannel`. An attempt and a completion are two facts: a completion holds a module
for the interval, an attempt for the shorter retry interval, and the attempt is written
before the work so a crash mid-walk costs the gap rather than nothing.
