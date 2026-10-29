# Leftovers

`Sources/Modules/Leftovers/` finds login items and plug-in files whose owner is
gone. Its boundary is what it will *offer*, and the rules err toward leaving things
alone: `Sources/Modules/Leftovers/Engine/Logic/StaleItemRules.swift` names what it
keeps.

Its removal path goes through `RemovableScope.partition` inside
`Sources/Modules/Leftovers/Engine/LeftoversEngine.swift` and then through
`HelmTrash.remove`; why the gate gets the engine's own `home` is on that `home`.

Turning a login item off is not deleting it, and the switch is aimed at a launchd
*label*, which is not a file: `Sources/Modules/Leftovers/Engine/Logic/LaunchctlDisabled.swift`
says why the per-user disabled-label list is the switch, and
`Sources/Modules/Leftovers/Engine/Logic/LaunchClaims.swift` says how many files
claim one label.

`LeftoversEngine` keeps its own record of the labels it disabled (`recordKey`, whose
doc comment says why not the system's list), so switching the module off gives back
exactly those; the edge that record cannot close is in ARCHITECTURE.md § Giving everything back.

Writability is asked of a directory rather than of each item in it
(`LeftoversFilePort.isWritableDirectory`).

## How Leftovers' model reaches its engine

`LeftoversViewModel` is built with the engine by the descriptor's `makeModule` and
held by the host. It calls `scan`, `trash` and `setDisabled` through its
`LeftoversWork` port, which the engine conforms to; each is answered by return, and
there is no stream because the engine emits nothing. The last word on a path and on a
label stays in the engine: `trash` partitions through `RemovableScope` before
`HelmTrash.remove`, and `setDisabled(_:)` asks `LaunchLabel.mayBeSwitched` and the
two agent folders before it reaches the switch, so a caller of the model cannot go
round them. On the person's switch the host calls the descriptor's `stop(_:)` after
`willDisable()` has given the switches back, so a press that late writes nothing nobody gives back.
