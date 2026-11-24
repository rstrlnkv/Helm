# State and lifetime

## State that outlives a page and ends with its module

A module's UI state outlives its page and not its module. Settings rebuilds a page on
every sidebar visit, so a model is held outside the page, by the host. The on-disk scan cache is untouched when the model goes: the copy in memory goes, the answer stays.
A module that owns its model ends it in `stop(_:)` (`Sources/HelmUI/ModuleDescriptor.swift`),
which `Sources/HelmApp/ModuleHost.swift` calls before the engine's `deactivate()`; the model
then goes with the module's `Live`.

The host is only one of a model's two owners. A subscriber task started as
`Task { [weak self] in await self?.observeEvents() }` resolves its weak capture once, and
the method then holds `self` for as long as it runs — which, over a stream that does
not finish, is the life of the app. The tasks are therefore held and
cancelled from the class's own teardown rather than from `deinit`.
`EngineNews.subscriberCount` makes the guard a count rather than a
memory figure: `Tests/HelmContractTests/EngineNewsReplayTests.swift` (`testACancelledConsumerLeavesTheCountAndOnlyIt`) and
`Tests/HelmAppTests/ASwitchedOffModuleLetsItsSubscriberGoTests.swift`.

A mounted SwiftUI tree is billed whether or not anybody can see it; `Sources/HelmUI/DesignSystem/OffScreenIdle.swift`
(its doc comment holds the numbers) unmounts a
subtree while its window is out of sight and rebuilds it from the view model's current
state, and the model keeps its subscription throughout. It reaches a
module page from the window and not from the page: both hosting controllers that
`SettingsShellViewController.makeShell` (`Sources/HelmApp/SettingsWindow.swift`)
builds end on `helmIdlesOffScreen()` (the one hosting `ShellSidebar`, the one
hosting `SettingsDetail`), so a page inherits the idling. `helmSettingsColumn()` ends on the same
modifier; a page whose root is a `Form` takes no column and calls `helmIdlesOffScreen()` on its own
(`Sources/Modules/Layout/UI/LayoutSettingsPage.swift`). A harness that leaves its window
unordered declares itself with `helmMeasuringBench()`, which the app itself
does not. The panel window is not gated this way.

## An observer outlives the thing it points at

An observer, a timer or a system port an engine or a view model starts is taken down
twice: once in `deactivate()` and again in `deinit`. Both are needed because
`deactivate()` is not guaranteed on every route out, and a `deinit` alone is not enough
either where the thing observed keeps its own reference — the run loop holds a
repeating `Timer` for as long as it is armed, so the timer outlives whatever created it
until something calls `invalidate()`, `deinit` included. `RepeatingTick.set(active:)`
(`Sources/HelmRuntime/RepeatingTick.swift`) has the timer's own callback find its owner
already gone and invalidate itself. The sidebar's fold takes its display link down twice too: `DisplayFoldLink`
(`Sources/HelmApp/FoldLink.swift`) gives the system's link a target that holds only the tick closure, never the view,
and invalidates the link in `stop()` and in its own `deinit`.

`VPNEngine` stops its network observer from both `deactivate()` and `deinit`, because a
callback left holding a dropped engine points at freed memory the moment the port fires again;
`NetworkWatchPort.stopObserving` states the same rule from the port's own side.
`Tests/Modules/VPN/EngineTests/VPNNetworkWatchTests.swift` guards both halves. A
missing `deinit` fails as a crash on whichever call happens to
land on the freed object next. `DiskViewModel` keeps the token of the capacity port's change channel
(`VolumeCapacityPort.observeChanges`, answered in `Sources/Modules/Disk/Engine/SystemPorts.swift`) in a
property whose own lifetime ends it, so a view model dropped when the module is switched
off is not woken by the next disk somebody plugs in.

An unretained C context is not repaired by retaining it: a retained context keeps the
object alive until the port is invalidated, and only the object's own teardown
invalidates it, which is a cycle in which a switched-off module goes on reading every
keystroke. The doc comment of `CGKeyTap` (`Sources/Modules/Layout/Engine/SystemPorts.swift`)
has the measurements, and says what invalidating the mach port does and does not fix.
A run loop source is removed **and** invalidated, because removal takes it off this run
loop and invalidation stops the callback already scheduled, which is the one that lands
on the freed object (`Sources/Modules/KeepAwake/Engine/SystemPorts.swift`). A module
that is already live is not bootstrapped again (`ModuleHost.bootstrap`), because
assigning a fresh engine over a live one orphans whatever the old one registered.

The system withdraws an observer on its own. An event tap is disabled for timeout and for
user input, and revoked when the grant is withdrawn, and the only announcement is an event
of that disabling type arriving down the tap
(`Sources/Modules/Layout/Engine/Logic/TapDisabled.swift`). Anything derived from an event
stream has an event that clears it and a case where that event never comes: every event
carries the live modifier flags and no release is guaranteed, so one code left behind
spoils every tap from then on, silently.

## A value read back whole

Completeness is judged on every part of a value. One predicate answers the switch, the store and a hand-edited file, and a scan's
completeness is never read from a flag that is true while the walk is running, or a
save door taken mid-walk writes a partial result the module reopens on, labelled as
measured. A condition left blank can be an all-matcher, which with a destructive action is a working rule three
gestures away.

An older encoded payload is not made to decode by a defaulted property: the synthesised
decoding requires the coding key and gives up on the whole document, so the initialiser is written by hand and
the later fields are read as optional-if-present.
