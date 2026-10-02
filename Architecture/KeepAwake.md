# KeepAwake

`Sources/Modules/KeepAwake/` holds sleep off. Its logic units are pure and its
engine is the orchestration between them and the ports:
`ls Sources/Modules/KeepAwake/Engine/Logic/` is the list, and the doc comment of
`KeepAwakeEngine` names the units it drives and says that the module lifecycle
(`activate()`/`deactivate()`) and the session are separate axes.

## The closed lid

A permanent passwordless root grant is paid for only where the thing is otherwise
impossible, and nothing here raises a dialog on the way out: a rule too old to
withdraw itself is left where it is (`ClamshellCoordinator.tearDown`). The one
grant with no revocation is `/opt/homebrew`'s ownership change
(ARCHITECTURE.md § Giving everything back).

`ClamshellCoordinator` is the one thing in the app that outlives its own process:
`pmset disablesleep 1` is system-wide, reached through a NOPASSWD rule
(`SudoersRule`) that ends with an argument-exact entry permitting only its own
removal, so the grant carries its own revocation, which it has to because dragging
the application to the Trash runs no code. Who may *raise* the password prompt
is a separate question from what the prompt runs: `ClamshellCoordinator.consumeEdge()`
answers an `Edge`, and the engine reads it before its own active guard, so the
rising edge installs, the falling edge withdraws, and neither is inferred from a
value that stays true after a dialog was declined.

`KeepAwakeSettings.clamshellEnabled` is not sealed, for the reason its doc comment
gives; the mitigation that ships instead is that edge: a forged value can engage a
grant the person already gave, and cannot summon a password dialog.

## Vetoes and the notice

A veto that ends everything is on the wire under its own name, and the engine
refreshes the published sets (`activeConditions`, `triggeredConditions`) *before* the
veto returns, so a screen drawn under a veto is not drawn from whatever the sets held
when it began and does not offer to pause a rule that is not holding. One screen
carrying two accounts of one rule shows the quieter one, which is the one that sounds
like nothing is wrong. `triggeredConditions` is built once from the same three
expressions the stop path consults, so the screen and the behaviour cannot come
apart, and a row's state is decided in one pure place, `RuleNote.of`, where the veto
outranks the pause and `triggerHolds` is per-rule rather than the module's own flag.

When a guard has stopped everything, that is said on the wire. The guard takes the
one notice slot when both it and a pause are true, since only one of the two explains
why nothing at all is running; the slot is gated on "there is something to say"
(`KeepAwakePanelTile.hasNotice`) rather than on the pause flag; and the notice
carries no button, because a control that cannot do what it says is worse than none.

## State a person asked for outlives the process

A session the person asked for lives in the store rather than in engine fields,
because anything that ends the process would otherwise cancel it (the reason is on
`SessionRestore`). Three things shape how such a state is written:

- `KeepAwakeEngine.deactivate()` is the one place it is left unwritten, and the cost
  of that choice is on its doc comment.
- A restored deadline is a deadline rather than a duration (`restoreSession`).
- A `Date` is stored as `timeIntervalSinceReferenceDate`, for the reason on
  `rememberSession`.

`SessionRestore` is the pure unit deciding what a session found in the store is
worth; every branch is a judgement rather than arithmetic, and its doc comment says
what it cannot repair.
