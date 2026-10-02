# Running other programs

`Sources/HelmLaunch` is the package's only non-Swift target: `NSTask` raises on some
launch paths and the `@try`/`@catch` has to sit in Objective-C, with no Swift frame
between it and the raise. The reasons are on the doc comments of `HelmLaunchTask` and
`HelmLaunchExceptionNameKey` in `Sources/HelmLaunch/include/HelmLaunch.h`.
`Tests/HelmAppTests/NoBareLaunchInTheShellTests.swift` refuses a bare
`try process.run()` anywhere but `HelmProcess`'s own door.

`Sources/HelmRuntime/HelmProcess.swift` is the one way to run a tool, and its doc
comments hold the rules: output is read to the end before the wait; stderr is the null
device where nobody parses it, never an undrained `Pipe`; `launchCeiling` bounds how many
tools are out at once, and a caller that asks for more gets a queue.

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
