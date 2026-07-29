# VPN Spin as a Choice, with a Colour — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The menu-bar spin that announces a VPN rule firing becomes a setting, off by default, and carries a colour chosen per firing kind.

**Architecture:** The spin's colour is a **new field** on `StatusAppearance`, deliberately not `tintToken` — that field is what `StatusPlan.choose` reads to decide who owns the menu bar between moments, and a module wanting one coloured second must not thereby own the icon all day. The palette control moves from Keep Awake into `HelmUI` so both modules use one.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest.

**Spec:** `docs/superpowers/specs/2026-07-29-0.8.0-features-design.md` § 2.

**This reverses a decision.** `docs/superpowers/specs/2026-07-29-vpn-automation-feedback-design.md` says the animation always plays. It is overruled on the grounds that movement in the menu bar is a person's to switch off. The old spec carries a note pointing here.

---

## File structure

| File | Change |
|---|---|
| `Sources/HelmContract/StatusAppearance.swift` | Gains `spinTintToken`. |
| `Sources/HelmContract/StatusPlan.swift` | `redrawKey` gains the spin tint. |
| `Sources/HelmApp/StatusItemController.swift` | Passes the spin tint to `RingIcon.spinnerFrames`. |
| `Sources/HelmUI/DesignSystem/PaletteSwatches.swift` | **New.** The grid of colour swatches, moved out of Keep Awake. |
| `Sources/Modules/KeepAwake/UI/KeepAwakeSettingsPage.swift` | Calls the shared grid; its private copy goes. |
| `Sources/Modules/VPN/Engine/VPNSettings.swift` | Three new keys. |
| `Sources/Modules/VPN/UI/VPNDescriptor.swift` | Honours the toggle; sets the spin tint from the kind. |
| `Sources/Modules/VPN/UI/VPNSettingsPage.swift` | The toggle, the two swatch grids, the note. |
| `Sources/Modules/VPN/UI/VPNStrings.swift` | New strings, eight languages. |

---

### Task 1: `StatusAppearance` gains a spin tint

**Files:**
- Modify: `Sources/HelmContract/StatusAppearance.swift`
- Test: `Tests/HelmContractTests/StatusPlanTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Append to `Tests/HelmContractTests/StatusPlanTests.swift`:

```swift
    /// The whole point of the separate field. `tintToken` is a claim on the
    /// menu bar between moments; a module that only wants its own second of
    /// animation coloured must not become the module that owns the icon.
    func testASpinTintIsNotAClaimOnTheIcon() {
        let now = Date()
        let spinner = StatusAppearance(spinUntil: now.addingTimeInterval(1),
                                       spinTintToken: "green")
        let tinter = StatusAppearance(tintToken: "orange")

        // While the spin runs it wins on its own tier, as before.
        XCTAssertEqual(StatusPlan.choose([spinner, tinter], now: now), spinner)

        // Once it is over, the module that actually tints takes the icon back —
        // the spinner's colour must not have registered as a tint.
        let after = now.addingTimeInterval(5)
        XCTAssertEqual(StatusPlan.choose([spinner, tinter], now: after), tinter)
    }

    func testASpinTintAloneNeverWinsTheTintTier() {
        let now = Date()
        // Spin already finished, so only the fallback tiers can answer.
        let spent = StatusAppearance(spinUntil: now.addingTimeInterval(-1),
                                     spinTintToken: "green")
        XCTAssertEqual(StatusPlan.choose([spent], now: now), .inactive,
                       "a spent spin with a colour is not a module with a tint")
    }

    func testTheRedrawKeyNoticesTheSpinTint() {
        let green = StatusPlan.redrawKey(style: "ring", size: "medium", tint: nil,
                                         progress: nil, title: nil, frame: 3,
                                         spinTint: "green")
        let orange = StatusPlan.redrawKey(style: "ring", size: "medium", tint: nil,
                                          progress: nil, title: nil, frame: 3,
                                          spinTint: "orange")
        XCTAssertNotEqual(green, orange,
                          "the same frame in two colours must not report 'nothing changed'")
    }
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter StatusPlanTests`
Expected: FAIL — no `spinTintToken` argument, and `redrawKey` has no `spinTint:`.

- [ ] **Step 3: Add the field**

In `Sources/HelmContract/StatusAppearance.swift`, after the `spinUntil` property and before `init`:

```swift
    /// The colour of the spin, which is not a claim on the icon.
    ///
    /// Deliberately not `tintToken`: that field is what `StatusPlan.choose`
    /// reads to decide who owns the menu bar *between* moments, and a module
    /// that only wants its own second of animation coloured must not thereby
    /// become the module that owns the icon all day. `VPNDescriptor` records
    /// "no tint, ever" for the same reason and that decision still stands.
    public var spinTintToken: String?
```

Then extend the initializer — every existing caller passes arguments by name, so a new defaulted parameter at the end is source-compatible:

```swift
    public init(tintToken: String? = nil, iconStyle: String? = nil,
                timerProgress: Double? = nil, title: String? = nil,
                spinUntil: Date? = nil, spinTintToken: String? = nil) {
        self.tintToken = tintToken
        self.iconStyle = iconStyle
        self.timerProgress = timerProgress
        self.title = title
        self.spinUntil = spinUntil
        self.spinTintToken = spinTintToken
    }
```

- [ ] **Step 4: Extend `redrawKey`**

In `Sources/HelmContract/StatusPlan.swift`, replace the `redrawKey` function with:

```swift
    public static func redrawKey(style: String, size: String, tint: String?,
                                 progress: Double?, title: String?, frame: Int?,
                                 spinTint: String?) -> String {
        let part = { (value: String?) in value.map { "=" + $0 } ?? "-" }
        let bucket = progress.map { "=\(Int(($0 * 100).rounded()))" } ?? "-"
        return [style, size, part(tint), bucket, part(title),
                frame.map { "=\($0)" } ?? "-", part(spinTint)].joined(separator: "|")
    }
```

The frame index already changes every tick, so today the colour could be left out and nothing would break. It is included because a key that omits an input is a key that will be wrong the first time somebody caches more aggressively.

- [ ] **Step 5: Run the tests**

Run: `swift test --filter StatusPlanTests`
Expected: FAIL, but now only at the one call site in `StatusItemController` — a missing argument, not a logic failure. Fix it in Task 2 and this goes green.

If `StatusPlanTests` itself still fails on logic, stop: `choose` was changed by accident. It must not be.

- [ ] **Step 6: Commit after Task 2**

This task does not compile the app on its own. Commit at the end of Task 2.

---

### Task 2: The host draws the spin in that colour

**Files:**
- Modify: `Sources/HelmApp/StatusItemController.swift` (in `refreshIcon`)

- [ ] **Step 1: Update the call sites**

In `refreshIcon()`, replace the `key` computation and the image assignment:

```swift
        let title = appearance.title
        // The spin's own colour when it has one, and the module's tint
        // otherwise — which is what Keep Awake has always drawn with.
        let spinTint = appearance.spinTintToken ?? token
        let key = StatusPlan.redrawKey(style: style.rawValue, size: size.rawValue, tint: token,
                                       progress: progress, title: title, frame: frame,
                                       spinTint: frame != nil ? spinTint : nil)
        guard key != lastIconKey else { return }
        lastIconKey = key
        if let frame {
            button.image = RingIcon.spinnerFrames(style: style, size: size,
                                                  tintToken: spinTint)[frame]
        } else {
            button.image = RingIcon.make(style: style, size: size, tintToken: token, progress: progress)
        }
```

`spinTint` is passed into the key as `nil` when nothing is spinning, so a still icon's key does not change just because some module carries a spin colour it is not using.

- [ ] **Step 2: Build and run the suite**

Run: `swift build && swift test`
Expected: builds clean; 1575 + 3 new tests, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add Sources/HelmContract/StatusAppearance.swift Sources/HelmContract/StatusPlan.swift \
        Sources/HelmApp/StatusItemController.swift Tests/HelmContractTests/StatusPlanTests.swift
git commit -m "feat(menu bar): a spin can carry a colour without claiming the icon

The colour is a field of its own rather than \`tintToken\`, which is what
\`StatusPlan.choose\` reads to decide who owns the menu bar between moments.
A module wanting one coloured second must not become the module that owns
the icon all day.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: The swatch grid moves to `HelmUI`

**Files:**
- Create: `Sources/HelmUI/DesignSystem/PaletteSwatches.swift`
- Modify: `Sources/Modules/KeepAwake/UI/KeepAwakeSettingsPage.swift` (delete `swatchGrid`, call the shared one)

- [ ] **Step 1: Create the shared component**

Create `Sources/HelmUI/DesignSystem/PaletteSwatches.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// The ten palette colours as a grid of swatches. One of these, no local
/// variants: it was a private method inside `KeepAwakeSettingsPage` until VPN
/// needed the same control, and CLAUDE.md's list of things written twice
/// before they moved exists to stop the second copy.
///
/// **Buttons, not tap gestures.** A view whose only interaction is
/// `onTapGesture` never enters the key-view loop, so with Full Keyboard Access
/// on, Tab skipped every swatch and the colour could not be chosen without a
/// mouse — VoiceOver worked, which is what hid it. Ten `KeyViewProxy` views
/// appear under the hosting view for the button form and none for the gesture
/// form; `.buttonStyle(.plain)` leaves the drawing exactly as it was.
public struct HelmPaletteSwatches: View {
    private let selection: String
    private let pick: (String) -> Void

    public init(selection: String, pick: @escaping (String) -> Void) {
        self.selection = selection
        self.pick = pick
    }

    public var body: some View {
        // 5 columns × 2 rows for the 10 palette colours.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 24, maximum: 44)), count: 5),
                  spacing: 12) {
            ForEach(PaletteColor.allCases, id: \.rawValue) { palette in
                let selected = selection == palette.rawValue
                Button { pick(palette.rawValue) } label: {
                    Circle()
                        .fill(palette.color)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                        .overlay {
                            if selected {
                                // Dark on the three light swatches, white on
                                // the rest — a white check on yellow is not a
                                // check anyone can see.
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette == .white || palette == .yellow
                                                     || palette == .mint ? .black : .white)
                            }
                        }
                        .overlay {
                            if selected {
                                Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(palette.label)
                // The button carries its own trait and its own action; only
                // "which one is chosen" has to be said here.
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityLabel(palette.label)
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Point Keep Awake at it**

In `Sources/Modules/KeepAwake/UI/KeepAwakeSettingsPage.swift`, delete the whole private `swatchGrid(selection:pick:)` method — the doc comment moved with it to the new file — and change its two callers:

```swift
    private var colorSwatches: some View {
        HelmPaletteSwatches(selection: activeTintColor) { token in
            activeTintColor = token
            write(token, MenuBarLook.Key.activeTint)
        }
    }

    /// Timer palette: the countdown can stand out from the active colour.
    private var timerColorSwatches: some View {
        // No stored value yet → the active colour is what the timer will use,
        // so show that as the selection.
        HelmPaletteSwatches(selection: timerTintColor.isEmpty ? activeTintColor : timerTintColor) { token in
            timerTintColor = token
            write(token, MenuBarLook.Key.timerTint)
        }
    }
```

- [ ] **Step 3: Build and run the keyboard guard**

Run: `swift build && swift test --filter KeyboardReachableControlsTests`
Expected: builds clean; PASS. That guard is the one that would notice if the move turned the buttons back into gestures.

- [ ] **Step 4: Run the whole suite**

Run: `swift test`
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/HelmUI/DesignSystem/PaletteSwatches.swift \
        Sources/Modules/KeepAwake/UI/KeepAwakeSettingsPage.swift
git commit -m "refactor(ui): one swatch grid, in the design system

VPN needs the palette Keep Awake has, and a second copy is what the shared
list in CLAUDE.md exists to prevent. The two facts its comment carries — the
swatches are Buttons because a tap gesture never joins the key-view loop, and
the check is drawn dark on the light swatches — moved with it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: The three settings

**Files:**
- Modify: `Sources/Modules/VPN/Engine/VPNSettings.swift`
- Test: `Tests/Modules/VPN/EngineTests/VPNSpinSettingsTests.swift` (create)

- [ ] **Step1: Write the failing test**

Create `Tests/Modules/VPN/EngineTests/VPNSpinSettingsTests.swift`:

```swift
import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// Defaults matter here: the spin is off unless somebody asked for it, and the
/// two colours have to answer before anybody has picked one.
final class VPNSpinSettingsTests: XCTestCase {
    private func settings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn-test",
                                           backing: InMemoryKeyValueStore()))
    }

    func testTheSpinIsOffUntilItIsAskedFor() {
        XCTAssertFalse(settings().automationSpin)
    }

    func testTheSpinCanBeSwitchedOn() {
        let s = settings()
        s.setAutomationSpin(true)
        XCTAssertTrue(s.automationSpin)
    }

    func testTheTwoColoursHaveDefaultsBeforeAnybodyPicks() {
        XCTAssertEqual(settings().spinTint(for: .connected), "green")
        XCTAssertEqual(settings().spinTint(for: .disconnected), "orange")
    }

    func testEachKindKeepsItsOwnColour() {
        let s = settings()
        s.setSpinTint("purple", for: .connected)
        XCTAssertEqual(s.spinTint(for: .connected), "purple")
        XCTAssertEqual(s.spinTint(for: .disconnected), "orange",
                       "setting one colour must not move the other")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter VPNSpinSettingsTests`
Expected: FAIL — `value of type 'VPNSettings' has no member 'automationSpin'`.

- [ ] **Step 3: Add the keys**

In `Sources/Modules/VPN/Engine/VPNSettings.swift`, after the `setNotice` method:

```swift
    /// Whether the menu-bar ring turns when a rule fires.
    ///
    /// Off by default, which reverses what the automation-feedback spec
    /// decided: it argued the movement is feedback rather than a notification
    /// and should always play. Sound, and overruled — movement in the menu bar
    /// is a person's to switch off. The cost is exact and is stated under the
    /// switch: with this off *and* the notice set to nothing, a rule fires with
    /// no sign at all.
    public var automationSpin: Bool { store.bool("automationSpin", default: false) }
    public func setAutomationSpin(_ on: Bool) { store.set(on, for: "automationSpin") }

    /// The colour the ring turns in, per kind of firing. A tunnel going up and
    /// a tunnel going down are the two things worth telling apart at a glance,
    /// and `VPNAutomation.Kind` already distinguishes them.
    public func spinTint(for kind: VPNAutomation.Kind) -> String {
        store.string(Self.spinTintKey(kind), default: kind == .connected ? "green" : "orange")
    }
    public func setSpinTint(_ token: String, for kind: VPNAutomation.Kind) {
        store.set(token, for: Self.spinTintKey(kind))
    }
    private static func spinTintKey(_ kind: VPNAutomation.Kind) -> String {
        "spinTint.\(kind.rawValue)"
    }
```

- [ ] **Step 4: Run it and watch it pass**

Run: `swift test --filter VPNSpinSettingsTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modules/VPN/Engine/VPNSettings.swift \
        Tests/Modules/VPN/EngineTests/VPNSpinSettingsTests.swift
git commit -m "feat(vpn): the spin is a setting, and each kind of firing has a colour

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: The view model answers for the spin, and the descriptor asks it

**Files:**
- Modify: `Sources/Modules/VPN/UI/VPNViewModel.swift` (the settings seam, `setForTesting`)
- Modify: `Sources/Modules/VPN/UI/VPNDescriptor.swift` (`statusAppearance`)
- Modify: `Tests/Modules/VPN/UITests/VPNStatusAppearanceTests.swift` (three existing tests, then four new)

**Read this before writing anything.** `VPNDescriptor()` is constructed in the tests with **no store**, so `settingsStore` falls back to real `UserDefaults` — a descriptor that reads `VPNSettings` directly cannot be tested. The view model is already the seam for exactly this: `notice` reads `noticeForTesting ?? settings?.notice ?? .menuBar`, and the descriptor asks `model.effectiveNotice` rather than building settings itself. The spin follows that shape precisely. Do not add a store parameter to the descriptor.

**Three existing tests will fail, and should.** `VPNStatusAppearanceTests` lines 37, 48 and 96 assert that a firing spins the ring. They encode the decision this work reverses. They are not deleted — they are given `spin: true`, because what they were really pinning (the window matches `VPNAutomation.spinEnd`, the silent mode still spins, the third case at line 96) is still true when the spin is switched on.

- [ ] **Step 1: Add the seam to the view model**

In `Sources/Modules/VPN/UI/VPNViewModel.swift`, beside `private var noticeForTesting: VPNNotice?`:

```swift
    private var spinForTesting: Bool?
    private var spinTintsForTesting: [VPNAutomation.Kind: String]?
```

And beside the `notice` computed property, in the same shape:

```swift
    /// Whether the menu-bar ring turns when a rule fires. Read at every ask
    /// rather than cached, like `notice`, so a change in Settings applies to
    /// the next firing instead of to the next launch.
    public var automationSpin: Bool {
        spinForTesting ?? settings?.automationSpin ?? false
    }

    /// The colour that firing turns in.
    public func spinTint(for kind: VPNAutomation.Kind) -> String {
        spinTintsForTesting?[kind]
            ?? settings?.spinTint(for: kind)
            ?? (kind == .connected ? "green" : "orange")
    }
```

Then extend `setForTesting` — new parameters at the end with defaults, so no existing call site changes:

```swift
    func setForTesting(automation: VPNAutomation?, notice: VPNNotice,
                       bannerAuthorized: Bool = false,
                       notices: AutomationNoticePort? = nil,
                       spin: Bool = false,
                       spinTints: [VPNAutomation.Kind: String]? = nil) {
        noticeForTesting = notice
        bannerAuthorizedForTesting = bannerAuthorized
        spinForTesting = spin
        spinTintsForTesting = spinTints
        if let notices { self.notices = notices }
        if let automation { adopt(automation) } else { lastAutomation = nil }
    }
```

The default is `spin: false`, which is what makes the three existing tests fail in Step 3 rather than passing by accident.

- [ ] **Step 2: Extend the test fixture**

In `Tests/Modules/VPN/UITests/VPNStatusAppearanceTests.swift`, replace the `descriptor` helper with one that can ask for a spin. Everything else about it stays:

```swift
    private func descriptor(firing: VPNAutomation?, notice: VPNNotice,
                            bannerAuthorized: Bool = false,
                            spin: Bool = false,
                            spinTints: [VPNAutomation.Kind: String]? = nil)
                            -> (VPNDescriptor, ModuleViewModel) {
        let descriptor = VPNDescriptor()
        let host = ModuleViewModel(transport: LocalTransport())
        descriptor.viewModel(host).setForTesting(automation: firing, notice: notice,
                                                 bannerAuthorized: bannerAuthorized,
                                                 spin: spin, spinTints: spinTints)
        return (descriptor, host)
    }
```

The existing `firing(secondsAgo:name:)` helper builds a `.connected` firing. Add its sibling:

```swift
    private func firing(secondsAgo: TimeInterval, name: String = "Office",
                        kind: VPNAutomation.Kind) -> VPNAutomation {
        VPNAutomation(at: Date().addingTimeInterval(-secondsAgo), name: name, kind: kind)
    }
```

- [ ] **Step 3: Write the new tests, and watch the old ones fail**

Append to the same file:

```swift
    /// The reversal, pinned. The automation-feedback spec had the ring turning
    /// in every mode; movement in the menu bar is a person's to switch off, and
    /// the default is off.
    func testNothingTurnsUntilSomebodyAsksForIt() {
        let (d, host) = descriptor(firing: firing(secondsAgo: 0), notice: .menuBar)
        let appearance = d.statusAppearance(host)
        XCTAssertNil(appearance.spinUntil, "the ring must not turn when nobody asked")
        XCTAssertEqual(appearance.title, "Office", "the name is a separate setting and still applies")
    }

    func testEachKindTurnsInItsOwnColour() {
        let tints: [VPNAutomation.Kind: String] = [.connected: "purple", .disconnected: "pink"]
        let (up, upHost) = descriptor(firing: firing(secondsAgo: 0, kind: .connected),
                                      notice: .menuBar, spin: true, spinTints: tints)
        XCTAssertEqual(up.statusAppearance(upHost).spinTintToken, "purple")

        let (down, downHost) = descriptor(firing: firing(secondsAgo: 0, kind: .disconnected),
                                          notice: .menuBar, spin: true, spinTints: tints)
        XCTAssertEqual(down.statusAppearance(downHost).spinTintToken, "pink")
    }

    func testTheDefaultColoursDifferByKind() {
        let (up, upHost) = descriptor(firing: firing(secondsAgo: 0, kind: .connected),
                                      notice: .menuBar, spin: true)
        let (down, downHost) = descriptor(firing: firing(secondsAgo: 0, kind: .disconnected),
                                          notice: .menuBar, spin: true)
        XCTAssertEqual(up.statusAppearance(upHost).spinTintToken, "green")
        XCTAssertEqual(down.statusAppearance(downHost).spinTintToken, "orange")
    }

    /// The decision this module wrote down three days ago, which the colour
    /// work must not quietly spend: a tint is a claim on the icon between
    /// moments, and this module makes none.
    func testTheModuleStillNeverTints() {
        let (d, host) = descriptor(firing: firing(secondsAgo: 0), notice: .menuBar, spin: true)
        XCTAssertNil(d.statusAppearance(host).tintToken,
                     "no tint, ever — the spin colour is a different field")
    }

    /// A spin that is over carries no colour either, so a spent appearance
    /// cannot be mistaken for a live one further up.
    func testASpentSpinCarriesNoColour() {
        let (d, host) = descriptor(firing: firing(secondsAgo: 60), notice: .menuBar, spin: true)
        let appearance = d.statusAppearance(host)
        XCTAssertNil(appearance.spinUntil)
        XCTAssertNil(appearance.spinTintToken)
    }
```

Run: `swift test --filter VPNStatusAppearanceTests`
Expected: FAIL. Two distinct failures, and both are wanted:
- the four new tests fail — `statusAppearance` does not read the setting yet;
- `testFreshFiringSpinsTheRingAndNamesTheConnection`, `testSilentModeStillSpinsButNamesNothing` and the test at line 96 fail once Step 4 lands, because their default is now `spin: false`.

- [ ] **Step 4: Honour the setting in the descriptor**

In `Sources/Modules/VPN/UI/VPNDescriptor.swift`, replace the body of `statusAppearance` after the `guard let firing` line:

```swift
        // One reading of the clock, so the two windows cannot disagree about
        // which moment they are answering for.
        let now = Date()
        // The setting decides whether there is movement at all. Reduce Motion
        // is a separate question, answered a level up in `StatusPlan.spins`:
        // this is a preference, that is an instruction from the system.
        let spinning = model.automationSpin
            && VPNAutomation.spinPhase(firing, now: now) != nil
        let names = model.effectiveNotice.showsMenuBarName
            && VPNAutomation.showsName(firing, now: now)
        return StatusAppearance(title: names ? firing.name : nil,
                                spinUntil: spinning ? VPNAutomation.spinEnd(firing) : nil,
                                spinTintToken: spinning ? model.spinTint(for: firing.kind) : nil)
```

Asked of `model`, never of `VPNSettings` directly — the descriptor is built with no store in every test, so a direct read would reach real `UserDefaults`.

Extend the "No tint, ever" doc comment above the method with one line, leaving the rest exactly as it is:

```swift
    /// The spin's colour is `spinTintToken`, which `StatusPlan.choose` does not
    /// read — so colouring the animation does not make this a tinting module.
```

- [ ] **Step 5: Update the three tests that encode the old default**

In `Tests/Modules/VPN/UITests/VPNStatusAppearanceTests.swift`, add `spin: true` to the `descriptor(...)` call in each of the three tests that assert `spinUntil` is non-nil, and correct the doc comment on `testSilentModeStillSpinsButNamesNothing`, which currently states the reversed rule:

```swift
    /// The movement is feedback that the app did something rather than a
    /// notification, so the quietest *notice* mode still gets it — the notice
    /// setting decides the fate of the name only. Whether there is movement at
    /// all is now its own switch, which this test turns on.
    func testSilentModeStillSpinsButNamesNothing() {
        let fired = firing(secondsAgo: 0)
        let (d, host) = descriptor(firing: fired, notice: .silent, spin: true)
        let appearance = d.statusAppearance(host)
        XCTAssertEqual(appearance.spinUntil, VPNAutomation.spinEnd(fired))
        XCTAssertNil(appearance.title)
    }
```

- [ ] **Step 6: Run it and watch it pass**

Run: `swift test --filter VPNStatusAppearanceTests`
Expected: PASS, every test in the file.

- [ ] **Step 7: Run the whole suite**

Run: `swift test`
Expected: 0 failures. If `VPNAutomationAnnouncementTests` or `VPNBannerWordsTests` fail, they are calling `setForTesting` and taking the new default — give them `spin: true` where they assert on movement, and leave them alone where they do not.

- [ ] **Step 8: Commit**

```bash
git add Sources/Modules/VPN/UI/VPNViewModel.swift Sources/Modules/VPN/UI/VPNDescriptor.swift \
        Tests/Modules/VPN/UITests/VPNStatusAppearanceTests.swift
git commit -m "feat(vpn): the ring turns only if asked, in the colour of what happened

Asked of the view model, not of VPNSettings: the descriptor is built with no
store everywhere it is tested, so a direct read would reach real UserDefaults.
The seam is the one \`notice\` already uses.

Three tests asserting that a firing spins were pinning the reversed decision.
They keep what they were really about and now switch the spin on themselves.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: The settings on screen

**Files:**
- Modify: `Sources/Modules/VPN/UI/VPNStrings.swift`
- Modify: `Sources/Modules/VPN/UI/VPNSettingsPage.swift`

- [ ] **Step 1: Add the strings**

In `Sources/Modules/VPN/UI/VPNStrings.swift`, beside the other notice strings:

```swift
    static var spinLabel: String {
        L("Turn the menu-bar icon", [.ru: "Вращать значок в строке меню", .es: "Girar el icono de la barra de menús", .fr: "Faire tourner l’icône de la barre des menus", .de: "Menüleistensymbol drehen", .ja: "メニューバーのアイコンを回す", .zh: "转动菜单栏图标", .pt: "Girar o ícone da barra de menus"])
    }
    static var spinConnected: String {
        L("When a rule connects", [.ru: "Когда правило подключает", .es: "Cuando una regla conecta", .fr: "Quand une règle connecte", .de: "Wenn eine Regel verbindet", .ja: "ルールが接続したとき", .zh: "规则连接时", .pt: "Quando uma regra conecta"])
    }
    static var spinDisconnected: String {
        L("When a tunnel goes down", [.ru: "Когда туннель разрывается", .es: "Cuando un túnel cae", .fr: "Quand un tunnel tombe", .de: "Wenn ein Tunnel abbricht", .ja: "トンネルが切れたとき", .zh: "隧道断开时", .pt: "Quando um túnel cai"])
    }
    /// The cost of the two quiet settings meeting, said where they are set.
    static var spinSilentWarning: String {
        L("With this off and the notice set to nothing, a rule that connects or drops a tunnel gives no sign at all.", [.ru: "Если это выключено, а уведомление — «ничего», правило подключит или разорвёт туннель без единого признака.", .es: "Con esto desactivado y el aviso en nada, una regla que conecta o corta un túnel no da ninguna señal.", .fr: "Avec ceci désactivé et l’avis réglé sur rien, une règle qui connecte ou coupe un tunnel ne donne aucun signe.", .de: "Ist dies aus und der Hinweis auf nichts gestellt, verbindet oder trennt eine Regel ohne jedes Zeichen.", .ja: "これをオフにし、通知も「なし」にすると、ルールが接続・切断しても何の合図も出ません。", .zh: "关闭此项且提示设为“无”时，规则连接或断开隧道将没有任何提示。", .pt: "Com isto desligado e o aviso em nada, uma regra que conecta ou derruba um túnel não dá sinal algum."])
    }
```

- [ ] **Step 2: Seed the state**

In `Sources/Modules/VPN/UI/VPNSettingsPage.swift`, add three `@State` properties beside `notice`:

```swift
    @State private var spin: Bool
    @State private var spinTintConnected: String
    @State private var spinTintDisconnected: String
```

And seed them in `init`, beside the `_notice` line — from the store, never from `vm`, for the reason the existing comment there gives:

```swift
        let settings = VPNSettings(store: store)
        _spin = State(initialValue: settings.automationSpin)
        _spinTintConnected = State(initialValue: settings.spinTint(for: .connected))
        _spinTintDisconnected = State(initialValue: settings.spinTint(for: .disconnected))
```

- [ ] **Step 3: Draw them**

In `noticePicker`, after the existing `Text(VPNStr.noticeHint)` block, add:

```swift
        Toggle(VPNStr.spinLabel, isOn: Binding(
            get: { spin },
            set: { on in
                spin = on
                VPNSettings(store: store).setAutomationSpin(on)
            }))

        if spin {
            LabeledContent(VPNStr.spinConnected) {
                HelmPaletteSwatches(selection: spinTintConnected) { token in
                    spinTintConnected = token
                    VPNSettings(store: store).setSpinTint(token, for: .connected)
                }
            }
            LabeledContent(VPNStr.spinDisconnected) {
                HelmPaletteSwatches(selection: spinTintDisconnected) { token in
                    spinTintDisconnected = token
                    VPNSettings(store: store).setSpinTint(token, for: .disconnected)
                }
            }
        }

        // Said where the two settings are, not only in a spec file.
        if !spin, notice == .silent {
            Text(VPNStr.spinSilentWarning)
                .font(.caption)
                .foregroundStyle(HelmSignal.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
```

The swatches appear and disappear with the toggle. Per ARCHITECTURE.md § Motion, reveals grow — the enclosing `Form` section animates on `spin` through `HelmMotion.interface`, which the page's existing `.animation` modifiers already supply for this section; if it does not, add `.animation(HelmMotion.interface, value: spin)` to the section rather than an inline curve.

- [ ] **Step 4: Run the guards**

Run: `swift test --filter NamedControlsTests && swift test --filter KeyboardReachableControlsTests`
Expected: PASS both. Every control above carries a label.

- [ ] **Step 5: Run the whole suite and build**

Run: `swift build && swift test`
Expected: builds clean, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/Modules/VPN/UI/VPNStrings.swift Sources/Modules/VPN/UI/VPNSettingsPage.swift
git commit -m "feat(vpn): the spin switch and its two colours, in eight languages

The one combination that produces silence — spin off, notice nothing — says
so where the two settings are, rather than leaving the person to discover it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Measure it in the menu bar

**Files:** none changed if it passes.

"It looks right" is not a claim about this. ARCHITECTURE.md § Dev loop: ragged, abrupt and too fast are claims about frames, so measure frames.

- [ ] **Step 1: Install the signed build**

```bash
pkill -f 'MacOS/HelmApp'; bash Scripts/package-app.sh
rm -rf /Applications/Helm.app
ditto "$TMPDIR/helm-package/Helm.app" /Applications/Helm.app
codesign --verify --deep --strict /Applications/Helm.app
xattr -dr com.apple.quarantine /Applications/Helm.app && open /Applications/Helm.app
```

- [ ] **Step 2: Default is off**

With a VPN rule configured, trigger a firing (launch the app the rule watches). Expected: **nothing turns**. The name still appears beside the icon, because the notice mode's default is unchanged.

- [ ] **Step 3: Switch it on and check both colours**

Settings → VPN → turn the switch on, leave the colours at green and orange. Fire the rule by launching the watched app: the ring turns green. Quit the app so the rule drops the tunnel: the ring turns orange.

- [ ] **Step 4: The countdown still wins**

Start a Keep Awake timer, then fire a VPN rule while it counts. Expected: the countdown keeps the icon; nothing turns and no name appears. This is `StatusPlan.choose`'s first tier and it is the case a regression would hide in.

- [ ] **Step 5: Reduce Motion**

System Settings → Accessibility → Display → Reduce Motion on. Fire a rule. Expected: no movement, the name still appears — the setting is a preference, Reduce Motion is an instruction, and the instruction wins.

- [ ] **Step 6: Measure the memory of a second colour**

The frame cache is keyed by style, size, tint and appearance, so two colours mean two sets of 36 frames. The claim on record is ~1 MB for the first firing and nothing after.

```bash
grep "\[memory\]" ~/Library/Logs/Helm/helm.log | tail -20
```

Fire ten times in each colour. Expected: a step of about 1 MB per colour on its first firing, flat after. A figure that keeps climbing means the cache key is wrong and the frames are being rebuilt.

- [ ] **Step 7: Check the harness rule**

Run: `grep -r HELM_DEBUG Sources/`
Expected: no output.

- [ ] **Step 8: Record it**

Add to `CHANGELOG.md` under `## [Unreleased] — 0.8.0` — including that this reverses the "always plays" decision, since the previous entry in the same section says the ring turns — and to `Sources/HelmApp/ChangelogData.swift`.

```bash
git add CHANGELOG.md Sources/HelmApp/ChangelogData.swift
git commit -m "docs: the spin became a choice, in both changelogs

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
