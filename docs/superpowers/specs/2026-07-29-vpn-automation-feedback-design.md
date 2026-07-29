# Telling the user a VPN automation fired — 2026-07-29

VPN rules connect and disconnect tunnels while nobody is watching. Today the
only trace is the status item's tint changing colour, which nobody sees happen.
This gives the moment a shape: the ring spins twice, and — at the user's choice
— the connection is named.

Decided with the user before any code:

- **VPN only.** Not a general "an automation fired" mechanism. Autopilot has the
  same shape and will want this, but it is one module's problem until there is a
  second consumer, and generalising means editing `ModuleDescriptor` and all
  nine descriptors for one caller.
- **The animation always plays**, in all three notice modes. It is feedback that
  the app did something, not a notification; the setting decides the fate of the
  *text* only.
- **The label is the connection's name**, for three seconds.
- **Default is the menu-bar label.** A module that acts on its own should say
  what it did, and this is the only mode that needs no new permission.
- **Ships in 0.7.2-dev.36**, not folded into dev.35 — dev.35 is a large
  refactor and its triage should not be mixed with a new feature's.

## What counts as an automation firing

Not "the VPN state changed". A tunnel the person raised by hand from Helm's
panel, from the macOS menu bar or from System Settings must not animate
anything: an indicator that fires for everything indicates nothing.

`VPNEngine` already holds the two facts needed. `_autoConnected` is the set of
connections Helm itself raised through a rule, and `_cameUp` records which of
those actually reached the up state. So:

- **Connected by automation** — `connect(name, auto: true)` succeeds.
- **Torn down by a rule** — the rule's app quit, so `VPNAutoConnectCore`
  asks the engine to disconnect. This goes through `disconnect(name, auto: true)`
  and **not** through the refresh path.
- **Dropped from under us** — a tunnel Helm raised is no longer up and is not
  coming back: the `dropped` set computed during a refresh. Helm did not cause
  this one; the network or System Settings did. It is reported anyway, because
  a tunnel the app promised to keep up going away is exactly the news the user
  wants, and it is the one case where nothing else on screen would say so.

The first draft of this spec said the rule's teardown arrived through the
refresh path. It does not — `appTerminated` calls `disconnect` directly, so the
name leaves `_autoConnected` before any refresh sees it, and the `dropped` set
is left holding only the third case above. Written down because the mistake is
invisible from the outside: implemented as first described, "a rule disconnected
your VPN" would never once have fired, and the feature would have looked
finished.

What is deliberately **not** a firing: `disconnect(name)` with no `auto:`, which
is every button in the panel and the transport command behind it.

Both produce one value:

```swift
public struct VPNAutomation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case connected, disconnected }
    public let at: Date
    public let name: String
    public let kind: Kind
}
```

The engine keeps the last one and includes it in the `state` payload it already
emits. No new event name, no new channel: the state payload is level-triggered
and replayed to late subscribers, so a view model built after the fact still
sees a firing that is still within its display window, and one that is not is
simply stale and ignored.

**The name never reaches the log.** `HelmLog` lines about this go through
`Redact.vpn`, as every other VPN line already does. The name appears on screen
and in a notification banner, both of which the user asked for; it does not
appear in a file they may paste into an issue.

## How the menu bar learns about it

`StatusAppearance` gains one optional field:

```swift
/// Spin the ring until this moment. nil = still.
public var spinUntil: Date?
```

Level-triggered, like everything else in that struct — "spin until T", not "a
thing happened". That matters because the host reads the struct whenever it
redraws and gets no events; a one-shot flag would be missed or replayed
depending on timing. It is optional with a default, so the other eight
descriptors are untouched and still compile.

`VPNDescriptor.statusAppearance(vm)` computes `spinUntil` and `title` from the
view model's last automation:

| window from `automation.at` | what the status item shows |
|---|---|
| 0 – 1.2 s | ring spinning, name beside it |
| 1.2 – 3.0 s | ring normal, name beside it |
| after 3.0 s | ring normal, no name |

The title is only produced when the notice style is `.menuBar`.

### Two rules the animation obeys

**A countdown wins.** Keep Awake draws its remaining time as an arc on this same
ring. If the chosen appearance carries a `timerProgress`, the spin does not run —
the label still appears. A continuous state must not be interrupted by a moment,
and a countdown that jumped backwards for 1.2 s would read as a bug.

**Reduce Motion wins.** `NSWorkspace.accessibilityDisplayShouldReduceMotion` is
read fresh, exactly as `HelmMotion` does it, and when it is on the ring does not
spin. The label still appears, so the information survives and only the movement
goes. This is not an option; it is the house rule.

### Which module drives the icon

Today the host picks `first { $0.tintToken != nil }` — the first active module.
A VPN spin would be invisible whenever another module happened to sort first.
The selection becomes a small pure function so it can be tested without a status
bar:

```swift
StatusPlan.choose(_ appearances: [StatusAppearance], now: Date) -> StatusAppearance
```

An appearance whose `spinUntil` is in the future wins; otherwise the existing
rule applies unchanged. A spin is at most 1.2 seconds, so the borrow is brief
and self-ending.

## Drawing it

`RingIcon.makeArc` already draws a sweep from a start angle, which is most of
the work. It gains a sibling for a fixed-length segment at a rotating phase:

```swift
static func makeSpinner(style:size:tintToken:phase: Double) -> NSImage
```

`phase` is 0…1 across the whole animation. Two revolutions means the segment's
start angle is `90 - 720 * phase`; the segment is a quarter of the circle, drawn
over the same faint track the countdown uses so the icon keeps its footprint.

**The frames are computed once.** Thirty-six images per (style, size, tint) built
on the first spin and cached — not one `NSImage` built per frame at 30 Hz in the
menu bar. `StatusItemController` already caches by a redraw key; the key gains
the frame index, because the existing bucketing exists to suppress redundant
redraws and would otherwise suppress the animation itself.

The frame timer is separate from the 1 Hz countdown tick, runs only while a spin
is live, and is invalidated the moment it is not — the same discipline
ARCHITECTURE.md § "An observer outlives the thing it points at" demands.

## The three notice modes

Stored in the VPN module's own `NamespacedStore` under `automationNotice`:

```swift
public enum VPNNotice: String, CaseIterable, Codable, Sendable {
    case silent, menuBar, system
}
```

A picker in a new section of `VPNSettingsPage`, all eight languages, default
`.menuBar`.

- **silent** — the ring spins, nothing is named.
- **menuBar** — the name sits beside the icon for three seconds. Reuses the
  `title` path the Keep Awake countdown already uses; nothing new is drawn.
- **system** — a `UNUserNotificationCenter` banner.

### The system banner is the risky part, and it is designed to fail honestly

Helm requests no notification permission today. Adding one means a new
authorization, and these builds are ad-hoc signed — ARCHITECTURE.md § Permissions
records that macOS ties such a grant to the exact binary, so every rebuild
invalidates it while the checkbox stays ticked. Whether `UNUserNotificationCenter`
authorization behaves the same way here is **not known and must be measured on a
real build**, not reasoned about.

So the mode exists and states its own condition:

- Authorization is requested when the user picks `system`, not at launch. Asking
  for a notification permission before anyone wants notifications is how people
  learn to deny them.
- If authorization is denied or unavailable, the settings row says so and offers
  the System Settings pane, in the shape `HelmPermissionNote` already uses for
  Full Disk Access and Accessibility.
- In that state the behaviour falls back to `menuBar` — and the row says that
  too. Falling back to silence would be worse: the user asked to be told
  loudly, and the one thing the app must not do is quietly not tell them.

Delivery goes through a port with a fake in tests, like every other side effect
in this codebase:

```swift
public protocol AutomationNoticePort: Sendable {
    func authorizationState() async -> NoticeAuthorization
    func requestAuthorization() async -> NoticeAuthorization
    func post(title: String, body: String) async
}
```

## What gets tested, and how

Pure logic, tests first:

- `VPNAutomation` production: an auto connect records one; a manual connect and
  a manual disconnect record nothing. This is the finding that makes the feature
  mean something, so it is the first test.
- `SpinWindow.phase(firedAt:now:)` → `nil` after 1.2 s, 0…1 inside it, and
  `SpinWindow.showsName(firedAt:now:)` → false after 3 s. Parameterised by an
  injected `now`, never the machine's clock.
- `StatusPlan.choose` — a spinning appearance wins; a countdown suppresses the
  spin but not the name; Reduce Motion suppresses the spin but not the name.
- `VPNNotice` default and round-trip through the store.
- The notice decision: which of the three outputs each mode produces, including
  the denied-authorization fallback.

Host and drawing:

- `RingIcon.makeSpinner` at phases 0, 0.25, 0.5 produces different bitmaps, and
  the same phase produces an identical one (the cache depends on it).
- The frame timer stops: after the window closes, no timer remains.

Not testable without a person: whether the banner actually appears. That is a
line in the dev build's log plus a look at the screen, and the plan says so
rather than pretending a test covers it.

## What this deliberately does not do

- **No general automation-fired mechanism.** Named above; revisit when Autopilot
  asks.
- **No per-rule choice.** One setting for the module. A person who wants
  different noise for different apps is a person we have not met.
- **No sound.** macOS's own notification settings own that.
- **No history of firings.** Autopilot's history section exists because it moves
  files; a VPN connecting is visible in the connection list already.

## Risks, stated plainly

1. **The banner may not work under ad-hoc signing.** Measured on a real build
   before the mode is offered as working; the fallback above is the design's
   answer either way.
2. **A 30 Hz redraw of a menu-bar item is a cost nobody has measured here.** The
   precomputed frame cache is the mitigation, and the plan measures the redraw
   rather than assuming it is free.
3. **Borrowing the status item from another module** is new behaviour. It lasts
   1.2 s and ends by itself, but it is worth watching in the dev build.
