# Tests and measurement

## What makes a check

A check is judged by what its total failure would print. If that looks the same as
success it is not a check yet; the defect is put back and the check watched going red,
because a check never seen to fail is not a guard. A test that measures asserts
something: one that logs a figure for a person to read cannot fail, and a real regression
sits in it until somebody reads the number by hand. A test looking for a missing word
asserts first that the subject happened at all, since it passes when nothing was logged,
which is the default in a test process because the log is off outside a dev build.

## What proves what

The proof follows the class of the defect, and only some classes keep theirs in the tree.

| The defect | Its proof | Kept |
|---|---|---|
| data deleted, moved, overwritten or half-written; a secret or a name reaching a log, argv or a file; a privilege raised or a scope widened; work done while nobody watches | a test | yes |
| a crash on what a file, the system or another process hands Helm | a test | yes |
| an import across a boundary; a path or `§` pointer to nothing | the build's import check (ARCHITECTURE.md § The boundaries) and the checks of the tree | yes |
| the suite itself touching this Mac: its Keychain, defaults, Trash or a person's files | a test | yes |
| the look: layout, size, colour, contrast, a page's states | shots before and after (§ Snapshot rules) | no |
| motion | a recording before and after (§ Measuring motion) | no |
| logic that costs no data | the repro or a command printing the value, before and after | no |

A proof that is not kept is the same command run before the fix and after it, the before
already red, and its files stay outside the tree. A test outside the kept classes is
optional, and its class decides it: `Tests/optional-tests.txt` names such classes one per
line, `Scripts/test.sh` passes each to `--skip` on every run without a `--filter`, and
`HELM_FULL_SUITE=1` runs the full suite before a release. A name on the list that no test
class declares fails the run, because a stale name skips nothing and says so nowhere. A
defect found and not fixed goes to the defect log — the repository's issues, and a
security defect to the owner's private record, never to a public issue — and not into the
tree as a skipped test: a skip reads as a pass in a failures-only summary, and a
reproduction nobody runs goes stale.

## Removal takes its traces

When code leaves the tree, its tests and its lines on these pages and in `CLAUDE.md` leave
in the same commit; its lines in the crew's knowledge leave in the same change and reach
Core Crew's git when the owner commits them. A test of removed code no longer builds, and a
backticked Swift file name, a path with an extension `DocumentsNameTheTreeTests` knows
(slashed, or bare with a `:line`), a directory in the map or a `§` pointer left behind
fails the checks of the tree, and a class left on `Tests/optional-tests.txt` fails the run;
any other name, a bare type or a name in a doc comment, fails nothing, so the commit that
removes a name first runs
`command grep -rn '<name>' ARCHITECTURE.md Architecture CLAUDE.md README.md Sources Tests Scripts .claude/crew/knowledge`
and takes every line it prints — a mention, not a caller, the one question `grep` answers
here (ARCHITECTURE.md § Why the commands are run). Nothing is kept for later: git holds
what was removed. A module archived rather than dropped is tagged `archive/<module>` on its
last commit; a lesson in the crew's knowledge that outlives it stays, its address the old
path followed by «in the tag `archive/<module>`», read with `git show archive/<module>:<path>`.

## Readings and mutants

A volume-group walk is asserted on tree structure and never on sizes: which side of a
duplicate path wins is a race, so a size assertion passes by luck, and it did once. A
result found while more than one suite run was up is re-run alone at least three times
before it is believed, because the build lock serialises building and not running, and
two runs share the scratch directories, the Trash and Application Support. Any reading is
taken more than once: a count taken while the suite was still building is not the
count of the finished one. A render names its appearance, because this machine
switches by the sun and an unnamed reading is a reading of the hour; a suite has gone red
between two runs with nothing committed between them.

A mutated file is restored from a copy and never with `git checkout` on its path, which
restores to HEAD and discards every uncommitted edit in the file, and has destroyed work that
way. Committing before mutating is better
still, and the mutant is read back out of the file before its outcome is believed,
because a "0 failures" result has more than once been a substitution that never
applied.

## Fakes

A fake has every state the real port has and no state it does not, stands for one side of
a boundary only, and finishes the prompt it stands for. A simpler fake makes a failure
unrepresentable rather than untested; a freer one proves a branch unreachable in
production; an encoder and decoder that disagree are green against a fake that encodes its
own reply; a fake that never completes leaves the engine mid-prompt for ever behind an
in-flight guard. The fake port is named at every construction, because a defaulted port
is the machine's own keychain, and eleven forgetful constructions rolled a real rule set
back. A busy gate is tested with a runner that never exits, because a fake answering
synchronously releases the gate before the call it gates returns and the test passes with
the gate deleted; a cooperative yield is never a wait, because it buys a turn on the pool
and no wall-clock time, so no number of passes widens the window a writer can land in.

## Shared test plumbing

`Tests/Support/ScratchDirectory.swift` is the scratch directory, and its doc comment says
why its teardown drains. A restore that must outlive the sweep is registered as a
teardown block, and teardown blocks run first, so a directory left unreadable is
otherwise swept before it is made readable again.
`Tests/Support/EachLanguage.swift` runs an assertion about a visible string across the
eight languages; its doc comment says why, and states the rule a new test follows for the
language it asks in.

## Harnesses

A harness is pointed at a temporary folder, and what it saved under
`~/Library/Application Support/Helm/` is deleted and the app's own state checked before
the work is called done: real code writes, and the app has twice been handed back with
somebody's test tree in it and no way out. Whether a thing predates the session is asked
before anything under `/Applications` is removed, and what a harness launches is proved
able to replace what it kills before it kills anything. Accessibility is granted to the
process at the top of the launch chain rather than to the test runner, because the system
attributes the ask to the responsible process.

## Two screen instruments

`Scripts/shoot.sh` takes the still and `Sources/HelmReadout/` reads it. Neither judges:
the first prints where and how big, the second prints numbers, and a threshold lives in
the person or the check that reads them.

`shoot.sh <page>` launches Helm Dev on a page and captures the window, or with `--panel` the panel. Helm Dev is the
process whose executable path, as the kernel holds it (`HelmReadout exe <pid>`), is exactly
`/Applications/Helm Dev.app/Contents/MacOS/HelmApp`, never one found by name or by `ps`'s
command column, which is argv[0] and which any process sets: Helm and Helm Dev run one
executable name, and a SIGTERM must reach only Helm Dev. The pid is checked again before
every press, before a scroll or a panel press, and before it is ended. The page is opened by `-HelmOpenPage <id>`
(`Sources/HelmApp/LaunchPage.swift`), the one thing a press cannot reach, since Helm Dev has
no window at launch; any other state is brought by pressing a control by its accessibility
name (`--press`), by a launch argument (`--arg`), by the scroll bar (`--scroll`) or by the panel (`--panel`), through the Accessibility C API, so no System Events and no AppleScript
runs. A page that cannot be opened is refused and logged, never replaced by another.

The region is the window's bounds read before and after the capture, both printed:
an autosaved window origin can land on another display under `.accessory`, so no place
is assumed. `screencapture -R` takes the region, not `-l` by window number, which
mis-renders a window whose material is active. Another application often takes the front,
so each press and the capture print whether anything sits above the window, and shoot
says "front: no" in words rather than fighting for the front. An `mkdir` lock
(`helm-shoot.lock` in the user's temp directory, its owner's pid in a file inside) stops two
shoots on one screen: the second refuses at once with exit 73 naming the owner pid, and
never waits. A locked screen is refused with 75. `defaults export` of Helm Dev's domain
is taken before and after, the run reports whether it changed, and Helm Dev is ended by
SIGTERM sent to the checked pid only; only after that pid is seen to have ended (a Helm Dev
still running would overwrite it) is a changed domain deleted and the copy imported, since
`defaults import` alone merges and a key added during the run would survive; a third export
is compared with the copy and the run prints "defaults restored: identical" or "DIFFERENT". The shot's pixel
size is compared with the window's bounds times the display's scale (`HelmReadout scale`)
and a disagreement is printed, because `-R` is given a rect and nothing here proves that
every display arrangement honours it.

`HelmReadout` is an executable target declared in no product (SwiftPM synthesises one for
it, and `HelmApp` does not depend on it, so `--product HelmApp` never builds it) and with no
dependency on any other target; `swift build --target HelmReadout` builds it, `shoot.sh`
never does. A capture carries the display's profile, so `point` prints the file's own
values with the profile name beside the sRGB ones; the other subcommands read sRGB.
Its subcommands: `point`, `bands`, `contrast`, `diff` over two captures of one size,
`window <pid>` with the windows in front of each, `exe <pid>`, `scale <x> <y>`, `ax <pid>`,
`press <pid> <name> [<role>] [--nth <n>]`, `scroll <pid> <fraction>`, `statusitem <pid> <host-pid>`, and `session`, which says whether the screen is
locked and which grants this chain has.

Two controls may share a name when the page offers one action twice (a toolbar button and an empty state's):
`press` refuses them and lists them numbered in the tree order `ax` prints; `--nth <n>` (1-based), after
`--press "<name>"` in `shoot.sh` and last in `HelmReadout press`, picks one.

A state that is not on screen at launch is reached by `--press` (above), `--arg`, `--scroll` or
`--panel`; `--name` only names the file. `--arg <key> <value>` is
a launch argument after `-HelmOpenPage`, answered from the argument domain, so it overrides
a default for the run and writes none (`--arg module.app.appearance dark`). `--scroll <fraction>`
(0 to 1) writes the page's vertical scroll bar value (`HelmReadout scroll`), because a window
taller than the screen loses its lower part in a shot and a SwiftUI row offers no
scroll-to-visible; a page-down action answers -25204 on a SwiftUI scroll area. The value is
absolute, so a rerun gives the same frame, and the tool prints how far the first row moved.
`--panel` presses the status item and shoots the panel window (layer 101) instead of the page:
on macOS 27 status items live in `MenuBarAgent`'s tree, so `HelmReadout statusitem` finds the
button by Helm Dev's own pid (the label "Helm" is the button's description; its title is the countdown text while one is shown, so the match reads both), which leaves the release Helm's button alone; the panel
frame shows other modules' live tiles, so it is proof and not a file for the tree. `--name <stem>`
makes the file `<page>-<stem>.png`, so one page can be shot in many states into one folder.

## Snapshot rules

A still proves the look only if it was taken so that a one-point defect shows.

- The region at its natural size, never scaled: a scaled picture hides a 1 pt line.
- Beside it, the system's own analogue at the same size, taken by the same
  `screencapture -R` of the window `HelmReadout window <pid>` names: a number about
  Helm's ground means something only against the ground the system draws on the same
  screen (measured once: Helm's flat dark sidebar read 40 where System Settings' read 38).
- Light and dark by pressing Helm's own switch, never the system's: the system's
  switch is a setting of somebody's Mac, which no crew member changes.
- Active and inactive (`--inactive`): a window's material and its controls draw
  differently when it is not key (measured: a light ground read 211 active and 240 inactive).
- Before and after the change, the same page and state: a difference between two shots
  of different states is not the change's.
- Motion by frames (§ Measuring motion), with `HelmReadout diff` over a crop: a still
  shows a settled state only.
- Colour read in sRGB: a capture carries the display's profile, so its file values are
  not the token's.

## Measuring motion

Motion is recorded with a screen recording and the recorder is never wrapped in a timeout:
the file is written when the recording stops and the signal kills it first, which reads
exactly like a permissions refusal. Stills arrive slowly and are for
settled states, and a still is taken by `Scripts/shoot.sh` (§ Two screen instruments) of
the window's region rather than by display index, because that index is not the screen
order and a full-screen capture photographs whatever else is open on somebody's machine. A pixel probe timestamps its sampling loop, because reading
pixels costs enough per frame that a run of samples nominally "20 ms" apart
covers far more time than that; it
anchors on something that moves with what is measured, since a fixed rectangle over a
growing page measures the page; it crops to the part that moves, because a whole-window
difference is dominated by whatever else changed; it measures at the shipping duration,
because at a longer duration an instant snap reads as "it drew quickly at the start"; and it
ships the control with every ramp it measures, because without it the ramp passes on a machine
that animates everything by default. Motion is never measured from a hosting view's
fitting size, which answers with the ideal size and reads every ramp as a step.

## Why the commands are run

The commands a session runs each have a reason that is not obvious from the command. A
filtered run is far shorter than the suite, which is what makes running a guard before the
suite cheap enough to actually do. `plutil -lint` refuses a catalog, so
`python3 -m json.tool` is what follows a hand edit, and the four string guards, which the run before a commit skips, are run by name before committing. The visual
harness is env-gated and belongs in the working tree only while it is being used, so
`command grep -rn HELM_DEBUG Sources/` is empty before a commit.

"Who uses this" is answered from an index and never from `grep`: the tree writes backticked
names inside doc comments deliberately and at volume, so a grep counts prose as a caller.
The `periphery` report is not a to-do list either: its "unused" covers dead code, a marker a
test checks by type rather than by call, and a fake's capability no test has needed yet,
while its assign-only findings are usually a property held to keep an object alive, a
token whose clearing is the cancellation, or a field a synthesized conformance reads.

A cleanup is measured before it is believed: `du -sh "$TMPDIR"` first, then what under it
is not `helm-*`, because the same folder holds other programs' files. `--scratch-path` is
passed only when another suite run may be up, and one path is reused for the session,
since a fresh directory per invocation is a full build directory.

The helper directories change faster than prose about them: `ls
Sources/HelmRuntime`, `ls Sources/HelmUI/DesignSystem` and `ls Tests/Support` are read
before a helper is written, because prose listing them falls behind the directories, and
a helper written beside one that already exists is the duplicate this reading is for.
