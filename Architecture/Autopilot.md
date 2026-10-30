# Autopilot

`Sources/Modules/Autopilot/` acts on somebody's files without being asked each
time, so its boundary is a set of refusals rather than a set of capabilities.

Rules live in a plist any process running as the user can write, so they are sealed
with a key from Helm's own login keychain (`RuleKeychain.swift`); how the seal is
judged, migrated and locked is ARCHITECTURE.md § Sealed settings. A rule set whose
seal disagrees decodes to `[]`, so none of its rules runs, and `rulesRefused` on
`AutopilotEngine` is the same verdict as a flag.

`WatchScope` bounds what even a rule Helm itself sealed may reach, and the action
set is closed: there is no script action, and `command grep -rn 'case script\|runScript\|shellAction' Sources/Modules/Autopilot/`
prints nothing. The reasons are on the doc comments of `RuleAction.swift` and
`WatchScope.swift`.

A stamp that will not stick is logged and tolerated, which is survivable only
because sorting, moving and tagging recognise a file already where the rule would
put it, and renaming tells "already done" from "do it again" by inspecting the name
against `RenameShape.swift`.

Which volumes cannot keep the stamp is not every removable one: a filesystem that
refuses extended attributes, or an AppleDouble `._name` sidecar something drops,
on the `/Volumes` that `WatchScope` admits. exFAT is not among them: on macOS 27.2 an
`hdiutil create -fs ExFAT` image took `xattr -w` and kept it, in a `._name` sidecar.

Three triggers reach the runner and none covers the others; each names itself
while it runs:

```bash
command grep -o 'autopilot\.[a-zA-Z]*' \
  Sources/Modules/Autopilot/Engine/AutopilotEngine.swift | sort -u
```

The history is a second sealed document in the same plist. Why a forged record
matters and what a return checks is the doc comment of `UndoRunner`; a history
seal that fails to verify freezes the history rather than being overwritten or
deleted (`AutopilotEngine.remember`).

A per-rule fact stays per-rule, and a module macOS is blocking is marked from the declared
permission and not from the switch. A module-wide suppression marked on every switched-on
rule says "paused" about rules that are merely waiting, and a page reading its own enabled
flag shows "Active" for a module that has been inert all session.

## How Autopilot's model reaches its engine

`AutopilotViewModel` is built with the engine by the descriptor's `makeModule` and held by
the host for the life of the module, so it asks the engine nothing when it is built: the
page calls `appear()` at every mount, which reads the folders, their status and the
history, as a page that owned its model did at each opening. The model calls the engine
through its `AutopilotWork` port, which the engine conforms to, and every answer is a
return. The reads and writes of the rule set and the history run off the cooperative
pool and never on the engine's own queue, because the status and the clearing of the
history take that queue synchronously inside; a dry run, a Run now and both returns run
on that queue, serialised with the hourly sweep and the FSEvents leg. Run now refuses a
folder that is switched off in the engine, not only at the button. The gates are below
these calls and are not reached around.

The one thing the engine says unasked, that a pass went into the history, is not a call of
the model's. The engine is built with a `historyChanged` closure, called only after the
history and its seal were written; the descriptor makes it yield into a one-slot
`AsyncStream`, and the model re-reads the history on it once a page has opened the module.
The descriptor's `stop(_:)` closes the model before the engine's `deactivate()`.
`AStoppedAutopilotModelReachesNoWorkTests.testBuildingTheModelAsksTheEngineNothing` holds
the first; `TheModelsDoorNeverWaitsOnTheEnginesQueueTests` holds the queue rule.
