# Disk Space (DaisyDisk analog) — Design

**Status:** approved
**Date:** 2026-07-25
**Module id:** `disk`

## Goal

See where disk space went, drill into it, and reclaim it safely — a sunburst
ring in Helm's instrument language, living inside the settings window like
every other module. No third-party code; techniques referenced from
MacDirStat (`getattrlistbulk` scanning) and SquirrelDisk (radial drill-down
UX) only.

## Decisions (from brainstorming)

1. **Scope:** whole volumes by default plus "scan a folder…". Full Disk
   Access improves coverage; its absence never blocks scanning what is
   readable (the permissions section already explains the grant).
2. **Visualization:** sunburst ring — Helm's own mark is a ring, so the chart
   continues the app's identity. Drawn ourselves on SwiftUI Canvas.
3. **Placement:** inside the settings window (detail pane ≈ 690×560). No
   separate window.
4. **Deletion:** a collect basket. Items are ticked into it, the sum is
   visible, one "Move to Trash" with confirmation empties it. Nothing is
   deleted directly from the ring.

## Screens

- **Start:** volume cards (name, capacity, used bar, monospaced figures) +
  "Scan a folder…" (NSOpenPanel). Orange permission note when FDA is absent.
- **Scanning:** live instrument line — files seen, bytes accumulated, current
  path; ring builds incrementally as aggregates arrive. Cancel button.
- **Result:** ring left (~360pt, 3 depth levels, free space as a dim sector,
  center = current folder name + size; click segment → drill in with
  `HelmMotion.emphasis` morph, click center → up). Right: breadcrumbs +
  current-level list with size bars; hover syncs ring segment ↔ list row.
- **Basket bar (bottom):** count, total bytes, Move to Trash (confirm),
  per-item remove, Reveal in Finder.

## Engine (`Module_Disk_Engine`)

- `DiskScanner` — walks via `getattrlistbulk` (BSD, batched attributes; the
  reason MacDirStat scans fast). Cancellable; progress callbacks throttled
  (~4/s). Runs on a utility queue via the module `blocking` pattern.
- **Honest sizes:** `totalFileAllocatedSize`-equivalent attributes; hard links
  counted once (dedup on fileID); APFS clones not double-charged where the
  attributes expose it. Free space from `volumeAvailableCapacityKey`.
- `DiskTree` — aggregated tree, small-entry folding: children below a byte
  threshold collapse into an "other" node so million-file scans stay bounded
  in memory and the ring stays legible.
- `RingLayout` (pure, TDD) — tree + focus node + depth window → segments
  (start/end angle, ring index, node ref, color index). Minimum visible angle;
  smaller entries fold into "other". Free-space sector only at volume root.
- Safety: paths under `/System`, `/Library/Apple`, sealed volume internals are
  never basketable; scan follows no symlinks; one filesystem per scan
  (`getattrlistbulk` per-volume, no crossing mount points).
- Transport: `listVolumes`, `scan(path)`, `cancel`, `progress` events pushed
  via broadcast, `trash(paths)` reusing the shared trash outcome pattern.

## UI (`Module_Disk_UI`)

- Descriptor category `.utilities`, `menuBar → .utility`.
- `RingView`: Canvas; hit-testing by angle/radius math (pure, shared with
  RingLayout tests). Colors: muted depth-derived palette from the module tint;
  hover brightens; selection ring.
- Settings page hosts the three states; module page is the whole experience.
- Strings in 8 languages; motion via `HelmMotion` only.

## Testing

- `RingLayout`: proportions, minimum-angle folding, free-space sector, focus
  windows, hit-test math. Pure, exhaustive.
- `DiskTree` aggregation: folding threshold, hard-link dedup bookkeeping,
  "other" node accounting.
- Scanner against a fixture directory tree built in tmp during tests
  (real FS, small): sizes, cancellation, no-symlink-following.
- UI states via the screenshot harness; scan of a real folder live.

## Risks

- **Scan speed** on large volumes → `getattrlistbulk` + incremental UI;
  target: home directory in seconds, full disk tolerable with progress.
- **Memory** on million-node trees → fold small entries during aggregation,
  keep the full-fidelity list only for the focused level.
- **FDA** absent → readable subset scans fine; unreadable directories shown
  as "no access" segments, counted at zero, with the grant link.

## Out of scope (v1)

- Deleting from system volumes; network volumes; Time Machine snapshot
  accounting; file-type coloring; export/reports.
