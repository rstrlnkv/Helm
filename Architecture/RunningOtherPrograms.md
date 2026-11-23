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
tools `run` and `runData` have out at once, and a caller that asks for more gets a queue;
a launch through `start` (the streamed runs and the updater) takes no slot. The reason for the ceiling is the doc comment of `launchCeiling`.

Output that gets *streamed* is a different port and keeps stderr on purpose, merged
onto the one pipe (`stream` in `Sources/Modules/Homebrew/Engine/SystemPorts.swift`) — a
console shows what the tool says. Output that gets *parsed* carries no diagnostics, except `brew doctor`, whose whole answer is on standard error: `runCapturingDiagnostics` asks `HelmProcess.runData` for `standardError: .merged` and so takes a launch slot and a deadline like any query (its doc comment holds the measurement). The
stream is split into whole lines on the newline **byte** by `LineBuffer`, in the same
file, and ends at an empty read rather than at the process's exit, so the last line a
tool prints reaches the console.

A privileged command carries its content rather than a path: a staged file's path
stands in `ps auxww` while the prompt is up. The escaping is `AppleScript.literal`
(`Sources/HelmRuntime/AppleScript.swift`), and `AppleScript.administratorShellScript` is
the one place that composes the privileged line. A secret is the same: an argument stands
in `ps auxww` for every process on the Mac, so a secret a tool reads goes to its terminal,
never to its arguments, its environment, a file or the log. Hosts, which gave a tool its
passphrase through its terminal, is archived, and its code is

```bash
git show archive/hosts:Sources/Modules/Hosts/Engine/PTYProcess.swift
```

VPN's secret has no terminal form to go to, so it goes to the system in process
(Architecture/VPN.md).

A blocking call is hopped through `Sources/HelmRuntime/OffTheCooperativePool.swift`,
since an `async` engine method a model awaits runs on the Swift-concurrency pool and a process waited on or a
recursive scan parks a pool thread for seconds.

## Running applications

`NSWorkspace.runningApplications` and `.frontmostApplication` are read on the
main thread only: a read from another thread crashes the process, and moving work
off the main thread is a change to every AppKit call it can reach. The crash is on
the doc comment of `RunningApps` (`Sources/HelmRuntime/RunningApps.swift`) and of
`FrontmostApp` (`Sources/HelmRuntime/FrontmostApp.swift`).

There is no safe shape for "a live list, off the main thread", and neither port
offers one. `RunningApps` and `FrontmostApp` read AppKit on the main thread and hand
every other thread a snapshot: whoever was running, or in front, a moment ago.
`FrontmostApp` refreshes from the notification that arrives on the main thread anyway;
`RunningApps` has no observer, and the ports that watch (Keep Awake's, VPN's) call
`refreshOnMain` from theirs. Layout's fix
gesture calls through the snapshot rather than straight into AppKit, because it runs
off the main thread by construction. A port that must ask AppKit directly hops to the
main thread itself, as the Uninstaller's `WorkspaceRunningApps` does for its scan and
its quit loop, both of which run on a pool.
