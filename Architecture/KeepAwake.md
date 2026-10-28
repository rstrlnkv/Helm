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
removal, `/bin/rm -f` on the one literal path (`SudoersRule.removeArguments`), so the grant carries its own revocation, which it has to because dragging
the application to the Trash runs no code. Who may *raise* the password prompt
is a separate question from what the prompt runs: `ClamshellCoordinator.consumeEdge()`
answers an `Edge`, and the engine reads it before its own active guard, so an edge
that happens while the module is idle is consumed rather than saved up, the
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

## Its states

`-HelmKeepAwakeSample <name>` puts one of the states in the table below on screen without the Mac being in
it (`KeepAwakeSamples.swift`). The descriptor builds `KeepAwakeSampleEngine` instead of the
engine: no port exists, so no assertion, `pmset` or sudoers step is reachable, and the page and
tile read an in-memory store seeded with the sample's settings, so nothing is written to the
defaults. The name is read from the argument domain only, and an unknown or missing one builds
no real engine either and logs a refusal. The engine says `standsIn` (`ModuleEngine`), so while
it is live the host refuses to switch Keep Awake off and refuses Reset everything, one warn line
beginning "refused: samples shown" for each: either would write the real `enabled` flag and skip the engine's
hand-back. A built sample logs `samples built: <name>` when the engine is made, which is before
`LaunchPage` may refuse the page; `launch page: keep-awake` is what proves the page opened. Keep
Awake must be switched on in Helm Dev, or the launch page is refused. The names are matched,
never drawn; app names come from the system, the sample rules being Apple's own bundle ids,
except that one row of `worst` is the sample's own non-existent bundle id, drawn as it is on
purpose.

The page id is the module id, `keep-awake`, not `keepawake`. A state is shot with its file
`keep-awake-<state>-<light|dark>[-<ru|de>][-s025|-s050|-s100|-panel].png`, position 0 without a suffix:

    bash Scripts/shoot.sh keep-awake --arg HelmKeepAwakeSample <name> \
      --arg module.app.barAppearance flat --arg module.app.appearance <light|dark> \
      --name <name>-<light|dark> [--scroll <0...1>] [--panel] --out <dir>

`--scroll <fraction>` sets the page's vertical scroll bar to that fraction of its range, for
the part below the fold; `--panel` shoots the panel tile (the status item pressed in
`MenuBarAgent`'s tree, found by Helm Dev's pid). A panel frame also shows the other modules'
live tiles (VPN profile names, disk): it is proof for the owner's eyes, never kept in the tree.

| state | the Mac is shown as | seen in |
|---|---|---|
| `idle-no-rules` | off, no rule | hero off, tile |
| `idle-waiting` | off, power and display rules on, none fired | hero, rule notes |
| `timed-long` | a session one second short of the longest | hero, tile, menu-bar ring |
| `timed-then-held` | 47 minutes left, a power rule holding after it | hero's "held by" tail |
| `indefinite` | on, no end | hero, tile |
| `automatic-apps` | held by three app rules, two apps running | hero names, Stop caption, rules list |
| `stop-two-step` | 30 minutes, a rule holds, timer ends automation | hero's Stop word |
| `suppressed` | rule applies and is paused | Paused/Resume, rule note, tile |
| `battery-veto` | stopped by the battery guard | the notice, rule note, battery row |
| `lid-refused` | closed-lid option on, macOS refused | lid row note |
| `left-behind` | lid option off, its sudoers rule still there; an unreadable rules value | lid note, rules banner |
| `worst` | three conditions, eight app rules (one not installed), lid held, longest numbers | everything |

`worst` is the one with the worst data: the largest numbers the clamps allow (jiggle interval,
default duration) and the most app rules. Its longest strings come from the language, not the
sample: add `--arg module.app.interfaceLanguage ru`, and once with `de` for the German wrap.

Shoot each state at position 0 (no suffix), `--scroll 0.5` and `1` (suffixes `-s050`, `-s100`);
add a position where the 0.5 frame cuts the part to be shown: `0.25` (`-s025`) for `lid-refused`
and `left-behind`, whose lid row the header cuts at 0.5. The panel tile (`--panel`)
for `idle-no-rules`, `timed-long`, `indefinite`, `automatic-apps`, `suppressed`, `battery-veto`
and `worst`.

Samples cannot cover what is read from the machine itself: a Mac without a battery, a lid or a
built-in display (`MacHardware`), and the pointer row's reading of the real Accessibility grant.
Those rows are shown or hidden by the Mac the shot is taken on.
