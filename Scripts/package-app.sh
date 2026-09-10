#!/bin/bash
set -euo pipefail

# Resolve repo root (this script lives in Scripts/, repo root is its parent)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Helm.app"
BUILD_DIR="$REPO_ROOT/build"

# Build number = the number of commits in the history. It rises along one
# branch and says nothing about which commit: two branches whose histories
# hold the same count print it for different commits. The About page's
# "build N" (its only reader: Sources/HelmApp/AboutPage.swift) is a counter,
# not a commit id, and a number that silently goes DOWN is worse than a
# build that refuses to run: it reads as an older build to anyone comparing
# one copy's About page against another's.
#
# Read standard output only below for a value that must be plain digits or a
# single path — git's own diagnostics go to standard error, and merging the
# two (`2>&1`) once let a shallow clone's trace lines become the build
# number itself. GIT_TRACE and its many suffixed cousins (GIT_TRACE_SETUP,
# GIT_TRACE_REFS, GIT_TRACE_PACK_ACCESS, ...) can point at a path rather
# than a file descriptor (e.g. `GIT_TRACE=/dev/stdout`), which writes there
# directly rather than through this script's own redirection — inside
# `$(...)`, that path IS the pipe being read, so the value captured below
# would otherwise carry git's own trace line ahead of the answer. Every
# `GIT_TRACE*` name is unset below, before the first git call, which closes
# that route from the environment; it does not reach the same trace
# mechanism turned on through `trace2.normalTarget` in a config file instead
# (a global `~/.gitconfig`, `GIT_CONFIG_GLOBAL`, or the system config —
# `GIT_CONFIG_SYSTEM`, i.e. `/etc/gitconfig` — and not the repository's own
# config: measured, `trace2.normalTarget` set through any of those three
# changes nothing here, because the `export GIT_TRACE2=0 GIT_TRACE2_PERF=0
# GIT_TRACE2_EVENT=0` below wins over each of them).
for HELM_GATE_TRACE_VAR in "${!GIT_TRACE@}"; do
  unset "$HELM_GATE_TRACE_VAR"
done

# `GIT_TRACE2`, `GIT_TRACE2_PERF` and `GIT_TRACE2_EVENT` are unset by the
# loop just above along with every other `GIT_TRACE*` name, which closes
# only the environment route into trace2 — a config file's
# `trace2.normalTarget`/`trace2.perfTarget`/`trace2.eventTarget` is a second
# route the loop cannot reach, and nothing left in the environment says
# otherwise once the loop has run. Set back to `0` explicitly, each wins
# over its matching config value (measured: a healthy repository whose
# `GIT_CONFIG_GLOBAL` points `trace2.normalTarget` at `/dev/stdout` now
# builds and announces its true count instead of refusing on "printed more
# than one line", and a no-commits refusal measured against the same config
# pointed at `/dev/stderr` reads only git's own `fatal:` line, with no
# trace2 line ahead of it). That is what keeps a refusal that quotes git's
# own standard error back (below, for the three calls whose failure is
# otherwise a guess) safe to print: a stray trace line reaching standard
# error is what would otherwise become part of that quoted text.
export GIT_TRACE2=0 GIT_TRACE2_PERF=0 GIT_TRACE2_EVENT=0

# `GIT_WORK_TREE` in the environment would answer every question below from
# a work tree this checkout did not choose, and the `--git-dir` pin every
# call further down carries does not stop it (measured: `GIT_WORK_TREE=/tmp`
# makes `git --git-dir=<this repo's .git> rev-parse --show-toplevel` answer
# `/tmp`) — so its presence has to refuse before any git call is made rather
# than trust the top-level check further down to catch it. `GIT_DIR` alone
# is different: once `--git-dir` is on the command line git ignores
# `GIT_DIR` entirely, empty or pointing at another repository (measured) —
# but this guard runs before `GIT_DIR_ARG` even exists, so nothing below has
# been pinned yet, and refusing here is cheaper than trusting a pin two
# lines further down to make it moot. Tested for being SET rather than
# non-empty (`${GIT_DIR+x}`, not `${GIT_DIR:-}`): `GIT_DIR=` with nothing
# after the `=` is still a value someone set on purpose, and the emptiness
# test alone reads it as absent and lets it through.
if [ -n "${GIT_DIR+x}" ] || [ -n "${GIT_WORK_TREE+x}" ]; then
  echo "!! Build number: GIT_DIR=\"${GIT_DIR-<unset>}\" GIT_WORK_TREE=\"${GIT_WORK_TREE-<unset>}\" is set in the environment, which would steer every git call below at whatever repository those name rather than $REPO_ROOT. Refusing rather than counting a history nobody chose to ship." >&2
  exit 1
fi

# Git's own standard error is what a refusal below quotes rather than a
# guessed cause: "no .git anywhere above it" used to be printed for a
# `rev-parse --show-toplevel` failure whatever git actually said, including
# dubious ownership and a permission denial, neither of which that sentence
# was true of. Captured to a file rather than merged with standard output
# (`2>&1` would feed a value meant to be plain digits or a single path with
# git's prose), one file for the life of this script, overwritten by each
# call in turn and removed on exit including a refusal.
GIT_ERR_FILE="$(mktemp "${TMPDIR:-/tmp}/helm-package-gate-git-stderr.XXXXXX")"
trap 'rm -f "$GIT_ERR_FILE"' EXIT

# $REPO_ROOT must be git's own top level, not merely inside one: a tree with
# no `.git` of its own but sitting under an ancestor's (an archive unpacked
# inside a checkout, a module vendored into another repository) has git
# walk up and count the ancestor's history instead, silently. Every git call
# this gate makes below is pinned to `--git-dir="$REPO_ROOT/.git"` for
# exactly this reason: plain discovery (`-C "$REPO_ROOT"` with no
# `--git-dir`) does not stop at a `.git` that exists but is not a working
# repository — measured for an empty directory, one holding only empty
# `objects`/`refs`, an empty file and a dangling symlink, all named
# `.git` — it keeps walking up and silently answers from whatever real
# `.git` sits above (measured: an ancestor 30 commits deep whose config
# points `core.worktree` at `inner/sub`, nothing of its own underneath,
# answered with the ancestor's own toplevel and, uncaught, would have gone
# on to count the ancestor's history). Pinned this way git refuses outright
# on all four ("fatal: not a git repository", or for the empty file "fatal:
# invalid gitfile format") instead of walking past them. A worktree's
# `.git` and a submodule's are each a *file* naming the real directory
# elsewhere (`gitdir: ...`, absolute for a worktree, relative for a
# submodule); `--git-dir` given that literal path follows it exactly the
# way discovery would, so a plain repository, a worktree and a submodule
# all still answer with their own true count (measured). What the pin does
# not reach is $REPO_ROOT/.git naming a *work tree* other than $REPO_ROOT
# itself (its own `core.worktree` pointed elsewhere) — caught by the
# comparison below, which asks whether the two paths are the *same
# directory* (`-ef`, same device and inode) rather than whether they are
# spelled the same way. A spelling compare, even resolved with `pwd -P` on
# both sides first, fails open on a healthy tree reached through another
# spelling of its own path: entered as `.../CASE-new` for a directory that
# is `case-new` on disk, bash's own `pwd -P` keeps the typed case while
# git's `--show-toplevel` answers with the on-disk spelling, so the two
# never matched and this checkout refused itself, falsely, as "a work tree
# other than $REPO_ROOT itself" (measured, on this tree's own case and on an
# NFC directory entered through its NFD spelling); `-ef` treats both as the
# one directory they are. What `-ef` actually catches is this repository's
# OWN `core.worktree` pointed at another, existing directory: `--git-dir`
# resolves straight to $REPO_ROOT/.git, its config names the other directory
# as the work tree, and `-ef` answers false for the two distinct inodes. An
# ancestor's `core.worktree` is a different story and never reaches this
# line at all: with $REPO_ROOT holding no `.git` of its own, the pin above
# already refuses on "fatal: not a git repository" before `-ef` runs, and
# with $REPO_ROOT holding its own `.git`, the pin resolves there directly and
# the ancestor's config is never consulted.
GIT_DIR_ARG="--git-dir=$REPO_ROOT/.git"
TOPLEVEL="$(git -C "$REPO_ROOT" "$GIT_DIR_ARG" --no-replace-objects rev-parse --show-toplevel 2>"$GIT_ERR_FILE")" || {
  echo "!! Build number: \`git -C $REPO_ROOT $GIT_DIR_ARG rev-parse --show-toplevel\` failed for $REPO_ROOT. Refusing rather than shipping build 1 below whatever is already out. git said: $(cat "$GIT_ERR_FILE")" >&2
  exit 1
}
case "$TOPLEVEL" in
  *$'\n'*)
    echo "!! Build number: \`git rev-parse --show-toplevel\` printed more than one line for $REPO_ROOT. Refusing rather than trusting output that is not the single path this check expects." >&2
    exit 1
    ;;
esac
if [ ! -e "$TOPLEVEL" ]; then
  echo "!! Build number: \`git rev-parse --show-toplevel\` named a path for $REPO_ROOT that does not exist on disk (\"$TOPLEVEL\"). Refusing rather than trusting it." >&2
  exit 1
fi
if ! [ "$TOPLEVEL" -ef "$REPO_ROOT" ]; then
  echo "!! Build number: \`git rev-parse --show-toplevel\` answered \"$TOPLEVEL\" for $REPO_ROOT, and that is not the same directory as $REPO_ROOT itself (different device or inode). Refusing rather than shipping a build number for the wrong tree." >&2
  exit 1
fi

# Three mechanisms give a commit a shorter parent chain (or none at all), and
# each makes `git rev-list --count HEAD` walk less history than really
# happened and undercount with no error of its own — the count can go DOWN,
# which is the one thing this gate exists to prevent. A replacement ref
# (`git replace --graft`, under refs/replace) refuses outright below, rather
# than only being neutralised with `--no-replace-objects` on the count
# further down — an existing replacement means somebody already needed the
# real parent hidden, which the count should not silently work around. The
# older `info/grafts` file has no such flag to neutralise it at all, so it is
# refused on the same finding: present. The commit-graph cache
# (`objects/info/commit-graph`) is neither refused nor checked for tampering
# here — a forged one still parses as a well-formed cache and git trusts its
# stored parent pointers over walking the objects themselves, so a graph
# edited to drop one commit's parent (measured: a true count of 10 read back
# as 6) looks exactly like an untouched one from here. `-c
# core.commitGraph=false` on the count further down is what neutralises it,
# the same role `--no-replace-objects` plays for a replacement ref.
REPLACE_REFS="$(git -C "$REPO_ROOT" "$GIT_DIR_ARG" for-each-ref refs/replace)" || {
  echo "!! Build number: \`git for-each-ref refs/replace\` failed for $REPO_ROOT. Refusing rather than counting without knowing whether a replacement ref shortens this history." >&2
  exit 1
}
if [ -n "$REPLACE_REFS" ]; then
  echo "!! Build number: $REPO_ROOT has at least one ref under refs/replace, which can give a commit a shorter parent chain than it really has. Refusing rather than counting a history that may have been shortened this way." >&2
  exit 1
fi
GRAFTS_PATH="$(git -C "$REPO_ROOT" "$GIT_DIR_ARG" --no-replace-objects rev-parse --git-path info/grafts)" || {
  echo "!! Build number: \`git rev-parse --git-path info/grafts\` failed for $REPO_ROOT. Refusing rather than counting without knowing whether a graft shortens this history." >&2
  exit 1
}
case "$GRAFTS_PATH" in
  *$'\n'*)
    echo "!! Build number: \`git rev-parse --git-path info/grafts\` printed more than one line for $REPO_ROOT. Refusing rather than trusting output that is not the single path this check expects." >&2
    exit 1
    ;;
esac
if [ -s "$GRAFTS_PATH" ]; then
  echo "!! Build number: $GRAFTS_PATH exists and is not empty. Refusing rather than counting a history a graft may have shortened." >&2
  exit 1
fi

# Two ways to fail to count survive this far, since the checks above have
# already required $REPO_ROOT/.git to exist and to resolve, through the
# pinned --git-dir, to $REPO_ROOT's own work tree: a shallow clone, where
# `rev-list --count HEAD` exits 0 but counts only what was fetched
# (`--depth 5` answers `5`), so the exit status alone does not see it —
# caught below by requiring `is-shallow-repository`'s answer to be exactly
# `false` (an old git that does not know the flag echoes it back verbatim
# and exits 0, which is neither `true` nor `false` and refuses the same
# way); and a repository with no commits at all (a fresh `git init` over
# sources, no `HEAD` to count), where `is-shallow-repository` answers
# `false` and only `rev-list --count HEAD` itself fails, with git's own
# `fatal: ambiguous argument 'HEAD'` and no word this was the build number.
# `is-shallow-repository` itself failing outright is not a cause this gate
# can name from here — git's own standard error is quoted rather than
# guessed, the same as the `show-toplevel` call above it (the two calls in
# between, `for-each-ref` and `rev-parse --git-path`, do not use this
# scheme: neither redirects its own standard error into $GIT_ERR_FILE).
# `--no-replace-objects` and
# `-c core.commitGraph=false` on the count below keep, respectively, a
# replacement ref (`git replace --graft`) and a forged or stale
# commit-graph cache from shortening the history it walks. The result must
# also be plain digits before it is trusted, in case anything else ever
# reaches standard output where only a count belongs. Checked here, before
# the compile, so a refusal costs seconds rather than a release build.
IS_SHALLOW="$(git -C "$REPO_ROOT" "$GIT_DIR_ARG" --no-replace-objects rev-parse --is-shallow-repository 2>"$GIT_ERR_FILE")" || {
  echo "!! Build number: \`git -C $REPO_ROOT rev-parse --is-shallow-repository\` failed for $REPO_ROOT. Refusing rather than shipping build 1 below whatever is already out. git said: $(cat "$GIT_ERR_FILE")" >&2
  exit 1
}
if [ "$IS_SHALLOW" != "false" ]; then
  echo "!! Build number: \`git rev-parse --is-shallow-repository\` did not answer exactly \"false\" for $REPO_ROOT. Refusing rather than trusting \`git rev-list --count HEAD\` against a history this could not confirm is complete." >&2
  exit 1
fi
BUILD_NO="$(git -C "$REPO_ROOT" "$GIT_DIR_ARG" --no-replace-objects -c core.commitGraph=false rev-list --count HEAD 2>"$GIT_ERR_FILE")" || {
  echo "!! Build number: \`git -C $REPO_ROOT rev-list --count HEAD\` failed for $REPO_ROOT. Refusing rather than shipping build 1 below whatever is already out. git said: $(cat "$GIT_ERR_FILE")" >&2
  exit 1
}
if ! [[ "$BUILD_NO" =~ ^[0-9]+$ ]]; then
  echo "!! Build number: \`git rev-list --count HEAD\` printed \"$BUILD_NO\" on standard output, not a plain count. Refusing rather than writing that into CFBundleVersion." >&2
  exit 1
fi
# Printed here, right after the gate and before the compile it guards,
# rather than only once more after the plist is written below — this is
# what lets a caller (or a test) see an undercount without paying for a
# release build to find out.
echo "==> Build number: $BUILD_NO"
# The bundle is assembled and signed OUTSIDE the repo.
#
# This checkout lives under ~/Documents, which a file provider syncs, and the
# provider stamps com.apple.FinderInfo onto directories it manages faster than
# `xattr -c` removes it. codesign refuses a bundle carrying it ("resource fork,
# Finder information, or similar detritus not allowed"), so signing in place
# here succeeds or fails by luck — and an unsigned bundle has no cdhash for TCC
# to hang Full Disk Access on, which is why the permission kept coming loose.
# TMPDIR (/var/folders/…) is not synced, so the seal survives there.
STAGE_DIR="${TMPDIR:-/tmp}/helm-package"
APP_DIR="$STAGE_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Building release binary"
# The product, not the package. A bare `swift build -c release` builds every
# target in the manifest, and one of them is `HelmTestSupport` — a plain target
# that imports XCTest, which resolves out of the Xcode-only framework path. So a
# release build needed a full Xcode install where a toolchain had been enough,
# and HelmTestSupport.swiftmodule landed in Release beside HelmApp. Declaring
# `products:` does not fix this by itself (measured: a bare build still builds
# all 466 steps); naming the product is what does — 187 steps, and no harness.
swift build -c release --product HelmApp

echo "==> Assembling $APP_DIR (idempotent)"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$BUILD_DIR"

cp "$REPO_ROOT/.build/release/HelmApp" "$MACOS_DIR/HelmApp"
cp "$REPO_ROOT/Resources/HelmApp/Info.plist" "$CONTENTS_DIR/Info.plist"

# The ring artwork the icon is built from: the in-app mark draws the same
# shape, so editing the icon in Icon Composer updates the app too.
cp "$REPO_ROOT/Resources/Icon/Helm.icon/Assets/helm-ring.svg" "$RESOURCES_DIR/helm-ring.svg"
# SwiftPM resource bundles. A target that declares `resources:` gets its own
# .bundle beside the binary, and `Bundle.module` looks for it next to the
# executable — miss this copy and the flag artwork is simply absent at
# runtime, with every layout quietly falling back to letters and nothing in
# the build saying so.
BUNDLE_COUNT=0
for bundle in "$REPO_ROOT"/.build/release/*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$CONTENTS_DIR/Resources/"
  BUNDLE_COUNT=$((BUNDLE_COUNT + 1))
done
echo "==> Resource bundles copied: $BUNDLE_COUNT"
if [ "$BUNDLE_COUNT" -eq 0 ]; then
  echo "!! No SwiftPM resource bundles found — Bundle.module lookups will fail" >&2
  exit 1
fi

# The third-party notice travels with the app, not only with the repo: the
# .app is a distribution too, and MIT asks for the notice in "all copies".
cp "$REPO_ROOT/NOTICE.md" "$RESOURCES_DIR/NOTICE.md"

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

# BUILD_NO was computed, checked and already announced above, before the
# compile. Written here, where the rest of the plist is: `Set` on a key
# `Resources/HelmApp/Info.plist` already carries as a placeholder does not
# fail, but a bad target path would, and that failure must stop the build
# rather than ship the placeholder `1` with nothing said.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NO" "$CONTENTS_DIR/Info.plist"

echo "==> Compiling Liquid Glass app icon (Icon Composer .icon → Assets.car)"
ICONOUT="$BUILD_DIR/iconout"
rm -rf "$ICONOUT" && mkdir -p "$ICONOUT"
xcrun actool "$REPO_ROOT/Resources/Icon/Helm.icon" \
  --compile "$ICONOUT" \
  --platform macosx \
  --minimum-deployment-target 26.0 \
  --app-icon Helm \
  --output-partial-info-plist "$ICONOUT/partial.plist" \
  --output-format human-readable-text
cp "$ICONOUT/Assets.car" "$RESOURCES_DIR/Assets.car"
cp "$ICONOUT/Helm.icns" "$RESOURCES_DIR/Helm.icns"

echo "==> Ad-hoc signing"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
# Verified here, where the signature is intact. This check was missing: signing
# reported success for months while producing a bundle codesign rejects.
codesign --verify --deep --strict "$APP_DIR"
echo "==> Signature verified"

# A copy in the repo for convenience only. It cannot be verified or installed
# from — the file provider re-stamps its root the moment it lands.
ditto "$APP_DIR" "$BUILD_DIR/$APP_NAME"

echo "==> Done"
echo "Signed app (install and package from here): $APP_DIR"
echo "Convenience copy (do not install):          $BUILD_DIR/$APP_NAME"
