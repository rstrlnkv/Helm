# Versioning

Helm uses `MAJOR.MINOR.PATCH` (SemVer-style). The release tag is `vMAJOR.MINOR.PATCH`.

| Bump | When | Example |
|------|------|---------|
| **MAJOR** (`1.x.x`) | Global changes to the app — new architecture, breaking redesign, a milestone release. | `0.9.0 → 1.0.0` |
| **MINOR** (`x.1.x`) | New capability or polish of existing features (new module, reworked panel, added setting). | `0.2.0 → 0.3.0` |
| **PATCH** (`x.x.1`) | Bug fixes only, no new user-facing capability. | `0.3.0 → 0.3.1` |

Rules:
- A MINOR bump resets PATCH to 0 (`0.3.4 → 0.4.0`). A MAJOR bump resets both (`0.9.2 → 1.0.0`).
- **Pre-1.0:** while `0.x`, MINOR is the main lane (features + polish); don't bump
  MAJOR. Reserve `1.0.0` for a real milestone — Developer ID + notarization (opens
  cleanly, no `xattr`) plus a stable module set. "1.0" means "ready for other people".
- **Every release bumps the version.** The updater compares versions with
  `UpdateVersion.isNewer`; two releases sharing a version means clients never see the
  update. No bump → no release.
- **Pre-release tags are the `-dev.N` lane and nothing else.** `UpdateVersion.parse`
  drops everything from the `-` on, and `prereleaseOrdinal` supplies the tiebreak: a
  prerelease sorts below its own release and above every earlier version
  (`0.7.0` > `0.7.0-dev.2` > `0.7.0-dev.1` > `0.6.1`). The ordinal is the trailing
  number of the suffix, so `-dev.2` and `-beta.2` compare equal — use one suffix, `-dev`.
- The number lives in `Resources/HelmApp/Info.plist` → `CFBundleShortVersionString`.
  `CFBundleVersion` (build number) is set automatically from the git commit count
  by `Scripts/package-app.sh` — never edit it by hand.
- One release = one `CHANGELOG.md` section + one git tag `vX.Y.Z` + **both** `.dmg`
  and `.zip` attached, and the `sha256` line for each in the notes.

Release flow:
1. Bump `CFBundleShortVersionString` per the table.
2. Add a `## [X.Y.Z] — YYYY-MM-DD` section to `CHANGELOG.md`.
3. `bash Scripts/package-app.sh && bash Scripts/make-dmg.sh && bash Scripts/make-zip.sh`

   Both packaging scripts read the **signed** bundle from `$TMPDIR/helm-package` and
   re-run `codesign --verify --deep --strict` before packaging — they exit non-zero
   rather than ship a bundle whose seal the sync folder broke. They never touch
   `build/Helm.app`, which is a copy for inspection only (ARCHITECTURE.md § Dev loop).
4. `git push` — **before** creating the release, or the tag lands on the old
   remote HEAD.
5. `gh release create vX.Y.Z build/Helm-X.Y.Z.dmg build/Helm-X.Y.Z.zip --title "Helm X.Y.Z" --notes "…"`

**The notes must carry the digest lines** `make-zip.sh` and `make-dmg.sh` print:

```
sha256 Helm-X.Y.Z.zip <64 hex>
```

The updater strips quarantine and the app is ad-hoc signed, so nothing about the
downloaded file is verified by macOS. `ReleaseDigest` is the only check there is:
without a matching line the update is not installed silently at all — the release
page opens instead and the user decides.

Always attach the **`.zip`** — the in-app updater downloads it for silent install
(`Installer`); the `.dmg` is the manual/drag-install path. A release without a zip
asset falls back to opening the release page.

## The disk image window

`make-dmg.sh` builds a laid-out window, not a bare folder. The background is
generated at build time by `Scripts/design/make-dmg-background.swift`; the
layout lives in `Scripts/dmg-settings.py`. **The two hold the same numbers seen
from two sides — change one and change the other.**

Three drawings are kept, chosen by `HELM_DMG_STYLE` or by the default at the
top of `make-dmg.sh`:

- **`field`** — squared paper, because measuring is what the app
  does. The grid fades before the window's edges: ruled hard into them it reads
  as a screenshot of something larger that got cropped.
- **`bezel`** (what ships) — the frame the About page puts the mark in, with
  the same ticks unrolled into a straight run ending in a chevron of the same
  strokes. The ring is open at the bottom, where Finder writes the icon's name:
  closed, it ran behind the word and the two crowded each other.
- **`sweep`** — one wedge of the sunburst opened towards Applications.

**A dev image is marked, and marks itself.** The ticks take the blue of the DEV
badge in About and the same capsule sits in the corner; `make-dmg.sh` decides
from the version string, not from a flag anyone has to remember. A screenshot
of a dev window turns up in an issue sooner or later and must not be mistaken
for a release.

**The window is never asked of Finder.** On macOS 26 Finder accepts the icon
view options over AppleScript, reports them back correctly when queried, and
draws its default window anyway: 48 pt icons in a grid, no background. This was
checked twice — with a hand-written `osascript` block and with Homebrew's
`create-dmg`, the maintained tool that does the same dance — and both produced
the same nothing, so it is the OS rather than any one script. Only the window's
*bounds* still take.

So `dmgbuild` writes the `.DS_Store` directly instead. It lives in a virtual
environment under `build/dmg-tools`, which `make-dmg.sh` creates on first run;
it is not installed into the system Python, which Homebrew marks externally
managed and which is not this project's to write into. `build/` is gitignored,
so a fresh clone pays for the environment once.

Judge the result by mounting it, never by reading the script:

```bash
open build/Helm-X.Y.Z.dmg      # icons at 128 pt, on the drawn background
```

Three things say it worked. `.DS_Store` is well over the 6148 bytes an
untouched one occupies (about 16k here) — that size is the tell that Finder
wrote a default and the settings were lost. `GetFileInfo` on the mounted volume
shows `C` among the attributes, so the volume icon is more than a file nobody
looks at. And `codesign --verify --deep --strict` still passes on the app
*inside* the image.

When changing the background, judge it against a composite of the real icons
and their real labels rather than the empty artwork. The first version's bezel
ran straight through the word "Helm" that Finder writes under the icon, and on
the bare background there was nothing to see it against.

## Rollback

There isn't one, and the shape of the updater is why: `UpdateVersion.isNewer` requires
a strictly greater version, so nothing published can pull a user *back* to an earlier
build. Two consequences worth knowing before shipping a bad one:

- To undo a dev build, publish the next one — `vX.Y.Z-dev.N+1` carrying the reverted
  code, with its digest lines. Never delete or re-tag a release people may have
  downloaded.
- A user on a prerelease who switches to Beta sees `latest`, which is the last
  non-prerelease tag — lower than what they are running, so Helm reports up-to-date
  and they stay on the prerelease until the next beta release passes it. By design;
  say so if someone asks why the switch appears to do nothing.

## Release flow (since 0.7.0)

**Everything ships to the dev channel first.** Cut a `vX.Y.Z-dev.N`
prerelease, run it, and triage against the log it writes (dev builds always
log — see Diagnostics below). Only when the bug and problem count is **zero**
does the same code go out as the beta `vX.Y.Z` release. Never publish to the
beta channel without a dev round.

## Diagnostics log

Dev builds enable `HelmLog` automatically (`LogPolicy.isEnabled` keys off the
`-dev` suffix in the version). It writes one line per event to
`~/Library/Logs/Helm/helm.log`, rolls over at 2 MB, and is reachable from
Settings → Diagnostics (show in Finder, copy, clear). Beta builds stay
silent unless the user turns the switch on.

## Dev channel

Experimental builds ship as GitHub **prereleases** tagged
`vX.Y.Z-dev.N` (`v0.7.0-dev.1`, `-dev.2`, …). They never change the beta
numbering: the eventual `vX.Y.Z` release supersedes every `-dev.N` before it.

```bash
bash Scripts/package-app.sh && bash Scripts/make-dmg.sh && bash Scripts/make-zip.sh
gh release create v0.7.0-dev.1 build/Helm-0.7.0-dev.1.dmg build/Helm-0.7.0-dev.1.zip \
  --prerelease --title "Helm 0.7.0-dev.1" --notes "…"
```

In the app, About → Update channel switches between **Beta** (reads
`releases/latest`, prereleases invisible) and **Dev** (reads the releases list
and takes the newest entry, prereleases included). Switching re-checks at once.
Version ordering lives in `UpdateVersion`: `0.7.0` > `0.7.0-dev.2` >
`0.7.0-dev.1` > `0.6.1`.
