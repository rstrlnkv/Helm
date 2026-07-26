# Helm — working notes for Claude

Read [ARCHITECTURE.md](ARCHITECTURE.md) before changing the panel, status item
or settings window — the "read before touching" facts there were earned through
long debugging sessions and are easy to re-break.

## Commands

```bash
swift test                              # full unit suite, seconds
bash Scripts/package-app.sh             # build + sign → $TMPDIR/helm-package/Helm.app
# install + relaunch locally (from the SIGNED copy, never from build/):
pkill -f 'MacOS/HelmApp'; bash Scripts/package-app.sh
rm -rf /Applications/Helm.app
ditto "$TMPDIR/helm-package/Helm.app" /Applications/Helm.app
codesign --verify --deep --strict /Applications/Helm.app   # must pass, or TCC drops grants
xattr -dr com.apple.quarantine /Applications/Helm.app && open /Applications/Helm.app
```

## Rules of the house

- **Everything ships to the dev channel first** (`vX.Y.Z-dev.N`, prerelease),
  is triaged against `~/Library/Logs/Helm/helm.log`, and goes stable only at
  zero known problems. Flow and commands: [VERSIONING.md](VERSIONING.md).
  Releases attach **both** dmg and zip; the zip feeds the silent updater.
- New module = descriptor + engine targets following the existing pattern
  (see ARCHITECTURE.md), registered in `ModuleRegistry.all`. Pure logic in
  `Engine/Logic/` with tests first. Shared plumbing lives in `HelmRuntime` —
  log + redaction, permissions + `TrashFailure`, removal scope, release digest,
  system-extension parsing, module order — check there before writing a helper
  inside a module.
- **The engine has the last word on deletion.** Anything that trashes paths goes
  through `RemovableScope.partition` inside the engine, not only through the view
  model that built the plan; refusals come back as
  `TrashFailure.Reason.outOfScope`, never dropped (ARCHITECTURE.md § Removal scope).
- **The log carries no names.** VPN names and app names go through `Redact.vpn` /
  `Redact.app`, paths through `Redact.path`. Counts and outcomes are free.
- **A release without its digest does not install.** The notes must carry the
  `sha256 <asset> <hex>` line `make-zip.sh` prints, or the updater opens the
  release page instead (VERSIONING.md).
- Pills are `HelmBadge`, cards are `.helmCard()` — one of each, no local variants.
- Every user-visible string goes through `L()` with all eight languages.
- Animations come from `HelmMotion` tokens, never inline curves. Reveals grow
  (measured height + `.clipped()`), never fade; literal colours inside
  animated blocks (ARCHITECTURE.md § Motion has the why).
- The in-app changelog is `Sources/HelmApp/ChangelogData.swift` (localized,
  badged, **user-facing — no fix minutiae**); `CHANGELOG.md` is the canonical
  English record. Update both.
- UI changes: verify visually with an env-gated screenshot harness
  (`HELM_DEBUG_*` in AppDelegate; ARCHITECTURE.md § Dev loop) — do not ask the
  user to be the test loop; `grep -r HELM_DEBUG Sources/` must be clean before
  committing. When a visual bug is subtle, measure pixels across frames
  instead of judging by eye.
- Commit messages with quotes/parens: write to a scratchpad file, `git commit -F`.
