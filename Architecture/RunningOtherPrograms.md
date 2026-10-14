# Running other programs

`Sources/HelmLaunch` is the package's only non-Swift target: `NSTask` raises on some
launch paths and the `@try`/`@catch` has to sit in Objective-C, with no Swift frame
between it and the raise; `HelmReadNumber` has the same `@try` around a call to a window's own getter for
`WindowCorner`, and catches anything thrown there, not only an `NSException`. The reasons
are on the doc comments of `HelmLaunchTask`, `HelmLaunchExceptionNameKey` and `HelmReadNumber` in `Sources/HelmLaunch/include/HelmLaunch.h`.
`Tests/HelmAppTests/NoBareLaunchInTheShellTests.swift` refuses a bare
`try process.run()` anywhere but `HelmProcess`'s own door.

`Sources/HelmRuntime/HelmProcess.swift` is the one way to run a tool, and its doc
comments hold the rules: output is read to the end before the wait; stderr is the null
device where nobody parses it, never an undrained `Pipe`; `launchCeiling` bounds how many
tools `run` and `runData` have out at once, and a caller that asks for more gets a queue,
which a bounded run leaves at its deadline with `timedOutStatus`, its tool unstarted.
The ceiling exists because Homebrew's search once put every press of Return on its own
unbounded `Task`; the doc comment of `launchCeiling` tells it. A bounded run's deadline
counts from the call; past it the tool's process group gets TERM and, after a grace,
KILL if its output is still held or the tool unreaped, and the run's slot comes back
when the tool and whatever else holds its pipe are gone, or as the run returns if the
tool is then reaped and its group empty — the doc comments of the bounded `run` and of
`signalTree` say when and why. `start` takes no slot and no deadline, for the reason on
its doc comment; its callers are the updater in `Sources/HelmApp/Installer.swift`, and
`stream` and `runCapturingDiagnostics` in
`Sources/Modules/Homebrew/Engine/SystemPorts.swift`. The Hosts module's terminal child
(`Sources/Modules/Hosts/Engine/PTYProcess.swift`) is spawned outside `HelmProcess`
altogether, in a session of its own.

Output that gets *streamed* is a different port and keeps stderr on purpose, merged
onto the one pipe (`stream` in `Sources/Modules/Homebrew/Engine/SystemPorts.swift`) — a
console shows what the tool says. Output that gets *parsed* carries no diagnostics. The
stream is split into whole lines on the newline **byte** by `LineBuffer`, in the same
file, and ends at an empty read rather than at the process's exit, so the last line a
tool prints reaches the console.

A privileged command carries its content rather than a path: a staged file's path
stands in `ps auxww` while the prompt is up. The escaping is `AppleScript.literal`
(`Sources/HelmRuntime/AppleScript.swift`), and `AppleScript.administratorShellScript` is
the one place that composes the privileged line.

A blocking call is hopped through `Sources/HelmRuntime/OffTheCooperativePool.swift`,
since a transport handler runs on the Swift-concurrency pool and a process waited on or a
recursive scan parks a pool thread for seconds.
