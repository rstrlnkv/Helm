# Helm — working notes for Claude

Read [ARCHITECTURE.md](ARCHITECTURE.md) before changing the panel, status item
or settings window — the "read before touching" facts there were earned through
long debugging sessions and are easy to re-break.

## Commands

```bash
swift test                              # full unit suite, seconds
bash Scripts/package-app.sh             # build → build/Helm.app
# install + relaunch locally:
pkill -f 'MacOS/HelmApp'; bash Scripts/package-app.sh
rm -rf /Applications/Helm.app && cp -R build/Helm.app /Applications/Helm.app
xattr -dr com.apple.quarantine /Applications/Helm.app && open /Applications/Helm.app
```

## Rules of the house

- New module = descriptor + engine targets following the existing pattern
  (see ARCHITECTURE.md), registered in `ModuleRegistry.all`. Pure logic in
  `Engine/Logic/` with tests first.
- Every user-visible string goes through `L()` with all eight languages.
- Release flow and version-bump rules: [VERSIONING.md](VERSIONING.md).
  Releases attach **both** dmg and zip; the zip feeds the silent updater.
- The in-app changelog is `Sources/HelmApp/ChangelogData.swift` (localized,
  badged); `CHANGELOG.md` is the canonical English record. Update both.
- UI changes to the panel/settings: verify visually with the env-gated
  screenshot harness described in ARCHITECTURE.md (§ Dev loop) — do not ask
  the user to be the test loop; remove the harness before committing.
