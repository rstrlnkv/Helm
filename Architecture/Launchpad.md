# Launchpad

`Sources/Modules/Launchpad/` is the engine of an app launcher: what is installed, how the person arranged it, what they hid. Only the engine exists so far; its UI target holds a placeholder (`Sources/Modules/Launchpad/UI/LaunchpadPlaceholder.swift`), and the registry descriptor, hotkey, strings and launching come with the UI. The reasons live on the doc comments of the code that carries them:

- an app is its bundle id and nothing else is stored; a path belongs to the latest catalog read, so a planted layout file cannot make Helm launch a path: `Sources/Modules/Launchpad/Engine/Logic/LaunchpadLayout.swift`;
- the three roots, the walk judged by name and one `lstat`, the duplicate rule (earlier root, then smallest path), and why Safari is no fourth root: `SystemPorts.swift` (`FileSystemAppCatalog`);
- a read that was not `complete` drops nothing, and a read never writes: `Sources/Modules/Launchpad/Engine/Logic/LaunchpadReconcile.swift`, `LaunchpadEngine.swift`;
- the layout file is private, bounded, and a bad one is moved aside once before the first save: `LayoutStore.swift`, `Sources/Modules/Launchpad/Engine/Logic/LayoutCoding.swift`, `Sources/Modules/Launchpad/Engine/Logic/LaunchpadLimits.swift`.

## The catalog and the layout

`AppCatalogPort.read()` is pull-only; a change in the installed set is seen on the next read. An absent or empty root reads as empty and complete; a root that exists but will not open, or a walk stopped at the ceiling on apps, makes `CatalogReading.complete` false. The layout is saved only on a person's edit (`LaunchpadEngine.apply`), through one lock over read, reconcile, edit and save; only the latest catalog read is kept (an edit reconciles against it; the layout is read afresh each time) and the calls block on disk, so a model hops with `offTheCooperativePool`.

A hidden app leaves its folder. The module is not a `BackgroundScanning` module: it is read on demand with the person present, and has no report. The layout is not a sealed setting: it reorders and hides and names no path.
