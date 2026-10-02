# Running applications

`NSWorkspace.runningApplications` and `.frontmostApplication` are read on the
main thread only. A read from another thread does not go stale — it crashes the
process, and moving work off the main thread is a change to every AppKit call it can
reach. The stack trace and the VPN engine's crash are on the doc comment of
`RunningApps` (`Sources/HelmRuntime/RunningApps.swift`); Layout's fix gesture proving
it a second time over `frontmostApplication` is on `FrontmostApp`
(`Sources/HelmRuntime/FrontmostApp.swift`).

There is no safe shape for "a live list, off the main thread", and neither port
offers one. `RunningApps` and `FrontmostApp` read where AppKit publishes — on the
main thread, from the notification that arrives there anyway — and hand every other
thread a snapshot: whoever was running, or in front, a moment ago. Layout's fix
gesture calls through the snapshot rather than straight into AppKit, because it runs
off the main thread by construction. A port that must ask AppKit directly hops to the
main thread itself, as the Uninstaller's `WorkspaceRunningApps` does for its scan and
its quit loop, both of which run on a pool.
