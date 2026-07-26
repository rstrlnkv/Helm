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

## Rollback

There isn't one, and the shape of the updater is why: `UpdateVersion.isNewer` requires
a strictly greater version, so nothing published can pull a user *back* to an earlier
build. Two consequences worth knowing before shipping a bad one:

- To undo a dev build, publish the next one — `vX.Y.Z-dev.N+1` carrying the reverted
  code, with its digest lines. Never delete or re-tag a release people may have
  downloaded.
- A user on a prerelease who switches to Stable sees `latest`, which is the last
  stable tag — lower than what they are running, so Helm reports up-to-date and they
  stay on the prerelease until the next stable release passes it. That is by design;
  say so if someone asks why the switch appears to do nothing.

## Release flow (since 0.7.0)

**Everything ships to the dev channel first.** Cut a `vX.Y.Z-dev.N`
prerelease, run it, and triage against the log it writes (dev builds always
log — see Diagnostics below). Only when the bug and problem count is **zero**
does the same code go out as the stable `vX.Y.Z` release. Never publish to
stable without a dev round.

## Diagnostics log

Dev builds enable `HelmLog` automatically (`LogPolicy.isEnabled` keys off the
`-dev` suffix in the version). It writes one line per event to
`~/Library/Logs/Helm/helm.log`, rolls over at 2 MB, and is reachable from
Settings → Diagnostics (show in Finder, copy, clear). Stable builds stay
silent unless the user turns the switch on.

## Dev channel

Experimental builds ship as GitHub **prereleases** tagged
`vX.Y.Z-dev.N` (`v0.7.0-dev.1`, `-dev.2`, …). They never change the stable
numbering: the eventual `vX.Y.Z` release supersedes every `-dev.N` before it.

```bash
bash Scripts/package-app.sh && bash Scripts/make-dmg.sh && bash Scripts/make-zip.sh
gh release create v0.7.0-dev.1 build/Helm-0.7.0-dev.1.dmg build/Helm-0.7.0-dev.1.zip \
  --prerelease --title "Helm 0.7.0-dev.1" --notes "…"
```

In the app, About → Update channel switches between **Stable** (reads
`releases/latest`, prereleases invisible) and **Dev** (reads the releases list
and takes the newest entry, prereleases included). Switching re-checks at once.
Version ordering lives in `UpdateVersion`: `0.7.0` > `0.7.0-dev.2` >
`0.7.0-dev.1` > `0.6.1`.
