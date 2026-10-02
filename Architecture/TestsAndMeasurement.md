# Tests and measurement

## What makes a check

A check is judged by what its total failure would print. If that looks the same as
success it is not a check yet; the defect is put back and the check watched going red,
because a check never seen to fail is not a guard. A test that measures asserts
something: one that logs a figure for a person to read cannot fail, and a real regression
sits in it until somebody reads the number by hand. A test looking for a missing word
asserts first that the subject happened at all, since it passes when nothing was logged,
which is the default in a test process because the log is off outside a dev build.
Every known gap in the tree is skipped the one way: the test is skipped unless
`HELM_KNOWN_GAPS=1` is set, with a reason that starts «Known gap <id>», at the top of
the test, the reproduction left intact below, so `HELM_KNOWN_GAPS=1` runs all of them
and each reads red while its gap is open.

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

## Measuring motion

Motion is recorded with a screen recording and the recorder is never wrapped in a timeout:
the file is written when the recording stops and the signal kills it first, which reads
exactly like a permissions refusal. Stills arrive slowly and are for
settled states, and a shot is taken by window number rather than display index, because
that index is not the screen order and a full-screen capture photographs whatever else is
open on somebody's machine. A pixel probe timestamps its sampling loop, because reading
pixels costs enough per frame that a run of samples nominally "20 ms" apart
covers far more time than that; it
anchors on something that moves with what is measured, since a fixed rectangle over a
growing page measures the page; it crops to the part that moves, because a whole-window
difference is dominated by whatever else changed; it measures at the shipping duration,
because at a longer duration an instant snap reads as "it drew quickly at the start"; and it
ships the control with every ramp test, because without it the ramp passes on a machine
that animates everything by default. Motion is never measured from a hosting view's
fitting size, which answers with the ideal size and reads every ramp as a step.

## Why the commands are run

The commands a session runs each have a reason that is not obvious from the command. A
filtered run is far shorter than the suite, which is what makes running a guard before the
suite cheap enough to actually do. A malformed
`Localizable.strings` is silent and every string in it falls back to English with no error
anywhere, which is why `plutil -lint` follows any hand edit, and the three string guards
are cheap to run first. The visual harness is env-gated and belongs in the working tree only while it is
being used, so `command grep -rn HELM_DEBUG Sources/` is empty before a commit.

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
