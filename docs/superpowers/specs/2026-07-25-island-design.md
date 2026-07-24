# Island (Dynamic Island for the notch) — Design

**Status:** approved-pending-review
**Date:** 2026-07-25
**Module id:** `island`

## Goal

A notch-centric island: invisible at rest, it reveals on hover or on an incoming
drag, expands downward with content, and auto-shows transient events. v1 ships
the shell plus the first source — a **file shelf**. Later sources (volume/HUD,
system events, Now Playing) plug into the same event bus without reworking the
shell.

## Decisions (from brainstorming)

1. **Scope (eventual):** HID/volume, media Now Playing, system events, file
   shelf. **v1 slice:** shell + file shelf; the rest arrive one by one.
2. **Idle behaviour:** invisible — the notch stays a notch. Reveal on mouse
   hover over the notch area or on a file drag entering it; transient events
   peek on their own and hide by TTL.
3. **Placement:** a regular Helm module (`Module_Island_Engine` / `_UI`),
   registered in `ModuleRegistry`, category `.appearance`. Its UI is its own
   window at the notch (owned by the descriptor); no panel tile beyond the
   standard utility row is required.
4. Built-in display with a notch only in v1 (`NSScreen.safeAreaInsets` decides);
   external displays and fullscreen Spaces are out of scope.

## Architecture

### Shell (foundation — follows ARCHITECTURE.md's panel rules exactly)

- Window: borderless, non-activating `KeyablePanel` above the menu bar
  (`.statusBar + 1`), transparent, **sized once per screen change**: a strip
  centred on the notch, wide/tall enough for the expanded state. The frame
  never moves while visible; every size change is SwiftUI animation inside
  (measured-height accordion, top-pinned content, `.clipped()` on the card).
- `makeKey()` on expand so animations tick; clicks outside the card fall to a
  transparent tap area that collapses the island.
- States: `hidden` → `peek` (capsule slightly wider than the notch; auto
  events) → `expanded` (content below the notch). Hover in the notch rect
  opens `expanded`; leaving it (with a grace delay) collapses.
- **Event bus:** sources publish `IslandEvent`(source id, priority, TTL,
  content view id + payload). `IslandStateMachine` (pure, tested) folds events
  + hover/drag inputs into the current state and visible content: higher
  priority wins, TTL expiry falls back, manual expand pins until dismissed.

### File shelf (first source)

- **Drag-in (adjusted after the risk gate):** hovering a drag at the top edge
  triggers Mission Control on macOS 26, so aiming at the notch strip cannot be
  the primary path. Instead a global monitor detects that a file drag started
  anywhere (drag pasteboard + mouse-drag events) and the island immediately
  expands with a drop zone hanging BELOW the menu bar — the user drops onto
  the card without dwelling at the top edge. The notch-strip dragging
  destination stays as a secondary path (proven working over the invisible
  window: 5/5 `draggingEntered` in the prototype).
- **Storage: references only** — security-scoped bookmarks; files never move.
  A missing file renders greyed with a note. The shelf persists across
  relaunches (bookmarks in the module store).
- **Drag-out:** items leave via standard drag (single or as a stack); the
  destination decides copy-vs-move semantics.
- Row affordances: file icon + name + size, badge with item count in `peek`,
  Clear all, ⌘-click reveals in Finder.

### Engine/UI split

- `Module_Island_Engine`: `IslandStateMachine`, `ShelfStore` (bookmark
  encode/resolve, missing detection, persist via `NamespacedStore`), notch
  geometry (`NotchMetrics` — pure function of screen frame + safeAreaInsets),
  ports for screen parameters. No AppKit window code.
- `Module_Island_UI`: descriptor (owns the `IslandWindowController`), SwiftUI
  content (capsule, expanded card, shelf grid), settings page (enable, hover
  sensitivity, shelf clear-on-quit toggle), 8-language strings.

## Testing

- `IslandStateMachine`: hover in/out with grace delay, drag enter/exit, event
  priority, TTL expiry, pinned-expand rules. Pure, TDD.
- `ShelfStore`: add/remove/clear, bookmark round-trip (fake port), missing
  files, persistence.
- `NotchMetrics`: island rects derived from screen + insets; no-notch screens
  return nil.
- Visuals verified with the env-gated screenshot harness (slow-motion runs),
  per ARCHITECTURE.md § Dev loop.

## Risks (named)

- The hover window must never steal menu-bar clicks → interactive region is
  strictly the notch rect (no clickable menu items live there).
- ~~Drag-detection over a transparent window~~ — retired 2026-07-25: the
  prototype logged 5/5 `draggingEntered`. New named risk: macOS 26 opens
  Mission Control on top-edge drag dwell → mitigated by the global
  drag-started reveal with a below-the-bar drop zone.
- Fullscreen apps hide the menu bar → island suppressed in v1.

## Out of scope (v1)

- Volume/brightness HUD replacement, system events, Now Playing (arrive as
  later sources on the same bus).
- External displays, multiple simultaneous expanded panes, always-visible mode.
