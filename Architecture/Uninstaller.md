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

Words: `Sources/Modules/Uninstaller/UI/Localizable.xcstrings`; interpolated ones in inline tables in `UninstallerStrings.swift`; shared words through `L()`, and the removal's sentence through `HelmBasket` in `Sources/HelmUI/BasketStrings.swift`.

## The states of the Uninstaller page

The page id is the module id, `uninstaller`, and a state is shot with its file `uninstaller-<state>-<light|dark>[-<ru|de>].png`:

    bash Scripts/shoot.sh uninstaller \
      [--press "<name>" [--nth <n>]]... \
      --arg module.app.appearance <light|dark> \
      [--arg module.app.interfaceLanguage <ru|de>] \
      --name <state>-<light|dark>[-<ru|de>] --out <dir>

Nothing is removed or quit to reach a state: the presses only tick, open the review and scan. `confirm`, `removing`, `removal-report` and the failure list are not shot. The removal report on the review is held by `TheReviewIsNotTheLastWordTests`, its verdict by `RemovalOutcomeTests` (optional); the Trash window's busy flag by `TheTrashOfferSendsOneBatchTests`, its refusal at the close by `ARefusalIsNotADeclineAtTheCloseTests` (optional); a second press on the Leftovers tab by `TheOrphansTabRefusesASecondPressTests`, which reads the source. The confirmation, the page's "Removing…" and the failure list have no guard.

| state | the page shows | reached by |
|---|---|---|
| `counting` | `HelmBusyState`, and "Counting apps…" in the footer | not caught by `shoot.sh` or a rectangle burst on this Mac: the list arrived before the window was first on screen; no test holds the page's frame |
| `apps` | the striped list of apps, the footer with the count | the page as it opens |
| `apps-basket` | the footer with "N selected · size" and Review N | `--press "<app>"` on `apps` |
| `review` | one group per app, its bundle first with "The app itself — always removed", and Move to Trash | `apps-basket`, then `--press "Review 1"` |
| `review-running` | the warning "Still running: …" with the force-quit switch over the review | `review` with a running app ticked |
| `orphans-start` | the invitation to scan, and the switch for the Trash below | `--press "Leftovers" --nth <n>` (the sidebar row shares the name) |
| `orphans` | the leftovers grouped by bundle id, nothing ticked | `orphans-start`, then `--press "Scan for leftovers"` |
| `orphans-none` | "No leftovers found." with Scan again | `orphans`, only when this Mac has none |
| `orphans-basket` | "N selected · size" and Move to Trash enabled | `orphans`, then `--press "Select all"` |
| `no-disk-access` | the Full Disk Access note over any of the above | Helm Dev without the grant (real use; the crew changes no grant) |
| `trash-offer` | the Trash window: the standing line, one card per app, Keep these files | only when the real Trash already holds an app with leftovers |
