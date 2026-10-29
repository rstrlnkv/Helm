#!/bin/bash
set -uo pipefail

# Take a still of one Helm Dev page: launch Helm Dev on it, bring state by
# pressing controls by accessibility name, capture the window's region (with --panel, the panel window).
#
#   bash Scripts/shoot.sh <page> [--press "<control name>" [--nth <n>]]... [--arg <key> <value>]...
#                         [--scroll <fraction>] [--panel] [--name <stem>] [--inactive] [--out <dir>]
#
# --nth <n> after a --press picks the n-th (1-based, in the order `HelmReadout ax` prints) of several
# controls with that name, the same action offered twice on a page; without it two of a name are refused.
# --arg is a launch argument `-<key> <value>` after `-HelmOpenPage`, which the argument
# domain answers over defaults and writes nothing. --scroll <fraction> (0 to 1) sets the
# vertical scroll bar of the window's widest scroll area after the presses, for the part of a
# page below the fold; absolute, so a rerun gives the same frame. --panel presses the status
# item and shoots the panel (layer 101) instead of the window: its button's description is "Helm"
# (StatusItemController; its title is the countdown text while one is shown), hosted on macOS 27 by MenuBarAgent and found by Helm Dev's pid. --name is the file's
# stem after the page: <page>-<stem>.png.
#
# <page> is a Settings tab ("general", "log", "about") or a module id: Helm Dev
# opens on it by `-HelmOpenPage` (Sources/HelmApp/LaunchPage.swift), the one
# thing a press cannot reach, because Helm Dev has no window at launch. The
# names a press takes are in the language Helm Dev runs in.
#
# Never in this script: System Events, AppleScript, or a process picked by
# name — Helm and Helm Dev run one executable name, so Helm Dev is the pid
# whose executable path (`HelmReadout exe`, the kernel's, not argv[0]) is
# exactly /Applications/Helm Dev.app/Contents/MacOS/HelmApp. It never builds:
# `swift build --target HelmReadout` first, `bash Scripts/package-dev.sh` for the app.
#
# Helm Dev's defaults domain is exported before and after; if it changed, it is deleted
# and the copy imported (`defaults import` alone merges, so a key added in the run would
# stay), and a third export is compared with the copy: "defaults restored: identical|
# DIFFERENT". Only once the checked pid has ended, only the domain com.helm.app.dev.
#
# Exit: 64 usage, 65 a press, scroll or status-item press failed, 69 something missing
# (no MenuBarAgent for --panel included), 73 another shoot holds the lock (not waited
# for), 75 the screen is locked, or Helm Dev gave no window or no panel window in time,
# or Helm Dev changed identity between a check and a press, a scroll or the panel press.
# Why it works this way: ARCHITECTURE.md § Two screen instruments.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
READOUT="$ROOT/.build/debug/HelmReadout"
DEVAPP="/Applications/Helm Dev.app"
DEVEXE="$DEVAPP/Contents/MacOS/HelmApp"
DOMAIN="com.helm.app.dev"
# getconf, not $TMPDIR: a sandboxed role may have rewritten $TMPDIR.
TEMP="$(getconf DARWIN_USER_TEMP_DIR)"
LOCK="${TEMP}helm-shoot.lock"

PAGE="${1:-}"; [ $# -gt 0 ] && shift
PRESSES=(); NTHS=(); ARGS=(); SCROLL=""; PANEL=no; STEM=""; INACTIVE=no; OUT=""
USAGE="usage: bash Scripts/shoot.sh <page> [--press \"<name>\" [--nth <n>]]... [--arg <key> <value>]... [--scroll <fraction>] [--panel] [--name <stem>] [--inactive] [--out <dir>]"
while [ $# -gt 0 ]; do
  case "$1" in
    --press) [ $# -ge 2 ] || { echo "--press needs a control name" >&2; exit 64; }; PRESSES+=("$2"); NTHS+=(""); shift 2 ;;
    --nth) [ ${#PRESSES[@]} -gt 0 ] && [ $# -ge 2 ] && [[ "$2" =~ ^[1-9][0-9]*$ ]] || { echo "--nth needs a number from 1, after a --press" >&2; exit 64; }; NTHS[${#NTHS[@]}-1]="$2"; shift 2 ;;
    --arg) [ $# -ge 3 ] || { echo "--arg needs a key and a value" >&2; exit 64; }; ARGS+=("-$2" "$3"); shift 3 ;;
    --scroll) [ $# -ge 2 ] && [[ "$2" =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]] || { echo "--scroll needs a fraction from 0 to 1" >&2; exit 64; }; SCROLL="$2"; shift 2 ;;
    --panel) PANEL=yes; shift ;;
    --name) [ $# -ge 2 ] || { echo "--name needs a stem" >&2; exit 64; }; STEM="$2"; shift 2 ;;
    --inactive) INACTIVE=yes; shift ;;
    --out) [ $# -ge 2 ] || { echo "--out needs a directory" >&2; exit 64; }; OUT="$2"; shift 2 ;;
    *) echo "$USAGE" >&2; exit 64 ;;
  esac
done
[ -n "$PAGE" ] || { echo "$USAGE" >&2; exit 64; }

[ -x "$READOUT" ] || { echo "no $READOUT: run 'swift build --target HelmReadout'" >&2; exit 69; }
[ -d "$DEVAPP" ] || { echo "no $DEVAPP: run 'bash Scripts/package-dev.sh'" >&2; exit 69; }

# The lock: mkdir is the atomic step. The owner's pid is a file in it.
if ! mkdir "$LOCK" 2>/dev/null; then
  owner="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [ -z "$owner" ]; then
    echo "refused: another shoot holds $LOCK (owner pid unknown: being taken now, or left by a killed run)" >&2
    echo "if no shoot is running, clear it with: rm -rf '$LOCK'" >&2
  elif kill -0 "$owner" 2>/dev/null; then
    echo "refused: another shoot holds $LOCK (owner pid $owner, alive)" >&2
  else
    echo "refused: another shoot holds $LOCK (owner pid $owner, gone)" >&2
    echo "the owner is gone; to clear: rm -rf '$LOCK'" >&2
  fi
  exit 73
fi
echo $$ > "$LOCK/pid"
DEVPID=""
BEFORE=""

# pgrep -x narrows by the name HelmApp; the pid is Helm Dev only when its executable
# path, from the kernel, equals Helm Dev's. A process that merely says it is, is not.
devpid() {
  local p
  for p in $(pgrep -x HelmApp); do
    [ "$("$READOUT" exe "$p" 2>/dev/null)" = "$DEVEXE" ] && { echo "$p"; return 0; }
  done
  return 0
}

# SIGTERM to the checked pid only, bounded wait.
quit_dev() {
  local pid="$1" i
  [ -n "$pid" ] || return 0
  [ "$(devpid)" = "$pid" ] || return 0
  kill -TERM "$pid" 2>/dev/null
  for i in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || return 0; sleep 0.5; done
  echo "Helm Dev $pid still running after 10 s" >&2
}

finish() {
  local rc=$?
  trap - EXIT
  if [ -n "$DEVPID" ]; then
    quit_dev "$DEVPID"
    if [ -n "$BEFORE" ]; then
      # Any Helm Dev, not only ours: a reset or "Update & Relaunch" pressed during the run starts a new pid.
      if [ -n "$(devpid)" ]; then echo "defaults not restored: a Helm Dev is running" >&2
      else
        defaults export "$DOMAIN" "$OUTDIR/defaults-after.plist" 2>/dev/null
        if cmp -s "$BEFORE" "$OUTDIR/defaults-after.plist"; then echo "defaults changed: no"
        else
          # `defaults import` merges: a key added during the run would survive it. Delete, then import.
          echo "defaults changed: yes (deleting the domain, importing the copy from before)"
          if defaults delete "$DOMAIN" 2>/dev/null; defaults import "$DOMAIN" "$BEFORE"; then
            defaults export "$DOMAIN" "$OUTDIR/defaults-restored.plist" 2>/dev/null
            if cmp -s "$BEFORE" "$OUTDIR/defaults-restored.plist"; then echo "defaults restored: identical"
            else echo "defaults restored: DIFFERENT (copy at $BEFORE)" >&2; fi
          else echo "DEFAULTS IMPORT FAILED, domain $DOMAIN may be empty: the copy is at $BEFORE" >&2; fi
        fi
      fi
    fi
  fi
  rm -rf "$LOCK"
  exit $rc
}
trap finish EXIT

SESSION="$("$READOUT" session)"
echo "$SESSION"
case "$SESSION" in
  *"locked: yes"*|*"on-console: no"*) echo "refused: the screen is locked or this session is not on the console" >&2; exit 75 ;;
esac
case "$SESSION" in *"screen-recording: no"*) echo "refused: no Screen Recording grant for this chain" >&2; exit 69 ;; esac
if [ ${#PRESSES[@]} -gt 0 ] || [ -n "$SCROLL" ] || [ "$PANEL" = yes ]; then
  case "$SESSION" in *"ax-trusted: no"*) echo "refused: no Accessibility grant for this chain" >&2; exit 69 ;; esac
fi

OUTDIR="${OUT:-${TEMP}helm-shots/$(date -u +%Y%m%dT%H%M%SZ)-$PAGE}"
mkdir -p "$OUTDIR" || exit 69

# An instance that is up cannot be given arguments by `open`: end it first.
old="$(devpid)"
if [ -n "$old" ]; then echo "Helm Dev already running (pid $old): SIGTERM, wait up to 10 s"; quit_dev "$old"; fi
[ -z "$(devpid)" ] || { echo "refused: Helm Dev would not quit" >&2; exit 69; }

BEFORE="$OUTDIR/defaults-before.plist"
defaults export "$DOMAIN" "$BEFORE" 2>/dev/null

open "$DEVAPP" --args -HelmOpenPage "$PAGE" ${ARGS[@]+"${ARGS[@]}"}
for i in $(seq 1 20); do DEVPID="$(devpid)"; [ -n "$DEVPID" ] && break; sleep 0.5; done
[ -n "$DEVPID" ] || { echo "Helm Dev did not start" >&2; exit 75; }
echo "Helm Dev pid $DEVPID ($(ps -o comm= -p "$DEVPID"))"

# The first on-screen window at $LAYER (0: the page; 101: the panel) of Helm Dev wider than 100 pt: "id x,y,w,h", then its above line.
WIN=""; ABOVE=""; COUNT=0; LAYER=0
read_window() {
  local out; out="$("$READOUT" window "$DEVPID")" || return 1
  COUNT=$(printf '%s\n' "$out" | grep -c 'onscreen yes')
  WIN=""; ABOVE=""
  local line next=no
  while IFS= read -r line; do
    if [ "$next" = yes ]; then ABOVE="${line#above: }"; break; fi
    case "$line" in
      "window "*" layer $LAYER onscreen yes bounds "*)
        local id="${line#window }"; id="${id%% *}"; local b="${line##* bounds }"
        local w="${b#*,*,}"; w="${w%%,*}"
        [ "$w" -gt 100 ] && { WIN="$id $b"; next=yes; } ;;
    esac
  done <<< "$out"
  [ -n "$WIN" ]
}
for i in $(seq 1 20); do read_window && break; sleep 0.5; done
if [ -z "$WIN" ]; then
  echo "no window of Helm Dev in 10 s; log:" >&2
  grep "launch page" "$HOME/Library/Logs/Helm/helm.log" | tail -3 >&2
  exit 75
fi
sleep 1

front() { read_window && { [ "$ABOVE" = none ] && echo "front: yes" || echo "front: no (above: $ABOVE)"; }; }

for k in ${PRESSES[@]+"${!PRESSES[@]}"}; do
  name="${PRESSES[$k]}"
  [ "$(devpid)" = "$DEVPID" ] || { echo "Helm Dev $DEVPID is no longer the Helm Dev process: no press" >&2; exit 75; }
  front
  "$READOUT" press "$DEVPID" "$name" ${NTHS[$k]:+--nth "${NTHS[$k]}"} || { echo "press \"$name\" failed" >&2; exit 65; }
  sleep 1
done

if [ -n "$SCROLL" ]; then
  [ "$(devpid)" = "$DEVPID" ] || { echo "Helm Dev $DEVPID is no longer the Helm Dev process: no scroll" >&2; exit 75; }
  "$READOUT" scroll "$DEVPID" "$SCROLL" || { echo "scroll to $SCROLL failed" >&2; exit 65; }
  sleep 1
fi

if [ "$PANEL" = yes ]; then
  [ "$(devpid)" = "$DEVPID" ] || { echo "Helm Dev $DEVPID is no longer the Helm Dev process: no panel" >&2; exit 75; }
  # The status item's button is labelled "Helm" in its description, its title being the countdown text while one is shown (StatusItemController); macOS 27 hosts it in MenuBarAgent's tree.
  AGENT="$(pgrep -x MenuBarAgent | head -1)"
  [ -n "$AGENT" ] || { echo "no MenuBarAgent: the status item cannot be found" >&2; exit 69; }
  "$READOUT" statusitem "$DEVPID" "$AGENT" || { echo "press of the status item failed" >&2; exit 65; }
  LAYER=101
  for i in $(seq 1 10); do read_window && break; sleep 0.5; done
  [ -n "$WIN" ] || { echo "no panel window (layer 101) in 5 s" >&2; exit 75; }
  sleep 1
fi

if [ "$INACTIVE" = yes ]; then open -a Finder; sleep 1; fi

read_window || { echo "the window is gone" >&2; exit 75; }
B1="${WIN#* }"
x="${B1%%,*}"; r="${B1#*,}"; y="${r%%,*}"; r="${r#*,}"; w="${r%%,*}"; h="${r#*,}"
# -R, not -l: -l mis-renders an active behind-window material (measured by window probes).
FILE="$OUTDIR/$PAGE${STEM:+-$STEM}.png"
screencapture -x -R"$x,$y,$w,$h" "$FILE" || { echo "screencapture failed" >&2; exit 69; }
FRONT_ABOVE="$ABOVE"
read_window && B2="${WIN#* }" || B2="gone"
PW="$(sips -g pixelWidth "$FILE" | awk '/pixelWidth/{print $2}')"
PH="$(sips -g pixelHeight "$FILE" | awk '/pixelHeight/{print $2}')"
if [ "$FRONT_ABOVE" = none ]; then F="yes"; else F="no (above: $FRONT_ABOVE)"; fi
# -R may not honour the rect on every display arrangement: say so when the file is not bounds x scale.
SCALE="$("$READOUT" scale "$x" "$y")"
SIZE_NOTE=""
case "$SCALE" in
  unknown) SIZE_NOTE="  size check: no display holds the window's corner" ;;
  *) [ "$PW" = "$(awk -v a="$w" -v s="$SCALE" 'BEGIN{printf "%d", a*s+0.5}')" ] && [ "$PH" = "$(awk -v a="$h" -v s="$SCALE" 'BEGIN{printf "%d", a*s+0.5}')" ] \
       || SIZE_NOTE="  SIZE MISMATCH: bounds ${w}x${h} pt at scale $SCALE is not ${PW}x${PH} px" ;;
esac
echo "shot: $FILE  ${PW}x${PH} px  place before: $B1  after: $B2  front: $F  windows: $COUNT$SIZE_NOTE"
