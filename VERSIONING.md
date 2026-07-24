# Versioning

Helm uses `MAJOR.MINOR.PATCH` (SemVer-style). The release tag is `vMAJOR.MINOR.PATCH`.

| Bump | When | Example |
|------|------|---------|
| **MAJOR** (`1.x.x`) | Global changes to the app — new architecture, breaking redesign, a milestone release. | `0.9.0 → 1.0.0` |
| **MINOR** (`x.1.x`) | New capability or polish of existing features (new module, reworked panel, added setting). | `0.2.0 → 0.3.0` |
| **PATCH** (`x.x.1`) | Bug fixes only, no new user-facing capability. | `0.3.0 → 0.3.1` |

Rules:
- A MINOR bump resets PATCH to 0 (`0.3.4 → 0.4.0`). A MAJOR bump resets both (`0.9.2 → 1.0.0`).
- The number lives in `Resources/HelmApp/Info.plist` → `CFBundleShortVersionString`.
  `CFBundleVersion` (build number) is set automatically from the git commit count
  by `Scripts/package-app.sh` — never edit it by hand.
- One release = one `CHANGELOG.md` section + one git tag `vX.Y.Z` + one `.dmg`
  attached to the GitHub release.

Release flow:
1. Bump `CFBundleShortVersionString` per the table.
2. Add a `## [X.Y.Z] — YYYY-MM-DD` section to `CHANGELOG.md`.
3. `bash Scripts/package-app.sh && bash Scripts/make-dmg.sh`
4. `gh release create vX.Y.Z build/Helm-X.Y.Z.dmg --title "Helm X.Y.Z" --notes "…"`
