# Launchpad

`Sources/Modules/Launchpad/` is an app launcher: what is installed, how the person arranged it, what they hid. The engine (`Engine/`) reads, edits and launches; the UI (`UI/`) is one module page, registered in `Sources/HelmApp/ModuleRegistry.swift` (`LaunchpadDescriptor`). There is no overlay and no hotkey yet. The reasons live on the doc comments of the code that carries them:

- an app is its bundle id and nothing else is stored; a path belongs to the latest catalog read, so a planted layout file cannot make Helm launch a path: `Sources/Modules/Launchpad/Engine/Logic/LaunchpadLayout.swift`;
- the three roots, the walk judged by name and one `lstat`, the duplicate rule (earlier root, then smallest path), and why Safari is no fourth root: `SystemPorts.swift` (`FileSystemAppCatalog`);
- a read that was not `complete` drops nothing, and a read never writes: `Sources/Modules/Launchpad/Engine/Logic/LaunchpadReconcile.swift`, `LaunchpadEngine.swift`;
- every file read out of a bundle (`Info.plist`, `InfoPlist.strings` of the lproj `Bundle.preferredLocalizations` picks) goes through one reader that opens without blocking, follows no link at the last component, takes a regular file only and stops at `LaunchpadLimits.maxFileBytes`, so a pipe or a huge file planted in a bundle cannot hold the walk: `SystemPorts.swift` (`cappedRead`);
- a tile is at least `LaunchpadMetrics.tileMinimum` (132 pt) wide, a constant chosen from the widest unbreakable German word measured ("Datenträgerverwaltung", 120.5 pt at the subheadline font) and says its name in `.help`; the folder popover is three of them: `Sources/Modules/Launchpad/UI/LaunchpadTiles.swift`;
- the layout file is private, bounded, and a bad one is moved aside once before the first save: `LayoutStore.swift`, `Sources/Modules/Launchpad/Engine/Logic/LayoutCoding.swift`, `Sources/Modules/Launchpad/Engine/Logic/LaunchpadLimits.swift`.

## The catalog and the layout

`AppCatalogPort.read()` is pull-only; a change in the installed set is seen on the next read, and `observeChanges` tells the model when to ask (`CatalogChange.concerns` in `Sources/Modules/Launchpad/Engine/Logic/CatalogChange.swift` keeps a path that ends at an `.app` or at the `Info.plist` inside its `Contents`, and a path with no `.app` component unless its last component is hidden). An absent or empty root reads as empty and complete; a root that exists but will not open, or a walk stopped at the ceiling on apps, makes `CatalogReading.complete` false. The layout is saved only on a person's edit (`LaunchpadEngine.apply`), through one lock over read, reconcile, edit and save; only the latest catalog read is kept (an edit reconciles against it; the layout is read afresh each time) and the calls block on disk, so a model hops with `offTheCooperativePool`.

A hidden app leaves its folder. The module is not a `BackgroundScanning` module: it is read on demand with the person present, and has no report. The layout is not a sealed setting: it reorders and hides and names no path.

## How Launchpad's model reaches its engine

`LaunchpadViewModel` (`Sources/Modules/Launchpad/UI/LaunchpadViewModel.swift`) is built with the engine by the descriptor's `makeModule` and held by the host. It reaches the engine only through its `LaunchpadWork` port, which `LaunchpadEngine` conforms to: `read`, `hide`, `unhide`, `launch`, `observeChanges`. Every blocking call hops off the main actor with `offTheCooperativePool`, and its answer is dropped when a newer request exists or the model was stopped: a snapshot by a newer read, a notice by a newer edit or launch (`LaunchpadViewModel.acts`). A launch's notice names the app on the tile that was pressed, taken before the launch.

A launch is resolved in the engine, not the model: `launch(id)` reads the catalog afresh, finds the id, asks the bundle at that fresh path for its id and only then hands the URL to `AppLauncherPort` (`Sources/Modules/Launchpad/Engine/Logic/LaunchResolution.swift`). A path never comes from the layout file or from the page's last snapshot. The answer is a `LaunchOutcome` (launched, gone, unreadable, failed); the model turns the last three into a notice. `SystemAppLauncher` (`Sources/Modules/Launchpad/Engine/SystemPorts.swift`) is the only code that opens an app, and in a test process it answers false and calls nothing (`TheSuiteDoesNotLaunchAppsTests`).

The model starts nothing in `init`. The page's `.task` calls `whileShown()`, which subscribes to the catalog watch before its first read, so no change falls between the two; the token it gets is local to that task, so leaving the page cancels the task and stops the watch. Events are buffered to one, so a burst is one more read. On the person's switch and on quit the host calls the descriptor's `stop(_:)`, after which the model reaches no work.

## The states of the Launchpad page

The page id is the module id, `launchpad`. The page is a grid of tiles under the header search; which state shows follows the model's `snapshot` and the search text:

- busy: `snapshot` is nil, the engine has not answered yet;
- empty: the answer holds no app, one statement, no verb;
- no match: the search is not blank and `LaunchpadSnapshot.search` found nothing;
- search results: a flat grid of the found apps, no folders, no hidden section;
- the layout: app tiles and folder tiles in the saved order; a folder tile opens a popover over its apps, which closes when the folder is gone or an app in it is launched; below the grid a collapsed Hidden section, shown only while something is hidden, opens by clipped measured height and lists each app with a Show button;
- a notice banner above the grid, no button: an app that is no longer installed, an app that could not be opened, an arrangement that was not saved. It has no timer; a launch that succeeds, a hide or a show, and the page's next appearance clear it; a failed launch replaces it.

A state is shot with `bash Scripts/shoot.sh launchpad ... --name <state>-<light|dark>` as the Disk page's states are (§ The states of the Disk page in `Architecture/Disk.md`). Nothing on the Mac is launched or removed to reach a state.
