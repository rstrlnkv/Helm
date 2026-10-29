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

## How the Uninstaller's model reaches its engine

`UninstallerViewModel` is built with the engine by the descriptor's `makeModule` and held
by the host. It calls the engine through its `UninstallerWork` port, which the engine
conforms to, and every answer is a return: the app list, the sizes, the last-opened
dates, the scan of one app, the orphan scan, a batch to the Trash, the Trash sweep, the
switch's state and the background scan. The gates stay in the engine and are not
reached around: `trashPaths` asks who is up, quits, asks again, partitions through
`RemovableScope` and only then hands each path to `HelmTrash.remove` through the
`trashItem` port.

The one thing the engine says unasked, that an app reached the Trash, is not a call of
the model's. The engine is built with a `trashChanged` closure; the descriptor makes it
yield into a one-slot `AsyncStream` that the model reads in `listenForTrash`, once for
the life of the module. With the Trash offer open the arrival goes to the offer, which
takes the new app into the list it shows; otherwise it goes to the host's handler, which
opens the window. The offer registers on the model (`openOffer`) before its first read,
so an arrival between the read and the registration is not lost.
`AStoppedUninstallerModelReachesNoWorkTests.testAnArrivalWithTheOfferOpenGoesToTheOffer`
holds the routing.

The host reaches the trash window through the live module's model with one `as?` in
`AppDelegate`; a model that is not an `UninstallerViewModel` is logged and there is no
offer. `TrashedAppOffer.sweep(uvm:onClose:)` is the one door that returns a view or
nothing. On the person's switch and on quit the host calls the descriptor's `stop(_:)`:
the model then reaches no work, shows no list or review still in flight, and lets go of the
arrival subscription and the open offer; saving a chosen sort order is not refused.

The model keeps no state for a reply that never arrives, and the Apps tab has two empty
states, no apps found and a search that hides all of them: before the first answer the
page draws a spinner and the footer says "Counting apps…" (`AppsEmpty.status(answered:loading:apps:)`).
