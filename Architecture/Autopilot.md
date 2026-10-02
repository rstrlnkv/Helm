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
