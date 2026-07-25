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
- **No pre-release tags for now.** `UpdateVersion.parse` strips non-numeric parts, so
  `v0.3.0-beta.1` parses equal to `0.3.0` and the updater can't tell them apart. Ship
  plain `vX.Y.Z`. If betas are ever needed, teach the parser pre-release precedence first.
- The number lives in `Resources/HelmApp/Info.plist` → `CFBundleShortVersionString`.
  `CFBundleVersion` (build number) is set automatically from the git commit count
  by `Scripts/package-app.sh` — never edit it by hand.
- One release = one `CHANGELOG.md` section + one git tag `vX.Y.Z` + one `.dmg`
  attached to the GitHub release.

Release flow:
1. Bump `CFBundleShortVersionString` per the table.
2. Add a `## [X.Y.Z] — YYYY-MM-DD` section to `CHANGELOG.md`.
3. `bash Scripts/package-app.sh && bash Scripts/make-dmg.sh && bash Scripts/make-zip.sh`
4. `gh release create vX.Y.Z build/Helm-X.Y.Z.dmg build/Helm-X.Y.Z.zip --title "Helm X.Y.Z" --notes "…"`

Always attach the **`.zip`** — the in-app updater downloads it for silent install
(`Installer`); the `.dmg` is the manual/drag-install path. A release without a zip
asset falls back to opening the release page.

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
