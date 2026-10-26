#!/bin/bash
set -euo pipefail

# Wraps `swift test`, logging the whole output and reading it the way this
# header says a run must be read: the exit status on its own line, never
# through a pipe, and the whole log rather than its tail. It also closes a
# gap that reading alone does not: `swift test
# --filter 'A|B|C'` where every alternative matches nothing prints `warning:
# No matching test cases were run` and this script fails on that too — but
# where only SOME alternatives match, it exits 0 with no warning at all
# (measured: `--filter 'TheMapNamesRealDirectoriesTests|NoSuchTestsAtAll'`
# -> EXIT=0, zero warnings, "Executed 1 test"). A mistyped guard name in a
# family run is then silently not run. This script fails non-zero and names
# the alternative, on Gradle's `failOnNoMatchingTests` model. `swift test`
# itself ORs a repeated `--filter`, so every occurrence is read here too, in
# both the `--filter X` and `--filter=X` forms, and joined the same way.
#
# Reading a run: this script prints its own verdict last. The closing "Test
# Suite 'All tests' passed" speaks for the last bundle and the very last
# line, "✔ Test run with 0 tests in 0 suites passed", for Swift Testing's
# empty run — neither speaks for the suite. A summary line that also carries
# a skip count reads as zero failures under a shorter pattern, and a
# `--filter` whose alternatives match nothing, or match only in part, still
# exits 0; the runner counts each alternative against the cases that
# actually ran and fails, naming the one that ran none. Where a bare `swift
# test` log has to be read, take the status on its own line —
#   swift test > log 2>&1; echo "EXIT=$?"
# — and count
#   command grep -cE 'with ([0-9]+ tests? skipped and )?[1-9][0-9]* failures?' log
#   command grep -c 'warning: No matching test cases were run' log
# A filter that matches in part is invisible to both counts.
#
# The build checks imports: --explicit-target-dependency-import-check error
# refuses an import of a target outside the importing target's dependencies,
# direct or through another (ARCHITECTURE.md § The boundaries). It checks
# only a target that recompiles, so a rerun after a refusal is green, and the
# refusing run's last build line can still be "Build complete!" (measured on
# Swift 6.4, 26.10.2026): $STATUS is the verdict, not that line.
#
# Usage: Scripts/test.sh [swift test arguments...]
# Without a --filter every class `Tests/optional-tests.txt` names is skipped;
# HELM_FULL_SUITE=1 runs them too, as a release does (ARCHITECTURE.md § What
# proves what).
# A listed name no `class <Name>:` under Tests/ declares refuses the run before
# swift test, naming it.
# The log path is $HELM_TEST_LOG if set, otherwise a fresh file under
# ${TMPDIR:-/tmp}; the summary line always prints where it went.
#
# LIMIT: an alternative is found by splitting --filter's value on every `|`
# in it — a plain splitter, not a regex parser. An alternative that carries
# its own `|` inside a group (say `Foo(A|B)Tests`) is split into two pieces,
# wrongly, neither balanced on its own, but `grep -E` only catches the piece
# whose stray `(` makes it invalid (measured: `NoSuch(A|B)Tests` ->
# "parentheses not balanced" on `NoSuch(A`, status 2, reported here as
# unreadable). Its other half's stray `)` is not an error to `grep -E` — BSD
# grep reads an unmatched `)` as a literal character, so `B)Tests` compiles,
# matches none of the selected cases (none is named that), and is reported
# the ordinary way, as an alternative that ran no test case, not as
# unreadable. Either half failing this way is still caught, one way or the
# other, rather than letting swift test's own — correct — reading of the
# whole group pass unrecorded.
#
# LIMIT: checking an alternative here means asking `grep -E`, BSD's POSIX
# ERE, whether it matches one of the selected cases; `swift test --filter`
# reads the same alternative in its own engine, measured as ICU on its
# XCTest side (by the output — `(?i)`, `\w`, `\S`, `*?` and `\Q…\E` agree
# between the two). A lookahead is a construct BSD grep has no notion of at
# all: ICU reads `Foo(?=Bar)` and BSD grep cannot parse it (measured:
# `TheMapNames(?=Real)` runs its case under `swift test` — the log carries
# its `Test Case … started` line — while `grep -E` exits 2 on it,
# "unreadable"). That failure is this checker's own reading going dark, not
# swift test's, so it is never folded into "ran no test case" — read as a
# mismatch, that would be a false claim about an alternative that ran fine
# — and is reported on its own line instead, failing closed rather than
# passing an alternative nothing here actually checked. Swift Testing
# bundles read `--filter` differently again: `--filter
# '(?<=\.)TheMapNamesRealDirectoriesTests'` still ran the XCTest case but
# `swift test` itself exited 1, the log's `Note: Some test targets reported
# failures:` naming every Swift Testing bundle — that exit is read here
# through `$STATUS` regardless of its cause, which this script has not
# measured further than that.
#
# LIMIT: a quieter case sits beside that one — `\z`, `\Z`, `\A`, `\p{Lu}` and
# `[\w]` all parse under `grep -E` without error (exit 0 or 1) and are read
# as something else entirely, an escape it does not recognise standing for
# its literal letter and a character class collapsing to the characters
# written inside it (measured: `MapNamesExists\z` and
# `TheMap[\w]amesRealDirectoriesTests` each ran their case under `swift
# test` and counted 0 selected cases here). This checker cannot tell that
# count apart from a genuine typo or an unrelated `--skip`, so all three
# land in the same "ran no test case" message below rather than one of them
# being guessed at.

# --filter can arrive as `--filter X` or `--filter=X`, and more than once;
# swift test ORs every occurrence, so every one is read here too and joined
# the same way rather than only the first.
FILTER_VALUES=()
ARGS=("$@")
for ((i = 0; i < ${#ARGS[@]}; i++)); do
  case "${ARGS[$i]}" in
    --filter=*)
      FILTER_VALUES+=("${ARGS[$i]#--filter=}")
      ;;
    --filter)
      FILTER_VALUES+=("${ARGS[$((i + 1))]:-}")
      ;;
  esac
done

# A test name holds no newline byte. `grep -E` below reads a pattern that
# carries one as two patterns split on that byte, and the empty side of
# such a split matches every line it is asked about, so a misspelled
# alternative followed by a newline then counts as a match instead of a
# miss (measured: `TheMapNamesRealDirectoriesTests|` followed by a newline
# and `NoSuchTestsAtAll` counted every selected case and printed PASS).
# Refuse any --filter value carrying one — in either the `--filter X` or
# `--filter=X` form, and on any occurrence — before swift test runs at all,
# so a bad value never gets as far as spending the run.
if [ "${#FILTER_VALUES[@]}" -gt 0 ]; then
  for ALT in "${FILTER_VALUES[@]}"; do
    case "$ALT" in
      *$'\n'*)
        echo "!! --filter value contains a newline byte, refused before swift test runs: $(printf '%q' "$ALT")" >&2
        echo "==> FAIL (runner exit=1, swift test exit=not run)  failure-lines=0  selected=0  log=not written"
        exit 1
        ;;
    esac
  done
fi

FILTER_VALUE=""
if [ "${#FILTER_VALUES[@]}" -gt 0 ]; then
  FILTER_VALUE="$(printf '%s|' "${FILTER_VALUES[@]}")"
  FILTER_VALUE="${FILTER_VALUE%|}"
fi

# The optional classes. Every run without a --filter skips each class
# `Tests/optional-tests.txt` names, one class per line; HELM_FULL_SUITE=1 runs
# them too, and a --filter runs whatever it names, optional or not. The list
# is read before swift test spends the run and refused whole when it is empty,
# on a line that is not one bare class name, a name written twice, a name no
# `class <Name>:` under Tests/ declares, or a name two classes declare: a stale
# name skips nothing and says so nowhere. Any superclass counts, so a test
# class built on a shared rig is declared like any other. Each name reaches
# swift test as `--skip '[.]<Name>/'`, matched like --filter against
# `<Target>.<Class>/<method>` (below), so it skips that class and no other —
# a bare name matches as a substring, and `AutomationNoticeTests` would skip
# `SystemAutomationNoticeTests` with it. /bin/bash is 3.2 here: no
# associative array, no mapfile, and an empty array expanded under `set -u`
# is an error, hence sort, comm and the count guard.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPTIONAL_LIST="$ROOT/Tests/optional-tests.txt"
refuse_list() {
  echo "!! $OPTIONAL_LIST: $1 — refused before swift test runs" >&2
  echo "==> FAIL (runner exit=1, swift test exit=not run)  failure-lines=0  selected=0  log=not written"
  exit 1
}
{ [ -f "$OPTIONAL_LIST" ] && [ -r "$OPTIONAL_LIST" ]; } || refuse_list "not a readable file"
set +e
NOT_A_NAME="$(command grep -nvE '^[A-Za-z_][A-Za-z0-9_]*$' "$OPTIONAL_LIST")"
NOT_A_NAME_STATUS=$?
DECLARING="$(command grep -rhoE --include='*.swift' '^[[:space:]]*((@[A-Za-z]+|final|public|open|internal)[[:space:]]+)*class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:' "$ROOT/Tests")"
DECLARING_STATUS=$?
set -e
case "$NOT_A_NAME_STATUS" in 0|1) ;; *) refuse_list "unreadable (grep exited $NOT_A_NAME_STATUS)" ;; esac
[ "$DECLARING_STATUS" -eq 0 ] || refuse_list "the test classes under $ROOT/Tests could not be read (grep exited $DECLARING_STATUS)"
[ -z "$NOT_A_NAME" ] || refuse_list "a line that is not one bare class name: $(echo $NOT_A_NAME)"
OPTIONAL_NAMES="$(LC_ALL=C sort "$OPTIONAL_LIST")"
[ -n "$OPTIONAL_NAMES" ] || refuse_list "names no class"
DECLARED="$(printf '%s\n' "$DECLARING" | sed -E 's/.*class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/' | LC_ALL=C sort)"
TWICE="$(printf '%s\n' "$OPTIONAL_NAMES" | uniq -d)"
UNDECLARED="$(LC_ALL=C comm -23 <(printf '%s\n' "$OPTIONAL_NAMES" | uniq) <(printf '%s\n' "$DECLARED" | uniq))"
AMBIGUOUS="$(LC_ALL=C comm -12 <(printf '%s\n' "$OPTIONAL_NAMES" | uniq) <(printf '%s\n' "$DECLARED" | uniq -d))"
[ -z "$TWICE" ] || refuse_list "named twice: $(echo $TWICE)"
[ -z "$UNDECLARED" ] || refuse_list "no class <Name>: under Tests/ declares: $(echo $UNDECLARED)"
[ -z "$AMBIGUOUS" ] || refuse_list "more than one class is declared as: $(echo $AMBIGUOUS)"
SKIP_ARGS=()
if [ "${#FILTER_VALUES[@]}" -eq 0 ] && [ "${HELM_FULL_SUITE:-}" != "1" ]; then
  while IFS= read -r NAME; do
    SKIP_ARGS+=(--skip "[.]${NAME}/")
  done <<< "$OPTIONAL_NAMES"
fi
SKIPPED_CLASSES=$(( ${#SKIP_ARGS[@]} / 2 ))

if [ -n "${HELM_TEST_LOG:-}" ]; then
  LOG="$HELM_TEST_LOG"
else
  # macOS's `mktemp` substitutes only a trailing run of `X`s in the
  # template: asked for `helm-test.XXXXXX.log` it creates that name
  # literally (measured: a second run then fails with "File exists" on the
  # literal path and swift test never starts). The run of `X`s is kept at
  # the very end for mktemp to substitute, and `.log` is appended by a
  # rename afterwards, once mktemp has reserved a unique name.
  if ! RAW="$(mktemp "${TMPDIR:-/tmp}/helm-test.XXXXXX")"; then
    echo "!! mktemp failed to reserve a log path under ${TMPDIR:-/tmp} — refusing before swift test runs" >&2
    echo "==> FAIL (runner exit=1, swift test exit=not run)  failure-lines=0  selected=0  log=not written"
    exit 1
  fi
  LOG="${RAW}.log"
  mv "$RAW" "$LOG"
fi

# `: > "$LOG"` and `swift test ... > "$LOG"` above open $LOG by path, so a
# name spelled with a leading `-` (HELM_TEST_LOG=-, --, -v, -x, -h) is an
# ordinary file to them. Every read below instead hands $LOG to a command as
# an argument, where a leading `-` is read as an option or, for a bare `-`,
# as POSIX's own name for standard input rather than a file called `-`
# (measured: `grep -c '' "-" </dev/null` reads /dev/null, not the file `-`
# in the working directory, and `--`, `-v`, `-x` and `-h` all fall back to
# stdin the same way once no file operand is left for grep to open). POSIX
# reserves a `./`-prefixed spelling to mean the literal file, so every
# non-redirection read from here on takes $LOG through this prefixed form
# instead, while messages keep naming $LOG itself, the spelling the caller
# gave.
LOG_SAFE="$LOG"
case "$LOG_SAFE" in
  -*) LOG_SAFE="./$LOG_SAFE" ;;
esac

# An unwritable log path otherwise fails silently downstream: the redirect
# below never starts swift test, $LOG never comes to exist, every read of it
# that follows returns nothing rather than an error, FAILURE_COUNT ends up
# empty, and `[ "$FAILURE_COUNT" -gt 0 ]` dies with "integer expression
# expected" while the summary blames "swift test itself" for a status that
# was really the shell failing to open the redirect.
if ! { : > "$LOG"; } 2>/dev/null; then
  echo "!! cannot write the log at $LOG — refusing before swift test runs" >&2
  echo "==> FAIL (runner exit=1, swift test exit=not run)  failure-lines=0  selected=0  log=not written"
  exit 1
fi

echo "==> swift test --explicit-target-dependency-import-check error $* (log: $LOG)"
if [ "$SKIPPED_CLASSES" -gt 0 ]; then
  echo "==> skipping the $SKIPPED_CLASSES classes Tests/optional-tests.txt names (HELM_FULL_SUITE=1 or a --filter runs them)"
  set -- "$@" "${SKIP_ARGS[@]}"
fi
set +e
swift test --explicit-target-dependency-import-check error "$@" > "$LOG" 2>&1
STATUS=$?
set -e

# A read below can block instead of failing: given a path to a character
# device, grep opens it and blocks in read(2) until whoever holds the other
# end writes or closes, and a real terminal does neither on its own. stat()
# alone answers the type without opening anything, so ask it first and
# refuse anything that is not a plain, ordinary file before any read is
# attempted (measured: with fd 2 opened write-only or read-write on a plain
# file, `/dev/stderr` itself stats as a regular file — `[ -f ]` true, `[ -c ]`
# false — because the special path answers for the descriptor it dups
# rather than for a device of its own; with fd 2 a pipe, `[ -f ]` and `[ -c ]`
# are both false, since a FIFO is neither; and `/dev/null` always stats
# `[ -c ]` true, `[ -f ]` false, being an actual device). This is why
# `HELM_TEST_LOG=/dev/null` has to fail closed on its own, and it costs
# nothing on the ordinary path, where $LOG is the plain file written above.
if [ ! -f "$LOG_SAFE" ]; then
  echo "!! the log at $LOG is not a plain file — refusing to read it after swift test ran (exit $STATUS) rather than risk a read that blocks or answers for the wrong descriptor" >&2
  echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  log=$LOG (not a plain file)"
  exit 1
fi

# The pre-run write check above only proved the log path accepts a write; a
# path can accept a write and still refuse a read (measured:
# `HELM_TEST_LOG=/dev/stderr Scripts/test.sh --skip .` runs swift test
# straight into /dev/stderr and then reads it back here). `|| true` on a
# `grep -c` was folding that refusal into the same empty string as "grep ran
# and matched nothing," so `[ "$FAILURE_COUNT" -gt 0 ]` below read false and
# the run passed over a log that, made readable again, was found to carry
# "No matching test cases were run". `[ -r "$LOG" ]` is not the fix in its
# place — measured on the same /dev/stderr, `-r` already reads it correctly
# as unreadable on this machine, but that is a property of this system's
# fdesc filesystem, not something a gate may assume of every device node —
# so read grep's own exit status on every call that matters: 0 or 1 is a
# real answer, anything else (2 for cannot open or read, 126, 127, or
# 128+signal for a grep killed outright) means this script failed to read
# its own log, not that swift test's run was clean. A count additionally has
# to come back a plain non-negative integer: measured with a stand-in grep
# that SIGKILLs itself on this path, `$?` was 137 (not 2), FAILURE_COUNT was
# left empty, a gate reading only `-eq 2` waved that through, and the
# arithmetic test on the empty count further down died with "integer
# expression expected" instead of failing closed.
set +e
FAILURE_COUNT=$(command grep -cE 'with ([0-9]+ tests? skipped and )?[1-9][0-9]* failures?' "$LOG_SAFE")
FAILURE_COUNT_STATUS=$?
NOMATCH_COUNT=$(command grep -c 'warning: No matching test cases were run' "$LOG_SAFE")
NOMATCH_COUNT_STATUS=$?
LOG_LINE_COUNT=$(command grep -c '' "$LOG_SAFE")
LOG_LINE_COUNT_STATUS=$?
set -e
COUNTS_UNREADABLE=0
case "$FAILURE_COUNT_STATUS" in 0|1) ;; *) COUNTS_UNREADABLE=1 ;; esac
case "$NOMATCH_COUNT_STATUS" in 0|1) ;; *) COUNTS_UNREADABLE=1 ;; esac
case "$LOG_LINE_COUNT_STATUS" in 0|1) ;; *) COUNTS_UNREADABLE=1 ;; esac
case "$FAILURE_COUNT" in ''|*[!0-9]*) COUNTS_UNREADABLE=1 ;; esac
case "$NOMATCH_COUNT" in ''|*[!0-9]*) COUNTS_UNREADABLE=1 ;; esac
case "$LOG_LINE_COUNT" in ''|*[!0-9]*) COUNTS_UNREADABLE=1 ;; esac
if [ "$COUNTS_UNREADABLE" -eq 1 ]; then
  echo "!! cannot read the log at $LOG after swift test ran (a count's exit status was neither 0 nor 1, or its output was not a plain integer) — refusing to judge a run from a log this script cannot read" >&2
  echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  log=$LOG (unreadable)"
  exit 1
fi

# A plain file and a clean grep status are still not evidence the log holds
# swift test's own output: opening a path that dups an existing descriptor —
# measured on /dev/stderr with fd 2 already opened by the parent shell —
# shares that descriptor's *offset*, so a read attempted here after swift
# test's own write left it at end-of-file reads zero bytes back, cleanly,
# status 1, the same as a log that is genuinely empty. Every real swift test
# run leaves at least "Building for debugging..." behind, so a log with no
# complete line at all is never a clean pass — it is this script failing to
# see what was actually written, and gets its own reason rather than being
# read as "0 failures, 0 selected".
if [ "$LOG_LINE_COUNT_STATUS" -eq 1 ]; then
  echo "!! the log at $LOG read back with no lines after swift test ran (exit $STATUS) — a clean run always leaves swift test's own output behind, so an empty read is never evidence of one" >&2
  echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  log=$LOG (empty on read-back)"
  exit 1
fi

# swift test's own --filter matches a regular expression against
# <target>.<class>/<method> (measured: --filter
# 'DocumentsNameTheTreeTests/testTheReaderRecognisesEveryFileLineShape' selects
# exactly that one case, and a bare class name or a partial name matches by
# substring the same way). Sequentially the log spells a run case with a
# space where the filter wants a slash — `Test Case '-[Target.Class
# testMethod]' started.` — one per case swift test actually ran, whichever
# it decided to; under `--parallel` that started/failed pair is printed only
# for a case that failed, and every case, passing or not, instead gets a
# `[n/N] Testing Target.Class/method` progress line (measured: four passing
# cases under --parallel print four such lines and no started/failed pair
# at all; a failing one prints both). Both shapes are read, the sequential
# one rewritten to the same Target.Class/method spelling, and the result
# deduplicated so a failing --parallel case is not counted twice. That is
# what makes the count below the set swift test itself selected, rather
# than a guess at a name.
# The same unreadable-log gap reaches this pipeline too: grep's own exit 2
# here would have been discarded by the pipe into sed and then into
# sort -u — a pipeline's status is its last command's, and sort has no way to
# know the file grep could not open. Read each grep on its own first, so its
# $? is the one this script sees, and only hand what it found to sed once
# that status is known to be 0 or 1 (a real answer) rather than 2.
set +e
SEQ_MATCHES="$(command grep -oE "Test Case '-\[[A-Za-z0-9_.]+ [A-Za-z0-9_]+\]' started" "$LOG_SAFE")"
SEQ_STATUS=$?
PARALLEL_MATCHES="$(command grep -oE '^\[[0-9]+/[0-9]+\] Testing [A-Za-z0-9_.]+/[A-Za-z0-9_]+' "$LOG_SAFE")"
PARALLEL_STATUS=$?
set -e
SELECTION_UNREADABLE=0
case "$SEQ_STATUS" in 0|1) ;; *) SELECTION_UNREADABLE=1 ;; esac
case "$PARALLEL_STATUS" in 0|1) ;; *) SELECTION_UNREADABLE=1 ;; esac
if [ "$SELECTION_UNREADABLE" -eq 1 ]; then
  echo "!! cannot read the log at $LOG to find which test cases swift test selected (a read's exit status was neither 0 nor 1) — refusing to judge a run from a log this script cannot read" >&2
  echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  log=$LOG (unreadable)"
  exit 1
fi
SELECTED="$( { \
  [ -n "$SEQ_MATCHES" ] && printf '%s\n' "$SEQ_MATCHES" \
    | sed -E "s/Test Case '-\[([A-Za-z0-9_.]+) ([A-Za-z0-9_]+)\]' started/\1\/\2/"; \
  [ -n "$PARALLEL_MATCHES" ] && printf '%s\n' "$PARALLEL_MATCHES" \
    | sed -E 's/^\[[0-9]+\/[0-9]+\] Testing //'; \
  true; \
} | sort -u )"
# The same fold that hid a killed grep's status behind `FAILURE_COUNT_STATUS`
# above was still sitting here as `|| true`: measured with the count's own
# grep SIGKILLed on this path, `$?` was 137, `|| true` swallowed it back to
# 0, SELECTED_COUNT came back empty, and the run reported PASS with
# `selected=`. Read the real status and shape the same way as every other
# count taken from this log, and fail closed with `unknown` rather than pass
# a run this script could not actually count.
set +e
SELECTED_COUNT=$(printf '%s\n' "$SELECTED" | command grep -c .)
SELECTED_COUNT_STATUS=$?
set -e
case "$SELECTED_COUNT_STATUS" in 0|1) ;; *) SELECTION_UNREADABLE=1 ;; esac
case "$SELECTED_COUNT" in ''|*[!0-9]*) SELECTION_UNREADABLE=1 ;; esac
if [ "$SELECTION_UNREADABLE" -eq 1 ]; then
  echo "!! cannot read how many test case(s) swift test selected from the log at $LOG (a count's exit status was neither 0 nor 1, or its output was not a plain integer) — refusing to judge a run from a log this script cannot read" >&2
  echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  log=$LOG (unreadable)"
  exit 1
fi

# What the list did, read from the cases that ran: under the skip no case of
# a listed class may have run — one that did means swift test no longer reads
# `--skip '[.]<Name>/'` as this script does — and a full run that swift test
# passed must have run a case of every listed class, the run's own proof
# that each name still selects something.
OPTIONAL_RAN=""
OPTIONAL_SILENT=""
RAN_CLASSES="$(printf '%s\n' "$SELECTED" | sed -nE 's#^[A-Za-z0-9_]+[.]([A-Za-z0-9_]+)/.*#\1#p' | LC_ALL=C sort -u)"
if [ "$SKIPPED_CLASSES" -gt 0 ]; then
  OPTIONAL_RAN="$(LC_ALL=C comm -12 <(printf '%s\n' "$OPTIONAL_NAMES") <(printf '%s\n' "$RAN_CLASSES"))"
elif [ "${#FILTER_VALUES[@]}" -eq 0 ] && [ "$STATUS" -eq 0 ]; then
  OPTIONAL_SILENT="$(LC_ALL=C comm -23 <(printf '%s\n' "$OPTIONAL_NAMES") <(printf '%s\n' "$RAN_CLASSES"))"
fi

UNMATCHED=()
UNREADABLE=()
ZERO_RAN=0
if [ -n "$FILTER_VALUE" ]; then
  if [ "$SELECTED_COUNT" -eq 0 ] && [ "$NOMATCH_COUNT" -eq 0 ]; then
    # Zero cases ran and swift test never said it looked. That is not
    # necessarily a filter mismatch — a usage error (an unrecognised
    # argument, say) also ran no case and said no such thing — so naming
    # the filter's alternatives here would blame a guessed cause; say only
    # what is known: no case ran, swift test's own exit status, and where
    # to read why.
    echo "!! 0 test case(s) ran and swift test never reported a search — swift test exited $STATUS, read $LOG" >&2
    ZERO_RAN=1
  else
    ZERO_RAN=0
    echo "==> Per-alternative counts (of $SELECTED_COUNT selected test case(s)):"
    # A --filter value cannot carry a newline byte here — it was refused
    # above, before swift test ran — so splitting it on `|` is nothing more
    # than a plain `read -ra` from a here-string, and a non-empty
    # FILTER_VALUE (guaranteed by the check this block is nested in) always
    # splits into at least one alternative, so the loop below needs no
    # separate zero-element guard.
    IFS='|' read -ra ALTERNATIVES <<< "$FILTER_VALUE"
    for ALT in "${ALTERNATIVES[@]}"; do
      set +e
      COUNT="$(printf '%s\n' "$SELECTED" | command grep -cE -- "$ALT")"
      GREP_STATUS=$?
      set -e
      if [ "$GREP_STATUS" -eq 2 ]; then
        echo "    '$ALT' -> unreadable by grep -E, BSD's POSIX ERE (grep exited 2) — swift test's own filter may still have matched it" >&2
        UNREADABLE+=("$ALT")
        continue
      fi
      # Status 2 above is grep -E refusing to parse the alternative — its own
      # meaning, handled and reported as such. Any other non-0/1 status (137
      # for a killed grep, measured with $COUNT left empty and this gate
      # absent: `[: : integer expression expected` on the `-eq 0` check
      # below, waved through as a passing alternative) is this script
      # failing to read its own count, and a shape that is not a plain
      # integer is the same failure by another door.
      COUNT_UNREADABLE=0
      case "$GREP_STATUS" in 0|1) ;; *) COUNT_UNREADABLE=1 ;; esac
      case "$COUNT" in ''|*[!0-9]*) COUNT_UNREADABLE=1 ;; esac
      if [ "$COUNT_UNREADABLE" -eq 1 ]; then
        echo "!! cannot read how many selected test case(s) matched '$ALT' from the log at $LOG (grep's exit status was neither 0, 1 nor 2, or its output was not a plain integer) — refusing to judge a run from a log this script cannot read" >&2
        echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  log=$LOG (unreadable)"
        exit 1
      fi
      echo "    '$ALT' -> $COUNT"
      if [ "$COUNT" -eq 0 ]; then
        UNMATCHED+=("$ALT")
      fi
    done
  fi
fi

FAIL=0
if [ "$STATUS" -ne 0 ]; then
  echo "!! swift test itself exited $STATUS" >&2
  FAIL=$STATUS
fi
if [ "$FAILURE_COUNT" -gt 0 ]; then
  echo "!! log carries a failure line the pattern in this header finds ($FAILURE_COUNT)" >&2
  [ "$FAIL" -eq 0 ] && FAIL=1
fi
if [ "$NOMATCH_COUNT" -gt 0 ]; then
  echo "!! log carries \"No matching test cases were run\" ($NOMATCH_COUNT) — 0 cases ran" >&2
  [ "$FAIL" -eq 0 ] && FAIL=1
fi
if [ "${#UNMATCHED[@]}" -gt 0 ]; then
  # No selected case matched the alternative as grep -E reads it: a typo in
  # the alternative is one cause, a --skip covering it is another, and a
  # construct grep -E parses without error but reads unlike swift test's own
  # ICU engine (`\z`, `\A`, `\p{Lu}`, `[\w]` and the like) is a third, just
  # as ordinary — say only that it ran none as checked here, not that it
  # failed to match under swift test.
  echo "!! filter alternative(s) ran no test case as grep -E reads it: ${UNMATCHED[*]}" >&2
  [ "$FAIL" -eq 0 ] && FAIL=1
fi
if [ "${#UNREADABLE[@]}" -gt 0 ]; then
  # This checker's own grep -E could not parse the alternative; swift test
  # reads --filter in a different engine and may have matched it anyway, so
  # this is not "ran no test case" — say only that it went unchecked, and
  # fail closed rather than pass an alternative nothing here verified.
  echo "!! filter alternative(s) could not be checked (unreadable by grep -E): ${UNREADABLE[*]}" >&2
  [ "$FAIL" -eq 0 ] && FAIL=1
fi
if [ "$ZERO_RAN" -eq 1 ]; then
  [ "$FAIL" -eq 0 ] && FAIL=1
fi
if [ -n "$OPTIONAL_RAN" ]; then
  echo "!! classes Tests/optional-tests.txt names ran under the skip: $(echo $OPTIONAL_RAN)" >&2
  [ "$FAIL" -eq 0 ] && FAIL=1
fi
if [ -n "$OPTIONAL_SILENT" ]; then
  echo "!! classes Tests/optional-tests.txt names ran no case in a full run: $(echo $OPTIONAL_SILENT)" >&2
  [ "$FAIL" -eq 0 ] && FAIL=1
fi

# The last line printed has to carry this runner's own verdict, not just
# swift test's exit status — swift test can exit 0 while an unmatched
# --filter alternative still fails the run (or exit non-zero itself), and a
# reader taking only the tail (the header warns against it, but it happens)
# must not read that as green.
if [ "$FAIL" -eq 0 ]; then
  VERDICT=PASS
else
  VERDICT=FAIL
fi
echo "==> $VERDICT (runner exit=$FAIL, swift test exit=$STATUS)  failure-lines=$FAILURE_COUNT  selected=$SELECTED_COUNT  skipped-classes=$SKIPPED_CLASSES  log=$LOG"
exit $FAIL
