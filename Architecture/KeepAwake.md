# KeepAwake

`Sources/Modules/KeepAwake/` holds sleep off. Its logic units are pure and its
engine is the orchestration between them and the ports:
`ls Sources/Modules/KeepAwake/Engine/Logic/` is the list, and the doc comment of
`KeepAwakeEngine` names the units it drives and says that the module lifecycle
(`activate()`/`deactivate()`) and the session are separate axes.

## How the model reaches the engine

`KeepAwakeViewModel` is built with the engine by the descriptor's `makeModule` and
held by the host, and it calls the engine's own methods (`toggleSession`,
`startSession`, `stopSession`, `resumeAutomation`, `settingsChanged`) on the main
actor, where the engine's fields are written from; the observers and `Clock.schedule`
deliver on main, and the lid coordinator hops to main before it announces
(`ClamshellCoordinator.onMain`). A name that does not exist is a
build error, not a refused string.

States come the other way through `KeepAwakeEngine.stream()`, one task in the model
that the descriptor's `stop(_:)` cancels before the engine's `deactivate()`. The
stream replays the latest state and registers the subscriber in the one hold of
`EngineNews`'s lock (`EngineNews.stream`); reading the state and then subscribing
leaves a window in which an emit is lost, and registering before replaying delivers an
older state after a newer one. It is synchronous and not actor-isolated so that the
model takes it in its own synchronous `init`, before the first suspension: no emit
falls between the model's construction and its subscription. `TheStreamReplaysTheStateInOrderTests` races an emit against the
subscription and asserts the order is kept, and
`ASwitchedOffModuleLetsItsSubscriberGoTests` that stopping the model returns the
subscriber.

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
is a separate question from what the prompt runs: only the person's gesture on the lid switch
(`KeepAwakeEngine.lidSwitchTurned`, its rising edge, with or without a running session) may raise it. A Start press
(`startSession`), a rule starting a session and a store value written from outside never do: `recompute` calls
`engage(mayPrompt: false)`, which engages silently when a passwordless grant exists and otherwise holds the Mac
without the lid rule. On a Mac with no lid (`LidInfoPort`) nothing reaches `lid.engage`, and both the per-app and the global
«external display» condition are false. `ClamshellCoordinator.consumeEdge()` answers an `Edge`, which the engine reads before its own active guard, so an edge
that happens while the module is idle is consumed rather than saved up, the
rising edge installs, the falling edge withdraws, and neither is inferred from a
value that stays true after a dialog was declined.

`KeepAwakeSettings.clamshellEnabled` is not sealed, for the reason its doc comment
gives; the mitigation that ships instead is the gesture: a forged value can engage a
grant the person already gave, and cannot raise a password dialog by itself, but with
no grant only the lid switch's own gesture does (`lidSwitchTurned`, its rising edge as `consumeEdge` reads it at a settings edit, in a session or not, on a Mac with a lid). A start press does not, with the stored option on or off.

`PmsetClamshellPort` is the only code that runs the grant's privileged commands, and no test runs it: every engine test builds the engine with
a fake `ClamshellPort` (`FakeClamshell` or a test's own), and `HelmProcess.run` is called directly, so there is no point at which a test can record argv. Three things in it are held by
reading only: every call against the grant goes through `withoutPassword` (`sudo -n`, or a dialog-less caller blocks on a prompt no window owns);
the argv words come from `SudoersRule` (`disableSleepArguments`, `removeArguments`), never typed here; and `removeSudoers` runs `removeScript()`
where `installSudoers` runs `installScript(user:)`, a swap that compiles, passes the suite and turns "Remove the rule" into "install it again".
A change to this class is read against `SudoersRule` line by line and run once by hand on Helm Dev (switch the closed-lid option on, then off, and look
for the file at `SudoersRule.installedPath` gone). That hand check covers the passwordless
removal (`removeSudoersWithoutPassword`, `sudo -n rm`), which `ClamshellCoordinator.removeGrant`
tries first; `removeSudoers` and its `removeScript()` run only when that fails, e.g. for an
old-form rule without the `rm` line, so the swap above is reached by hand only with such a rule in place. A test wants a process runner injected into the class (a closure `(String, [String]) -> (status, output)`
defaulting to `HelmProcess.run`), which no one has asked for yet.

## Vetoes and the notice

A veto that ends everything is in its state under its own name, and the engine
refreshes the published sets (`activeConditions`, `triggeredConditions`) *before* the
veto returns, so a screen drawn under a veto is not drawn from whatever the sets held
when it began and does not offer to pause a rule that is not holding. One screen
carrying two accounts of one rule shows the quieter one, which is the one that sounds
like nothing is wrong. `triggeredConditions` is built once from the same three
expressions the stop path consults, so the screen and the behaviour cannot come
apart, and a row's state is decided in one pure place, `RuleNote.of`, where the veto
outranks the pause and `triggerHolds` is per-rule rather than the module's own flag.

When a guard has stopped everything, that is said in the state. The guard takes the
one notice slot when both it and a pause are true, since only one of the two explains
why nothing at all is running; the slot is gated on "there is something to say"
(`KeepAwakePanelTile.hasNotice`) rather than on the pause flag; and the notice
carries no button, because a control that cannot do what it says is worse than none.

The battery floor is inclusive: `BatteryGuard.shouldDeactivate` is `percent <= threshold`, so the session ends *at* the figure. Every sentence that names
it says "or less" (the slider's note, the hero's and the panel's notice, the system notification), in all eight languages; ja and zh also have a strict
word (未満, 低于) that would say the opposite, and do not use it here. Compose them from the one phrase (`KAStr.atPercentOrLess`), never write the boundary
out again in a new string; a translator who writes "below" is wrong about what the Mac does.

`KeepAwakeEngine` takes the battery veto's notification channel as an optional, and `nil` means silent. The only place the real port and its words are
handed over is `KeepAwakeDescriptor.keepAwakeEngine`; a rebuild of that call that drops `batteryVeto:` switches the notification off and no engine test
notices, because they all build the engine with a fake. The sentence comes from the UI target (`KAStr.batteryVetoNotice`), the engine cannot spell it.

The reason line in the log ("holding sleep: manual+timer") is composed by `ConditionLabel`, which orders the reasons. `activeConditions` is a `Set`;
a line built by iterating it prints the same session in a different order on each launch, and `grep -c` over two logs counts nothing.

What the Stop button says and what the next press does both come from `StopPress.next`, called by the engine (`KeepAwakeEngine.swift`, the press) and by
the hero (`KeepAwakeHero.stopPress`, the word). There is no armed flag: its three inputs are read again on every rebuild, so the word is true only while
the state it names is true. A second spelling of the decision in a view is a button that promises one act and does another.

## Rules read from the machine

"External display" (the rule's row) is meaningless on a Mac with no lid (every display of a mini, a Studio or an iMac is external, the rule would mean never sleep),
and the stored flag survives on a machine whose plist was written as a laptop. Every place that counts or draws the rule asks whether the Mac has a lid (`lidInfo.hasLid()` in the engine, `MacHardware.hasLid` in the views)
first: the engine (`externalDisplayCondition`, `holdingAppRules`), the settings row, the panel tile and the mark column (`MarkableRules.onThisMac`); `AutomationMirror` only
copies the stored flag into the views' state. A new reader of the flag that does not ask counts a rule that has no row, and the card indents its rows for a
mark nobody can put there.

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

The states below are the module's checklist. Each is reached on a real Mac by what a person does or by real
use; only `worst` and the unreadable half of `left-behind` need a stored value put there by an argument (`--arg module.keep-awake.<key> <value>`, a number written `'<integer>N</integer>'`: a bare number reaches the store as a string and the default is shown). A page is shot as it stands, with `Scripts/shoot.sh`, after
Keep Awake is switched on in Helm Dev (the launch page is refused otherwise).

The page id is the module id, `keep-awake`, not `keepawake`. A state is shot with its file
`keep-awake-<state>-<light|dark>[-<ru|de>][-s025|-s050|-s100|-panel].png`, position 0 without a suffix:

    bash Scripts/shoot.sh keep-awake \
      [--press "<control name>"]... \
      --arg module.app.barAppearance flat --arg module.app.appearance <light|dark> \
      --name <state>-<light|dark> [--scroll <0...1>] [--panel] --out <dir>

`--press` brings the state about by the page's own controls, as a person would; `--scroll <fraction>` sets the page's vertical scroll bar to that fraction of its range, for
the part below the fold; `--panel` shoots the panel tile (the status item pressed in
`MenuBarAgent`'s tree, found by Helm Dev's pid). A panel frame also shows the other modules'
live tiles (VPN profile names, disk): it is proof for the owner's eyes, never kept in the tree.

| state | the Mac is in | reached by |
|---|---|---|
| `idle-no-rules` | off, no rule | switched off with every rule off: a person, or `--press` |
| `idle-waiting` | off, power and display rules on, none fired | a person turns the rules on while on battery with no external display (on mains the power rule fires at once); `--press` for the switches, the power source is real use |
| `timed-long` | a session one second short of the longest | a person starts the longest timed session; `--press` |
| `timed-then-held` | 47 minutes left, a power rule holding after it | a timed session with a power rule that holds; the rule's condition is real use |
| `indefinite` | on, no end | a person starts a session with no end; `--press` |
| `automatic-apps` | held by three app rules, two apps running | app rules for apps that are running; the apps are real use |
| `stop-two-step` | 30 minutes, a rule holds, timer ends automation | a timed session while a rule holds; the rule's condition is real use |
| `suppressed` | rule applies and is paused | a person pauses a rule that holds; `--press` |
| `battery-veto` | stopped by the battery guard | the battery falling to the guard's figure or less, or a person on battery raising the floor slider (5...50) to the charge or above |
| `lid-refused` | closed-lid option on, macOS refused | real use only: a sudoers rule that answers `disablesleep 0` but not `disablesleep 1` (not what Helm wrote), or the administrator dialog accepted and the call still failing |
| `left-behind` | lid option off, its sudoers rule still there; an unreadable rules value | the rule: real use, left by an earlier run that could not withdraw it; the unreadable rules value: a stored value that does not parse (`--arg module.keep-awake.autoAppRules garbage`, or a damaged settings file) |
| `worst` | three conditions, eight app rules (one not installed), lid held, longest numbers | a person sets the largest numbers the page offers and the most app rules; the clamp maximum (1440 minutes) is reached only by a stored value, e.g. `--arg module.keep-awake.jiggleIntervalMinutes '<integer>1440</integer>'`; the app not installed is real use: an app removed after its rule was added |

`worst` has no launch sample: the one that drew it was removed (f1951bed), so every part of it is set by a person or by `--arg`, which reaches settings only. Do not put `module.keep-awake.clamshellEnabled` in an unattended shot: while a rule holds the Mac awake, a grant already installed runs `pmset disablesleep 1` for real (`KeepAwakeEngine.recompute`, the `lidInfo.hasLid(), settings.clamshellEnabled` branch (`lidInfo` is a `LidInfoPort`, `MacHardware.hasLid` in production), `lid.engage(mayPrompt: false)`); a `--press` on a start control never raises the administrator dialog.

Longest strings come from the language: add `--arg module.app.interfaceLanguage ru`, and once with `de` for the German wrap.

Shoot each state at position 0 (no suffix), `--scroll 0.5` and `1` (suffixes `-s050`, `-s100`);
when none of the three shows the part a state is for whole, add `--scroll 0.25` (`-s025`). The panel tile (`--panel`)
for `idle-no-rules`, `timed-long`, `indefinite`, `automatic-apps`, `suppressed`, `battery-veto`
and `worst`.

Rows read from the machine itself are shown or hidden by the Mac the shot is taken on: a Mac without a battery or a lid (`MacHardware`), and the pointer row's reading of the real Accessibility grant.
