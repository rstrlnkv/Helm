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
# Reading a run: this script prints its own verdict last, one line of one
# shape whichever exit printed it —
#   ==> WORD (runner exit=N, swift test exit=N)  failure-lines=N  selected=N  skipped=N  log=PATH
# — where WORD is PASS, FAIL or SKIPPED, `selected=` counts the cases that
# ran and `skipped=` those of them that ended skipped (`unknown` where the
# runner states no count: a log it could not read, a `--parallel` one).
# SKIPPED is a run in which at least one case ran and every one of them was
# skipped: it asserted nothing, so it is not a pass, and the runner exits 1
# on it — the word for whoever reads the line, the status for whoever reads
# the status. FAIL outranks it: a run that failed any other way says FAIL
# and keeps that status. A run in which only some cases were skipped is
# judged as if none were, with their number on the line. A run in which no
# case ran fails, with or without a `--filter`. A run that ends with no such
# line was stopped before it judged: its status is non-zero and is all it
# said. The closing "Test
# Suite 'All tests' passed" speaks for the last bundle and the very last
# line, "✔ Test run with 0 tests in 0 suites passed", for Swift Testing's
# empty run — neither speaks for the suite. A summary line that also carries
# a skip count reads as zero failures under a shorter pattern, and a
# `--filter` whose alternatives match nothing, or match only in part, still
# exits 0; the runner counts each alternative against the cases that
# actually ran and fails, naming the one that ran none. An alternative that
# is a bare name — letters, digits and underscores, nothing else — is counted
# only where a target, a class or a method name starts with it, because a
# family's name found inside another family's is no evidence that the family
# ran; one found only inside a name fails the run on a line of its own, and
# spelled as a pattern, `.*Name`, it is counted anywhere. Where a bare `swift
# test` log has to be read, take the status on its own line —
#   swift test > log 2>&1; echo "EXIT=$?"
# — and count
#   command grep -cE 'with ([0-9]+ tests? skipped and )?[1-9][0-9]* failures?' log
#   command grep -c 'warning: No matching test cases were run' log
# A filter that matches in part is invisible to both counts.
#
# A tier: `--tier <name>` (or `--tier=<name>`; more than one is their union)
# runs a named set of families, so a change that touches one place is not
# proved by the whole suite. The families are read off the tree at every run
# and handed to `swift test` as ONE `--filter` of `Target\.Class/` addresses;
# no list of a directory's classes is kept here. A test class is a line
# `class Name: XCTestCase` at the head of a line, with `final` and attributes
# before it allowed. The tiers are
#   - a directory of Tests/ that holds test classes, or a module's directory
#     under Tests/Modules/, which is its EngineTests and its UITests together.
#     `Support` and `Modules` hold no test class of their own and are no tier.
#     A name is compared as spelled: the volume is case-insensitive and `disk`
#     is not `Disk`. An unknown name is refused with the tiers the tree has.
#   - `docs`: every class whose file names `StandingDocuments`, and by hand
#     ListsAgreeWithTheTreeTests and NoDocCommentIsDetachedTests.
#   - `strings`: by hand PunctuationIsTerminologyTests, StringsCoverageTests
#     and NoOrphanTranslationsTests.
#   - `windows`: the classes that put a window on the screen of whoever runs
#     them, which every other tier leaves out before its filter is built. A
#     class is one when its file's text, comments included, holds a word of
#     two lists, or names a rig, or names a member of a class so found. The
#     first list is the five calls that order a window or make it key or
#     main: `orderFront`, `orderBack`, `makeKey`, `makeMain`,
#     `NSApp.activate`. The second is the four spellings through which a
#     test puts a window of the product on the screen: `.show()` (the
#     capture bar's and the overlay's `show()` order their panels in front),
#     `.openMenu()` (the editor palette's `openMenu` pops the overlay's
#     menu), `windowed: true` (a `ShotToast` built so orders its panel in
#     front when it shows) and `PanelRig.rig` (the rig builds a capture
#     controller with the default toast, which is windowed, and a refusal
#     shows it). A rig is a file that holds a word of the first list and
#     declares no test class; a class that names, as a whole word, something
#     a rig declares at the head of a line is a window class too. The third
#     mark is one step deep: once the classes of the files found by the two
#     lists and the rig are known, a file that names a member of one of them,
#     the class declared in another file, is a window file, and its test
#     classes are window classes. A member is named by the class's name as a
#     whole word, a dot, then a letter or an underscore. The step is taken
#     once, so a class found by it marks no further file. It reads one line
#     at a time and the class's own name: a member named on the line after
#     the name, through an alias of the class, or on an instance of it
#     (`Class().member`) is not found, and such a class stays in its
#     directory's tier. It is what finds
#     TheLogHoldsAReaderThroughWhatNobodyTriedTests, which borrows the
#     `Window` that TheLogKeepsAReaderWhereTheyWereTests orders in front.
#     The two known false marks are `.show()` in
#     TheBarsTabsFoldByTheLayoutsVerdictTests, whose `rig.show()` is its own
#     `Rig` and orders nothing, and the third mark in
#     HostsTabsUnfoldWithoutABlinkTests, whose doc comment names another
#     class's test method: both lie in `windows` all the same. Whether a
#     class that takes the rig and asks for no refusal shows the toast is
#     not measured: `PanelRig.rig` marks it all the same. A class that
#     reaches a window through the product by none of these words is not
#     found, and lies in its directory's tier.
# A tier is refused, before `swift test` starts and with the one last line
# every refusal here prints, when its name is not one of these, when a name
# listed by hand is no class under Tests/, when it is left with no family, or
# when the tree cannot be read; so is a `--tier` value carrying a newline
# byte, as a `--filter` one is. Before the run, `==> tier '<name>': <N>
# families` (`1 family` for one) says how many addresses the tier handed
# over, and, when classes were left out, `; <K> that order a window are left
# to --tier windows`.
# After it, a tier family none of whose cases started fails the run on a line
# `!! tier family(ies) ran no test case:` that names each as Target.Class; a
# family whose cases were all skipped did start, and SKIPPED is judged as
# ever. `--tier` beside `--filter` is their union, as `swift test` ORs a
# repeated `--filter`: the alternatives of `--filter` are counted one by one
# as below, the families of a tier by the set they were expected to be.
#
# Usage: Scripts/test.sh [--tier <name>]... [swift test arguments...]
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
# ERE, whether it matches one of the selected cases — as it was given, except
# a bare name, which is asked with `(^|[./])` in front of it so it is found
# only where a target, class or method name starts; `swift test --filter`
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
#
# LIMIT: a skip is counted from the line a sequential run closes a skipped
# case with, `Test Case '-[Target.Class testMethod]' skipped`. Over a log
# that carries a `--parallel` progress line the runner prints
# `skipped=unknown` in place of a count and never says SKIPPED, whatever
# else the log holds: whether a parallel run writes that line for a case
# that skipped has not been measured here, and a zero counted from lines
# that may not be written would say "nothing was skipped" on nobody's
# evidence. Run a family without `--parallel` to have its skips counted and
# an all-skipped run refused.
#
# LIMIT: a tier is read from the Tests/ beside the Scripts/ this script lies
# in, wherever it is started from, while `swift test` runs in the directory
# the caller is in; nothing compares the two. A runner started by its path
# from another tree applies its own tree's tiers and window marks to that
# tree's tests: a family the other tree lacks fails the run as one that ran
# none, a window class the other tree marks differently does not.

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

# A refusal before swift test runs: its reason on standard error, then the one
# last line every such refusal ends on, and exit 1.
refuse() {
  echo "!! $1" >&2
  echo "==> FAIL (runner exit=1, swift test exit=not run)  failure-lines=0  selected=0  skipped=0  log=not written"
  exit 1
}

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
      *$'\n'*) refuse "--filter value contains a newline byte, refused before swift test runs: $(printf '%q' "$ALT")" ;;
    esac
  done
fi

# `grep` over the tests, its output left in TIER_OUT. Status 0 and 1 are
# answers (matched, matched nothing); anything else is a reading this script
# could not make, and a tier built from it would be a guess.
tier_grep() {
  local status
  set +e
  TIER_OUT="$(command grep "$@")"
  status=$?
  set -e
  case "$status" in
    0|1) ;;
    *) refuse "cannot read the tests for a tier (grep exited $status) — refusing to expand a tier from a reading this script cannot make" ;;
  esac
}

NL=$'\n'
TAB=$'\t'
CALLED_AS="$*"
TIER_NAMES=()
TIER_REST=()
TIER_LINES=()
TIER_ADDRESSES=""
# Read --tier out of the arguments, leaving every other one where it was. The
# value of --filter is skipped over whole, so a filter spelled `--tier` is not
# taken for the flag.
for ((i = 0; i < ${#ARGS[@]}; i++)); do
  case "${ARGS[$i]}" in
    --tier=*)
      TIER_NAMES+=("${ARGS[$i]#--tier=}")
      ;;
    --tier)
      TIER_NAMES+=("${ARGS[$((i + 1))]:-}")
      i=$((i + 1))
      ;;
    --filter)
      TIER_REST+=("${ARGS[$i]}")
      if [ $((i + 1)) -lt "${#ARGS[@]}" ]; then
        TIER_REST+=("${ARGS[$((i + 1))]}")
        i=$((i + 1))
      fi
      ;;
    *)
      TIER_REST+=("${ARGS[$i]}")
      ;;
  esac
done

# A tier name is compared below with a newline-joined list of the tiers, so a
# name carrying a newline could pass for two of them; it is refused whole, as
# a --filter value is.
if [ "${#TIER_NAMES[@]}" -gt 0 ]; then
  for NAME in "${TIER_NAMES[@]}"; do
    case "$NAME" in
      *$'\n'*) refuse "--tier value contains a newline byte, refused before swift test runs: $(printf '%q' "$NAME")" ;;
    esac
  done
fi

if [ "${#TIER_NAMES[@]}" -gt 0 ]; then
  # The tree this script lies in, whatever the directory it is started from.
  case "${BASH_SOURCE[0]}" in
    */*) TESTS="${BASH_SOURCE[0]%/*}/../Tests" ;;
    *) TESTS="../Tests" ;;
  esac
  DOCS_BY_HAND="ListsAgreeWithTheTreeTests${NL}NoDocCommentIsDetachedTests"
  STRINGS_BY_HAND="PunctuationIsTerminologyTests${NL}StringsCoverageTests${NL}NoOrphanTranslationsTests"

  # What the files say, each read once over the whole of Tests/: a window
  # word anywhere in a file's raw text, the standing documents, and the
  # classes. A rig is a file with a word of the first list and no class.
  ORDERING='orderFront|orderBack|makeKey|makeMain|NSApp\.activate'
  tier_grep -rlE --include='*.swift' -e "$ORDERING"'|\.show\(\)|\.openMenu\(\)|windowed: true|PanelRig\.rig' "$TESTS"
  WORD_FILES="$TIER_OUT"
  tier_grep -rlE --include='*.swift' -e "$ORDERING" "$TESTS"
  ORDERING_FILES="$TIER_OUT"
  tier_grep -rl --include='*.swift' -e 'StandingDocuments' "$TESTS"
  DOCS_FILES="$TIER_OUT"
  tier_grep -rEoH --include='*.swift' -e '^(@[A-Za-z]+ )*(final )?class [A-Za-z0-9_]+ *: *XCTestCase' "$TESTS"
  CLASS_LINES="$TIER_OUT"

  RIG_ALTERNATIVES=""
  while IFS= read -r RIG; do
    [ -n "$RIG" ] || continue
    case "$NL$CLASS_LINES" in *"$NL$RIG:"*) continue ;; esac
    tier_grep -hoE -e '^((public|private|fileprivate|internal|final|nonisolated|@[A-Za-z]+)[[:space:]]+)*(func|let|var|struct|enum|class|actor|protocol|typealias)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$RIG"
    while IFS= read -r DECLARATION; do
      [ -n "$DECLARATION" ] || continue
      RIG_ALTERNATIVES="${RIG_ALTERNATIVES:+$RIG_ALTERNATIVES|}${DECLARATION##*[[:space:]]}"
    done <<< "$TIER_OUT"
  done <<< "$ORDERING_FILES"
  RIG_USERS=""
  if [ -n "$RIG_ALTERNATIVES" ]; then
    tier_grep -rlwE --include='*.swift' -e "$RIG_ALTERNATIVES" "$TESTS"
    RIG_USERS="$TIER_OUT"
  fi
  WINDOW_FILES="$WORD_FILES$NL$RIG_USERS"

  set +e
  CLASS_ROWS="$(sed -E "s/^([^:]+):(@[A-Za-z]+ )*(final )?class ([A-Za-z0-9_]+).*/\\1${TAB}\\4/" <<< "$CLASS_LINES")"
  CLASS_ROWS_STATUS=$?
  set -e
  [ "$CLASS_ROWS_STATUS" -eq 0 ] || refuse "cannot read the test classes under $TESTS (sed exited $CLASS_ROWS_STATUS)"

  # The third mark, once: a file that names a member of a class of the files
  # found so far (`Class.member`, the name a whole word) is a window file. A
  # class named there is declared in a file already found, so a file the
  # step adds is another than the one that declares it — a found file that
  # names its own class matches too and was a window file already; classes
  # found here are not asked about again. The names are first read as fixed
  # strings with their dot, which finds a few files in two seconds where the
  # one pattern over every name took twenty-two (measured on this tree with
  # BSD grep); the pattern is then asked of those files alone.
  WINDOW_CLASSES=""
  NAMED=()
  while IFS=$'\t' read -r FILE CLASS; do
    [ -n "$CLASS" ] || continue
    case "$NL$WINDOW_FILES$NL" in
      *"$NL$FILE$NL"*)
        WINDOW_CLASSES="${WINDOW_CLASSES:+$WINDOW_CLASSES|}$CLASS"
        NAMED+=(-e "$CLASS.")
        ;;
    esac
  done <<< "$CLASS_ROWS"
  if [ -n "$WINDOW_CLASSES" ]; then
    tier_grep -rlF --include='*.swift' "${NAMED[@]}" "$TESTS"
    NAMING=()
    while IFS= read -r NAMING_FILE; do
      [ -n "$NAMING_FILE" ] || continue
      NAMING+=("$NAMING_FILE")
    done <<< "$TIER_OUT"
    if [ "${#NAMING[@]}" -gt 0 ]; then
      tier_grep -lE -e "(^|[^A-Za-z0-9_])($WINDOW_CLASSES)\\.[A-Za-z_]" "${NAMING[@]}"
      WINDOW_FILES="$WINDOW_FILES$NL$TIER_OUT"
    fi
  fi

  # One row a class: where it lies, what swift test calls it, and whether its
  # file orders a window or names the standing documents.
  ROW_ADDRESS=()
  ROW_TARGET=()
  ROW_CLASS=()
  ROW_PLACE=()
  ROW_WINDOW=()
  ROW_DOCS=()
  PLACES="$NL"
  while IFS=$'\t' read -r FILE CLASS; do
    [ -n "$CLASS" ] || continue
    REL="${FILE#"$TESTS"/}"
    case "$REL" in
      Modules/*/*/*)
        PLACE="${REL#Modules/}"
        PLACE="${PLACE%%/*}"
        TARGET="${REL#Modules/*/}"
        TARGET="Module_${PLACE}_${TARGET%%/*}"
        ;;
      Modules/*) refuse "$FILE holds a test class and lies in no target's directory" ;;
      */*)
        PLACE="${REL%%/*}"
        TARGET="$PLACE"
        ;;
      *) refuse "$FILE holds a test class and lies in no target's directory" ;;
    esac
    ROW_ADDRESS+=("$TARGET.$CLASS")
    ROW_TARGET+=("$TARGET")
    ROW_CLASS+=("$CLASS")
    ROW_PLACE+=("$PLACE")
    case "$NL$WINDOW_FILES$NL" in *"$NL$FILE$NL"*) ROW_WINDOW+=(1) ;; *) ROW_WINDOW+=(0) ;; esac
    case "$NL$DOCS_FILES$NL" in *"$NL$FILE$NL"*) ROW_DOCS+=(1) ;; *) ROW_DOCS+=(0) ;; esac
    case "$PLACES" in *"$NL$PLACE$NL"*) ;; *) PLACES="$PLACES$PLACE$NL" ;; esac
  done <<< "$CLASS_ROWS"
  if [ "${#ROW_ADDRESS[@]}" -eq 0 ]; then
    refuse "no test class found under $TESTS — refusing to expand a tier from a reading that found nothing"
  fi

  TIER_ALTERNATIVES=()
  TIER_FAMILIES=()
  for NAME in "${TIER_NAMES[@]}"; do
    BY_HAND=""
    case "$NAME" in
      docs) BY_HAND="$DOCS_BY_HAND" ;;
      strings) BY_HAND="$STRINGS_BY_HAND" ;;
      windows) ;;
      *)
        if [ -z "$NAME" ] || [[ "$PLACES" != *"$NL$NAME$NL"* ]]; then
          refuse "unknown tier '$NAME' — the tiers are:$(printf ' %s' ${PLACES} docs strings windows)"
        fi
        ;;
    esac
    # A name listed by hand that no file declares would leave its tier one
    # family short without a word.
    for HAND in $BY_HAND; do
      FOUND=0
      for ((k = 0; k < ${#ROW_CLASS[@]}; k++)); do
        if [ "${ROW_CLASS[$k]}" = "$HAND" ]; then FOUND=1; fi
      done
      [ "$FOUND" -eq 1 ] || refuse "$HAND is listed by hand for tier '$NAME' in Scripts/test.sh and no file under Tests/ declares it"
    done
    PICKED=0
    LEFT=0
    for ((k = 0; k < ${#ROW_ADDRESS[@]}; k++)); do
      IN=0
      case "$NAME" in
        windows) IN="${ROW_WINDOW[$k]}" ;;
        docs|strings)
          case "$NL$BY_HAND$NL" in *"$NL${ROW_CLASS[$k]}$NL"*) IN=1 ;; esac
          if [ "$NAME" = docs ] && [ "${ROW_DOCS[$k]}" -eq 1 ]; then IN=1; fi
          ;;
        *)
          if [ "${ROW_PLACE[$k]}" = "$NAME" ]; then IN=1; fi
          ;;
      esac
      [ "$IN" -eq 1 ] || continue
      if [ "$NAME" != windows ] && [ "${ROW_WINDOW[$k]}" -eq 1 ]; then
        LEFT=$((LEFT + 1))
        continue
      fi
      PICKED=$((PICKED + 1))
      TIER_FAMILIES+=("${ROW_ADDRESS[$k]}")
      TIER_ALTERNATIVES+=("${ROW_TARGET[$k]}\\.${ROW_CLASS[$k]}/")
    done
    LEFT_SAID=""
    if [ "$LEFT" -gt 0 ]; then LEFT_SAID="; $LEFT that order a window are left to --tier windows"; fi
    if [ "$PICKED" -eq 0 ]; then
      refuse "tier '$NAME' holds no family to run${LEFT_SAID}"
    fi
    NOUN=families
    if [ "$PICKED" -eq 1 ]; then NOUN=family; fi
    TIER_LINES+=("==> tier '$NAME': $PICKED $NOUN$LEFT_SAID")
  done

  # One family once, in an order that does not depend on the directory's.
  set +e
  TIER_ADDRESSES="$(printf '%s\n' "${TIER_FAMILIES[@]}" | sort -u)"
  TIER_ADDRESSES_STATUS=$?
  TIER_FILTER="$(printf '%s\n' "${TIER_ALTERNATIVES[@]}" | sort -u)"
  TIER_FILTER_STATUS=$?
  set -e
  if [ "$TIER_ADDRESSES_STATUS" -ne 0 ] || [ "$TIER_FILTER_STATUS" -ne 0 ]; then
    refuse "cannot order the families of a tier (sort exited $TIER_ADDRESSES_STATUS and $TIER_FILTER_STATUS)"
  fi
  TIER_FILTER="${TIER_FILTER//$NL/|}"
  if [ "${#TIER_REST[@]}" -gt 0 ]; then
    set -- "${TIER_REST[@]}" --filter "$TIER_FILTER"
  else
    set -- --filter "$TIER_FILTER"
  fi
fi

FILTER_VALUE=""
if [ "${#FILTER_VALUES[@]}" -gt 0 ]; then
  FILTER_VALUE="$(printf '%s|' "${FILTER_VALUES[@]}")"
  FILTER_VALUE="${FILTER_VALUE%|}"
fi

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
    refuse "mktemp failed to reserve a log path under ${TMPDIR:-/tmp} — refusing before swift test runs"
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
  refuse "cannot write the log at $LOG — refusing before swift test runs"
fi

if [ "${#TIER_LINES[@]}" -gt 0 ]; then
  printf '%s\n' "${TIER_LINES[@]}"
fi
if [ "${#TIER_NAMES[@]}" -gt 0 ]; then
  echo "==> swift test with the tier's families as its --filter, for: Scripts/test.sh $CALLED_AS (log: $LOG)"
else
  echo "==> swift test $CALLED_AS (log: $LOG)"
fi
set +e
swift test "$@" > "$LOG" 2>&1
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
  echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  skipped=unknown  log=$LOG (not a plain file)"
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
  echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  skipped=unknown  log=$LOG (unreadable)"
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
  echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  skipped=unknown  log=$LOG (empty on read-back)"
  exit 1
fi

# swift test's own --filter matches a regular expression against
# <target>.<class>/<method> (measured: --filter
# 'DocumentsNameTheTreeTests/testTheExcusedNamesAreStillMentioned' selects
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
# A sequential run closes a skipped case with a line of its own, spelled
# like the `started` one (read from a log of a two-case family that skipped
# whole: each case left its `started` line, a `: Test skipped` note and
# `Test Case '-[Target.Class testMethod]' skipped (N seconds).`). That line
# is what a skip is counted from, read beside the other two and its status
# kept the same way. The summary's `with 2 tests skipped and` is no count of
# cases: the same log carried it three times, once for each suite that
# closed over the two cases — their class, its bundle and the selection.
set +e
SEQ_MATCHES="$(command grep -oE "Test Case '-\[[A-Za-z0-9_.]+ [A-Za-z0-9_]+\]' started" "$LOG_SAFE")"
SEQ_STATUS=$?
PARALLEL_MATCHES="$(command grep -oE '^\[[0-9]+/[0-9]+\] Testing [A-Za-z0-9_.]+/[A-Za-z0-9_]+' "$LOG_SAFE")"
PARALLEL_STATUS=$?
SKIP_MATCHES="$(command grep -oE "Test Case '-\[[A-Za-z0-9_.]+ [A-Za-z0-9_]+\]' skipped" "$LOG_SAFE")"
SKIP_STATUS=$?
set -e
SELECTION_UNREADABLE=0
case "$SEQ_STATUS" in 0|1) ;; *) SELECTION_UNREADABLE=1 ;; esac
case "$PARALLEL_STATUS" in 0|1) ;; *) SELECTION_UNREADABLE=1 ;; esac
case "$SKIP_STATUS" in 0|1) ;; *) SELECTION_UNREADABLE=1 ;; esac
if [ "$SELECTION_UNREADABLE" -eq 1 ]; then
  echo "!! cannot read the log at $LOG to find which test cases swift test selected and which of them were skipped (a read's exit status was neither 0 nor 1) — refusing to judge a run from a log this script cannot read" >&2
  echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  skipped=unknown  log=$LOG (unreadable)"
  exit 1
fi
SELECTED="$( { \
  [ -n "$SEQ_MATCHES" ] && printf '%s\n' "$SEQ_MATCHES" \
    | sed -E "s/Test Case '-\[([A-Za-z0-9_.]+) ([A-Za-z0-9_]+)\]' started/\1\/\2/"; \
  [ -n "$PARALLEL_MATCHES" ] && printf '%s\n' "$PARALLEL_MATCHES" \
    | sed -E 's/^\[[0-9]+\/[0-9]+\] Testing //'; \
  true; \
} | sort -u )"
# Skipped cases are de-duplicated as the selected ones are, so that the two
# counts compared further down are counts of the same thing.
SKIPPED="$(printf '%s\n' "$SKIP_MATCHES" | sort -u)"
# The same fold that hid a killed grep's status behind `FAILURE_COUNT_STATUS`
# above was still sitting here as `|| true`: measured with the count's own
# grep SIGKILLed on this path, `$?` was 137, `|| true` swallowed it back to
# 0, SELECTED_COUNT came back empty, and the run reported PASS with
# `selected=`. Read the real status and shape the same way as every other
# count taken from this log, and fail closed with `unknown` rather than pass
# a run this script could not actually count. The count of skipped cases is
# taken beside it and held to the same two gates, because the verdict
# compares the two.
set +e
SELECTED_COUNT=$(printf '%s\n' "$SELECTED" | command grep -c .)
SELECTED_COUNT_STATUS=$?
SKIPPED_COUNT=$(printf '%s\n' "$SKIPPED" | command grep -c .)
SKIPPED_COUNT_STATUS=$?
set -e
case "$SELECTED_COUNT_STATUS" in 0|1) ;; *) SELECTION_UNREADABLE=1 ;; esac
case "$SKIPPED_COUNT_STATUS" in 0|1) ;; *) SELECTION_UNREADABLE=1 ;; esac
case "$SELECTED_COUNT" in ''|*[!0-9]*) SELECTION_UNREADABLE=1 ;; esac
case "$SKIPPED_COUNT" in ''|*[!0-9]*) SELECTION_UNREADABLE=1 ;; esac
if [ "$SELECTION_UNREADABLE" -eq 1 ]; then
  echo "!! cannot read how many test case(s) swift test selected, or how many of them were skipped, from the log at $LOG (a count's exit status was neither 0 nor 1, or its output was not a plain integer) — refusing to judge a run from a log this script cannot read" >&2
  echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  skipped=unknown  log=$LOG (unreadable)"
  exit 1
fi

# A run whose every selected case was skipped asserted nothing. Whether this
# is one is settled here, while the skip count is still a number: a log with
# a `--parallel` progress line states no count (the header's LIMIT says
# why), so from here on SKIPPED_COUNT may hold `unknown`, which is printed
# and never compared.
ALL_SKIPPED=0
if [ -n "$PARALLEL_MATCHES" ]; then
  SKIPPED_COUNT=unknown
elif [ "$SELECTED_COUNT" -ge 1 ] && [ "$SKIPPED_COUNT" -eq "$SELECTED_COUNT" ]; then
  ALL_SKIPPED=1
fi

UNMATCHED=()
INSIDE_ONLY=()
UNREADABLE=()
ZERO_RAN=0
if [ "$SELECTED_COUNT" -eq 0 ] && [ "$NOMATCH_COUNT" -eq 0 ]; then
  # Zero cases ran and swift test never said it looked. That is not
  # necessarily a filter mismatch — a usage error (an unrecognised
  # argument, say) also ran no case and said no such thing — so naming
  # the filter's alternatives here would blame a guessed cause; say only
  # what is known: no case ran, swift test's own exit status, and where
  # to read why. It is asked before the filter is looked at, not under it:
  # a run in which no case ran asserted nothing whether or not a --filter
  # was given, and with none there is no per-alternative count below that
  # could notice.
  echo "!! 0 test case(s) ran and swift test never reported a search — swift test exited $STATUS, read $LOG" >&2
  ZERO_RAN=1
elif [ -n "$FILTER_VALUE" ]; then
  echo "==> Per-alternative counts (of $SELECTED_COUNT selected test case(s)):"
  # A --filter value cannot carry a newline byte here — it was refused
  # above, before swift test ran — so splitting it on `|` is nothing more
  # than a plain `read -ra` from a here-string, and a non-empty
  # FILTER_VALUE (guaranteed by the check this block is nested in) always
  # splits into at least one alternative, so the loop below needs no
  # separate zero-element guard.
  IFS='|' read -ra ALTERNATIVES <<< "$FILTER_VALUE"
  for ALT in "${ALTERNATIVES[@]}"; do
    # swift test reads a bare name as a pattern too, so it runs every
    # family whose name merely contains it, and counted the same way a
    # family that is not there is reported as run through the others. A
    # bare name — non-empty, letters, digits and underscores only — is
    # therefore asked from the start of a target (the line's start), of a
    # class (behind the `.`) or of a method (behind the `/`), with nothing
    # asked of its right end, so the start of a name is still enough.
    # Anything else is a pattern and is asked as it was given.
    case "$ALT" in ''|*[!A-Za-z0-9_]*) ASKED="$ALT" ;; *) ASKED="(^|[./])$ALT" ;; esac
    set +e
    COUNT="$(printf '%s\n' "$SELECTED" | command grep -cE -- "$ASKED")"
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
      echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  skipped=unknown  log=$LOG (unreadable)"
      exit 1
    fi
    echo "    '$ALT' -> $COUNT"
    if [ "$COUNT" -eq 0 ]; then
      # A bare name that begins no name may still sit inside one, and then
      # swift test ran those cases for it — which is not "ran no test
      # case", so it is kept on a list of its own. A bare name holds no
      # pattern character, so "inside a name" is a plain substring
      # question, and the shell answers it itself: no second read whose
      # status would have to be judged.
      if [ "$ASKED" != "$ALT" ] && [[ "$SELECTED" == *"$ALT"* ]]; then
        INSIDE_ONLY+=("$ALT")
      else
        UNMATCHED+=("$ALT")
      fi
    fi
  done
fi

# The families a tier handed over are held to the run as one set: the
# families that ran are those with a case in SELECTED (a skipped case did
# start), and what was expected and is not among them is named. One set
# difference rather than one read of the log a family: a tier can hold
# hundreds, and the status of each read would have to be judged.
TIER_MISSING=()
if [ -n "$TIER_ADDRESSES" ]; then
  set +e
  TIER_RAN="$(printf '%s\n' "$SELECTED" | sed -E 's|/[^/]*$||' | sort -u)"
  TIER_RAN_STATUS=$?
  set -e
  if [ "$TIER_RAN_STATUS" -ne 0 ]; then
    echo "!! cannot read which families of the tier ran from the selected test case(s) (a read's exit status was $TIER_RAN_STATUS) — refusing to judge a run from a log this script cannot read" >&2
    echo "==> FAIL (runner exit=1, swift test exit=$STATUS)  failure-lines=unknown  selected=unknown  skipped=unknown  log=$LOG (unreadable)"
    exit 1
  fi
  while IFS= read -r FAMILY; do
    case "$NL$TIER_RAN$NL" in
      *"$NL$FAMILY$NL"*) ;;
      *) TIER_MISSING+=("$FAMILY") ;;
    esac
  done <<< "$TIER_ADDRESSES"
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
if [ "${#INSIDE_ONLY[@]}" -gt 0 ]; then
  # swift test did run cases for these, so "ran no test case" would be
  # false of them; what is known is that none of those cases belongs to a
  # target, class or method the name begins, which is what a bare family
  # name is taken to mean. Say that, and how to ask for the other reading.
  echo "!! filter alternative(s) begin no target, class or method name and were found only inside one: ${INSIDE_ONLY[*]} — a bare name is counted from the start of a name; spell it as a pattern (.*Name) to count it anywhere" >&2
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
if [ "${#TIER_MISSING[@]}" -gt 0 ]; then
  # A tier family none of whose cases started: a --skip over it is one cause,
  # an address `swift test` did not read as the runner spelled it is another.
  echo "!! tier family(ies) ran no test case: ${TIER_MISSING[*]}" >&2
  [ "$FAIL" -eq 0 ] && FAIL=1
fi
if [ "$ZERO_RAN" -eq 1 ]; then
  [ "$FAIL" -eq 0 ] && FAIL=1
fi

# The last line printed has to carry this runner's own verdict, not just
# swift test's exit status — swift test can exit 0 while an unmatched
# --filter alternative still fails the run (or exit non-zero itself), and a
# reader taking only the tail (the header warns against it, but it happens)
# must not read that as green. Nor may a run that asserted nothing: when
# nothing above failed and every selected case was skipped, the word is
# SKIPPED and the status 1, so neither a reader of the word nor a reader of
# the status takes it for a pass. A run that failed keeps FAIL and its own
# status, which sends nobody to read a failure as a skip.
VERDICT=PASS
if [ "$FAIL" -ne 0 ]; then
  VERDICT=FAIL
elif [ "$ALL_SKIPPED" -eq 1 ]; then
  echo "!! all $SELECTED_COUNT selected test case(s) were skipped, so this run asserted nothing — the reasons are the \"Test skipped\" lines in $LOG, and a re-run skips again while they hold" >&2
  VERDICT=SKIPPED
  FAIL=1
fi
echo "==> $VERDICT (runner exit=$FAIL, swift test exit=$STATUS)  failure-lines=$FAILURE_COUNT  selected=$SELECTED_COUNT  skipped=$SKIPPED_COUNT  log=$LOG"
exit $FAIL
