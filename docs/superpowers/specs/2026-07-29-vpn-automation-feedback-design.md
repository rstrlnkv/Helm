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

This is the table for an idle menu bar. There is one status item and one title
slot, and a module already using them keeps them — see "Which module drives the
icon" below for exactly how much of the firing survives that.

### Two rules the animation obeys

**A countdown wins — the whole icon, not only the movement.** Keep Awake draws
its remaining time as an arc on this same ring. A live countdown outranks a live
spin in `StatusPlan.choose`, so the appearance the host draws is the counting
one and `StatusPlan.spins` refuses to move it. A continuous state must not be
interrupted by a moment, and a countdown that jumped backwards for 1.2 s would
read as a bug.

The first version of this rule said "the spin does not run — the label still
appears". That was never achievable and the code never did it: the title slot
holds the countdown's own remaining time, so there is nowhere for the name to
go. **While another module owns the icon, the menu bar does not announce a
firing at all.** Someone who wants to be told regardless picks the banner, which
is the mode that owns its own surface.

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

Four tiers, in order:

1. an appearance with a live `timerProgress` — a countdown owns the icon while
   it runs;
2. the newest live spin;
3. the first that tints, which is the rule that was always here;
4. the first that carries a title.

A spin is at most 1.2 seconds, so the borrow in tier 2 is brief and
self-ending. Tier 1 is what makes `StatusPlan.spins`'s `timerProgress == nil`
guard reachable at all: no descriptor puts a countdown and a spin on one
appearance, so a guard that reads only the chosen appearance answers for
whichever module was chosen — and while the spin ranked first, that was always
VPN's, which never counts down.

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
authorization behaves the same way here was the design's open question; it was
measured on a real build and the answer is **no** — see Risks 1 below.

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
- `StatusPlan.choose` — a spinning appearance wins over a tint; a countdown wins
  over a spin, built from **two** appearances, which is the composition the app
  produces; Reduce Motion suppresses the spin but not the name.
- `VPNNotice` default and round-trip through the store.
- The notice decision: which of the three outputs each mode produces, for every
  answer macOS can give, with the stored mirror deliberately holding the
  opposite — a firing is decided on what the system says now, not on a memory.

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

## Risks, measured

Measured 2026-07-29 on macOS 26 (Darwin 27.0.0), Helm 0.7.2-dev.35 installed to
`/Applications` from `package-app.sh`, `Signature=adhoc`, `TeamIdentifier=not
set`, designated requirement `cdhash H"…"` and nothing else.

1. **The banner works under ad-hoc signing, and the grant survives a reinstall.**
   The whole chain was exercised on the running app:
   - The authorization prompt **does** appear when the mode is picked, and can be
     granted.
   - Afterwards `notificationSettings()` reports `authorizationStatus =
     .authorized (2)`, `alertSetting = .enabled (2)`, `alertStyle = .banner (1)`,
     `notificationCenterSetting = .enabled (2)`, `lockScreenSetting = .enabled
     (2)`, and the port answers `authorized`.
   - A banner **does** arrive on the next firing, on the display carrying the
     menu bar, titled and bodied in the app's language.
   - Helm appears in **System Settings → Notifications** under its own name and
     its own icon, with a working Allow switch.
   - **The grant survives a reinstall.** Three installs with three different
     cdhashes (`20dcecb2…`, `dd1f9989…`, `dd74f39f…`), each a `rm -rf
     /Applications/Helm.app` followed by a fresh `ditto`, and every one of them
     read back `.authorized` with no new prompt. Notification authorization is
     keyed by **bundle identifier**, not by the designated requirement — which is
     the opposite of what § Permissions describes for Full Disk Access, and the
     contrast was measured in the same reinstall: FDA went from `granted` to
     `denied`, Accessibility with it, and the keychain items Autopilot and the
     VPN credential cache own went back to prompting for the login password.
     So the note § Permissions makes is right about TCC and the keychain and
     does **not** extend to notifications.
   - Revoking in System Settings gives `authorizationStatus = .denied (1)` while
     `alertSetting` still reads `.enabled (2)` — which is why the port must key
     off `authorizationStatus` alone, as it does.
   - The refusal path was exercised end to end: with the permission revoked, the
     settings row says macOS refuses banners and that the name will be shown in
     the menu bar instead, and the next firing does put the name in the menu bar.
     **A revocation used to be heard only when the VPN settings page next
     appeared** — a firing before that visit produced the spin and nothing else,
     because the stored `bannerAuthorized` still said yes; measured, the ring
     turned for 1.1 s and no name was drawn. **Fixed:** the firing asks.
     `AutomationNotice.announce` now reads `authorizationState()` on its way to
     the banner and returns what it heard; `VPNViewModel` publishes that, and
     `effective(bannerAuthorized:)` is judged against it rather than against the
     mirror. The read prompts nobody, so it is affordable at every firing, and
     only `.system` asks — the answer cannot change what the other two modes do.
     The mirror stays as what the settings page displays. Guarded by
     `testEveryModeThatSpeaksAtAllSpeaksExactlyOnce`, which now runs every mode
     against every answer macOS can give with the mirror deliberately holding
     the opposite, and by
     `testARevokedPermissionIsNoticedWhenTheRuleFiresAndNotAtTheNextSettingsVisit`.
2. **The 30 Hz redraw costs nothing after the first spin.** Ten firings six
   seconds apart: footprint 17 MB before the first, 18 MB from the second, and
   18 MB unchanged through the tenth. The 1 MB is the one-time build of the
   36-frame cache; the frames are hit on every spin after it.
3. **Borrowing the status item works, and lasts as long as it should.** With no
   other module tinting, the ring swept 720° ± 6% inside the 1.2 s window (two
   revolutions, measured at 557–607°/s across two recordings) and the name stood
   beside it for 2.97 s of the 3.0 s window; the missing frames at each end are
   the engine→UI hop, one frame of paint delay.
4. **A countdown did not suppress the spin, and the rule that said it did was
   inert. Fixed 2026-07-29.** `StatusPlan.spins` reads `timerProgress` off the
   *chosen* appearance, and `StatusPlan.choose` gave a live spin the icon before
   it looked at anything else — so the appearance it inspected was VPN's, which
   never carries a countdown. No descriptor produces one appearance holding both
   fields, which is the only shape the rule could fire on, and the test that
   guarded it (`testACountdownSuppressesTheSpin`) constructed exactly that shape
   by hand. Measured on screen with a Keep Awake timed session running: the red
   ring and the remaining time were **replaced** for 1.2 s by a spinning grey
   ring and the connection's name, at 585°/s, and the countdown then came back —
   which is the "countdown arc that jumped backwards" this rule exists to
   prevent.

   The fix is a tier: a live `timerProgress` now outranks a live spin in
   `choose`, so the appearance handed to `spins` really is the counting one and
   the existing guard answers for the right reason. The test is built from two
   appearances, the way the app is
   (`testACountdownOutranksASpinForTheIcon`,
   `testTheChosenAppearanceOfACountdownDoesNotSpin`); the hand-built single
   appearance is kept as one assertion among several rather than as the whole
   coverage, because `spins` is public and the two fields are independent.
5. **While another module owns the icon, the menu bar does not announce a firing
   at all.** Not a limitation to work around — the consequence of there being
   one status item and one title slot, now that a countdown outranks a spin
   (Risk 4). With a Keep Awake countdown running, a firing produces no spin and
   no name: the slot holds "14:22" and it is the more important of the two.
   Asserted in `testWhileACountdownOwnsTheIconAFiringIsNotNamed`. With a module
   that tints but does not count down, the spin plays in full and the name is
   dropped the moment it ends — measured at 1.05 s of a 3.0 s window before the
   countdown tier existed, and unchanged by it. The person who wants to be told
   whatever else the menu bar is doing has the banner; that is what the mode is
   for. The picker's hint — "The menu-bar ring turns either way." — is a
   statement about the three modes and stays true of them, but it is the one
   place in the app that could be read as promising a ring a countdown will not
   give. Left alone deliberately: it is not wrong about the choice it sits
   under, and rewriting it costs eight languages and a screenshot pass.
