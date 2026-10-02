# Uninstaller

`Sources/Modules/Uninstaller/` removes an application and the files it left behind,
which makes "does this path belong to the app being removed" the whole question at
its boundary.

A path a pattern produced is a candidate rather than a finding, and glob results
are filtered against the installed set two ways at once:
`AppLister.installedBundleIDs()` reads the directory listing and
`AppLister.isKnownToSystem` asks LaunchServices, which sees what a listing cannot.
The exact candidates go through the same filter, via
`AppLister.installedPaths(forBundleID:)`, because their hazard is different.
`Sources/Modules/Uninstaller/Engine/Logic/LeftoverOwnership.swift` is where that
verdict is formed and holds the rules; `OrphanDetector.swift` and `SystemApp.swift`
in the same folder say why they are conservative and why macOS's own apps never
reach the checkbox.

Quitting is asked rather than assumed. `UninstallerEngine.waitUntilGone` polls to a
deadline, and the deadline ends the *wait* rather than the question:
`UninstallPlan.verdict(running:mayQuit:)` is asked again after the quit loop in
`removeBatch`, and a batch still holding a live app moves nothing and names it in
`stillRunning`, its own field on `UninstallResult` (the doc comment on
`stillRunning` says why it is not a classified failure).

The quit is by bundle identifier and reaches every copy of the app that is running;
`RunningAppsPort.quit(bundleID:force:)` says what that costs the fakes.
