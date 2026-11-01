import SwiftUI
import HelmRuntime
import HelmUI
import Module_KeepAwake_Engine

/// Compact tile shown in the shared Helm panel.
struct KeepAwakePanelTile: View {
    @ObservedObject private var vm: KeepAwakeViewModel
    private let store: NamespacedStore

    @State private var customMinutes: Int
    @State private var showMore = false
    /// Natural height of the ⋯ block, measured so the disclosure can animate
    /// between 0 and a concrete value. `nil` until the first one lands.
    @State private var moreHeight: CGFloat?
    /// Same measurement for the suppression row, which grows and shrinks on the
    /// engine's say-so rather than on a press.
    @State private var suppressedHeight: CGFloat?
    /// What is *drawn*, as against what the engine says. Both rows below read
    /// these and neither reads `vm` directly.
    ///
    /// `.animation(_:value:)` carries a property of a view that stays; it
    /// carries neither a transition nor a layout change. Measured in
    /// `KeepAwakeHero`, whose comment has the table: the swap under
    /// `.animation(_:value:)` is **one** distinct frame, the same swap written
    /// inside `withAnimation` is eleven, so both animations in this file are
    /// written inside `withAnimation`.
    ///
    /// Seeded from the engine rather than from a constant: the first value is
    /// not a change, and a panel opened while a timer is already running must
    /// show the countdown rather than play the presets swapping into it.
    @State private var shownActive: Bool
    @State private var shownSuppressed: Bool
    /// The floor the guard stopped at, for the sentence. Seeded from the store
    /// like the rest: the settings page can change it while the panel is open.
    @State private var batteryFloor: Int
    @State private var showCustomTime = false
    /// What the popover is holding while it is open. Separate from
    /// `customMinutes`, which is the value that has been *saved*: a popover
    /// dismissed without confirming must leave the stored duration alone.
    @State private var editedMinutes = 0
    @State private var autoExternalDisplay: Bool
    @State private var autoPower: Bool

    init(vm: KeepAwakeViewModel, store: NamespacedStore) {
        self.vm = vm
        self.store = store
        let settings = KeepAwakeSettings(store: store)
        _autoExternalDisplay = State(initialValue: settings.autoExternalDisplay)
        _autoPower = State(initialValue: settings.autoPower)
        _customMinutes = State(initialValue: Self.openingMinutes(store))
        _shownActive = State(initialValue: vm.isActive)
        _shownSuppressed = State(initialValue: vm.suppressed || vm.batteryStopped)
        _batteryFloor = State(initialValue: settings.batteryGuardPercent)
    }

    var body: some View {
        // spacing 0 + explicit padding: a stack spacing would still insert its
        // gap before the collapsed (zero-height) disclosure, leaving a stray
        // strip under the presets.
        VStack(alignment: .leading, spacing: 0) {
            header
            // The swap the tile is for. The rows are different view types, so
            // there is nothing to interpolate — a cross-fade on one clock is
            // the honest answer, written inside `withAnimation` because the
            // modifier carries nothing for a swap (see `shownActive`).
            Group {
                if shownActive, let end = vm.endDate {
                    countdownRow(end).transition(.opacity)
                } else {
                    presetRow.transition(.opacity)
                }
            }
            .padding(.top, HelmSpace.s4)
            // Above the ⋯ block, never inside it. The whole point of this row
            // is that nothing else on any screen says the rule has stopped
            // working, so putting it behind a disclosure would leave it exactly
            // as unfindable as the log line it replaces.
            //
            // The same accordion the block below uses. This is the panel — a
            // card that changes size under the pointer with no motion is the
            // defect the disclosure token was introduced to end.
            suppressedRow
                .helmAccordion(open: shownSuppressed, height: $suppressedHeight)
            // The accordion, and **available in both states**: the block is
            // mounted whether or not a session is running, so the ⋯ button
            // opens the same automation controls either way. Why there is no
            // `.opacity` is on the modifier (`HelmAccordion.swift`): a fade here
            // snaps the «Automation» heading's colour when its layer is dropped,
            // and a compositing group washes out the divider and switches.
            moreControls
                .helmAccordion(open: showMore, height: $moreHeight)
        }
        .helmPanelCard()
        // The transaction, not the modifier — see the note on `shownActive`.
        .onChange(of: vm.isActive) { _, running in
            withAnimation(HelmMotion.disclosure) { shownActive = running }
        }
        .onChange(of: hasNotice) { _, notice in
            withAnimation(HelmMotion.disclosure) { shownSuppressed = notice }
        }
        // The store isn't observable, so these mirrored values would otherwise
        // drift once the same settings are changed in the Settings window.
        .keepAwakeAutomationMirror(store, externalDisplay: $autoExternalDisplay,
                                   power: $autoPower, batteryFloor: $batteryFloor)
    }

    // MARK: - Header

    private var header: some View {
        // The shared widget header, not a fourth arrangement of a plate and a
        // name: five widgets in one panel, one heading.
        // The token, not `.orange`. The 1×1 widget draws the module's own
        // #DE7A21, and the system colour would repaint the plate in place when
        // a tile is resized between the two — the very defect
        // `HelmWidgetHeader` exists to end.
        HelmWidgetHeader(symbol: "moon.zzz.fill", tint: KeepAwakeDescriptor.tint.colour,
                         name: KAStr.moduleName,
                         subtitle: activeSubtitle, active: vm.isActive) {
            Toggle("", isOn: Binding(get: { vm.isActive }, set: { _ in vm.toggle() }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                // Orange switch = an automation rule (display/power/app) is
                // holding the session, so flipping it off may not stick.
                .tint(autoDriven ? KeepAwakeDescriptor.tint.colour : nil)
                // Live but dead while the battery guard vetoes: the engine
                // refuses the session instantly and the switch springs back, so
                // the one control in the menu bar that starts a session would be
                // a control that visibly does nothing. The notice below it is on
                // screen saying why, which is what makes disabling honest rather
                // than mute.
                .disabled(vm.batteryStopped)
                .accessibilityLabel(KAStr.moduleName)
        }
    }

    /// True while an automation condition (not just manual/timer) is active.
    private var autoDriven: Bool {
        !vm.activeConditions.isDisjoint(with: ActiveCondition.automatic)
    }

    /// Line under the title while active: the auto conditions and a lid hint,
    /// shown next to the toggle instead of at the bottom.
    private var activeSubtitle: String? {
        guard vm.isActive else { return nil }
        var parts: [String] = []
        if !vm.activeConditions.isEmpty {
            parts.append(vm.activeConditions.map(KAStr.condition).sorted().joined(separator: ", "))
        }
        // **What is true of the machine, not what is true of the lid.** «Lid
        // closed — staying awake» in a list of what is holding the Mac would be
        // wrong — the lid is not holding anything: sleep is off for the whole Mac,
        // through a rule that outlives this process, and the lid being closed is
        // merely the reason somebody asked for that. The settings row says the
        // same sentence, with the way back out of it after it.
        if vm.clamshellActive { parts.append(KAStr.sleepIsOffNow) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Presets + more

    private var presetRow: some View {
        HStack(spacing: HelmSpace.s3) {
            presetPill(KAStr.duration(15, compact: true), 15)
            presetPill(KAStr.duration(60, compact: true), 60)
            presetPill(KAStr.duration(120, compact: true), 120)
            // The glyph is the label a 320 pt row can take; the word is what
            // it means, and what the settings page's own button says. Without
            // this VoiceOver read the character.
            presetPill("∞", 0, spoken: KAStr.indefinite)
            morePill
        }
    }

    /// Every one of these asks the engine for a session, and while the battery
    /// guard vetoes, the engine refuses instantly — `releaseForBattery` is
    /// reached before anything is held. Pressing one would be silence with a
    /// banner beside it explaining a state the person has no reason to connect
    /// to the press. Disabled, not hidden: a row of pills that came and went would take
    /// the card's height with it, and the notice is the sentence.
    private func presetPill(_ label: String, _ minutes: Int,
                            spoken: String? = nil) -> some View {
        Button {
            vm.start(minutes: minutes)
        } label: {
            pillLabel(Text(label))
        }
        .buttonStyle(.plain)
        .disabled(vm.batteryStopped)
        .accessibilityLabel(spoken ?? label)
    }

    private var morePill: some View {
        Button {
            withAnimation(HelmMotion.disclosure) { showMore.toggle() }
        } label: {
            pillLabel(Image(systemName: "ellipsis"), active: showMore)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(HelmA11y.moreActions)
        // Which of the two things this button does it has just done. The block
        // below is hidden from the tree while collapsed, so without this the
        // only feedback for pressing it would be silence.
        // `HelmA11y`'s, not a second pair in this module: the panel and the
        // settings row's ⓘ answer the same question, and the shared one is read
        // out of macOS's own tables rather than translated (`HelmA11y.expanded`).
        .accessibilityValue(HelmA11y.expanded(showMore))
    }

    private func pillLabel(_ content: some View, active: Bool = false) -> some View {
        content
            .font(HelmText.rowDetail.weight(.medium))
            // A glyph-only pill (∞, ⋯) as tall as a worded one.
            .frame(maxWidth: .infinity, minHeight: 16)
            .padding(.vertical, HelmSpace.s3)
            // The open ⋯ pill: the accent at a quarter, a literal because the
            // panel has no kit fill for «pressed in».
            .background(Capsule().fill(active ? Color.accentColor.opacity(0.25) : HelmSurface.onPanelFill))
            .contentShape(Capsule())
    }

    /// Whether the slot under the presets has anything in it at all. Either
    /// notice fills the same slot, so this is «there is something to say» rather
    /// than «a rule is paused»: the battery guard sets no `suppressed` of its own,
    /// and gating on that one would leave its banner collapsed to nothing. The
    /// hero keeps the same pair.
    private var hasNotice: Bool { vm.suppressed || vm.batteryStopped }

    /// A rule applies, and the Mac is asleep anyway.
    ///
    /// Stopping a session while a rule still holds silences that rule until it
    /// fires again — and a timer that ends automation does the same when it
    /// runs out. Both are correct and neither is visible: the switch reads off,
    /// the rule reads on, and the Mac sleeps with the app that should be
    /// holding it still on screen. The settings page has a line for it; this
    /// is the panel, which is where somebody actually looks when the Mac
    /// slept and they did not expect it to.
    ///
    /// It ends by itself when the condition drops, so there is nothing to
    /// dismiss — only a way to say «no, keep going».
    /// The same shape the settings page draws, from the same component.
    ///
    /// Through `HelmBanner`, not a hand-built `HStack` of a mark, `.caption`
    /// text and a button: one statement in two appearances, decided by which
    /// window you happened to open. The wrapping and the literal colours it
    /// needs are in the component.
    @ViewBuilder private var suppressedRow: some View {
        Group {
            // The battery wins. Both can be true — a rule is paused *and* the
            // charge is at or under the floor — and of the two only one explains why
            // nothing at all is happening. No button beside it either:
            // «Resume» while the guard is in force is a control that cannot do
            // what it says, and the notice goes by itself when the charger goes
            // in. The settings page draws the same pair the same way round.
            if vm.batteryStopped {
                // The short form. The hero says «— plug in» after it, which is
                // the way out; here there is no room for a second clause beside a
                // symbol in a 320 pt card, and the presets going grey above it
                // are what says the panel cannot help.
                HelmBanner(KAStr.stoppedByBatteryShort(batteryFloor), symbol: "battery.25", compact: true) {
                    EmptyView()
                }
            } else {
                // The short form. In a 320 pt card beside a button the long
                // sentence wraps to four lines — a paragraph where everything
                // else is a row.
                HelmBanner(KAStr.automationPausedShort, symbol: "pause.circle.fill", compact: true) {
                    Button(KAStr.resume) { vm.resumeAutomation() }
                        .controlSize(.small)
                        .fixedSize()
                }
            }
        }
        .padding(.top, HelmSpace.s4)
    }

    /// Quick automation toggles + a custom timer, revealed inline under the
    /// presets — same disclosure language as the panel's Utilities section
    /// (the accordion: the card grows by the block's measured height, clipped,
    /// no fade).
    private var moreControls: some View {
        // The top gap lives INSIDE the measured block: with stack spacing at 0
        // it must not exist while collapsed, and it should animate in with the
        // rest of the block.
        // Order follows intent: the custom timer continues the preset row above
        // it (same action, arbitrary length), then the automation rules — which
        // are standing settings, not actions — sit under their own heading so
        // their labels read as conditions.
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            Divider().padding(.top, HelmSpace.s4)

            settingRow(KAStr.timer) {
                HStack(spacing: HelmSpace.s3) {
                    // A menu of sensible durations beats nudging a stepper five
                    // minutes at a time in a 320 pt panel.
                    Menu {
                        ForEach(Self.timerOptions, id: \.self) { minutes in
                            Button(KAStr.duration(minutes)) { setMinutes(minutes) }
                        }
                        Divider()
                        Button(KAStr.customTime) {
                            editedMinutes = customMinutes
                            showCustomTime = true
                        }
                    } label: {
                        Text(KAStr.duration(customMinutes))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                    .popover(isPresented: $showCustomTime, arrowEdge: .bottom) { customTimeEditor }

                    Button(KAStr.start) {
                        vm.start(minutes: customMinutes)
                        withAnimation(HelmMotion.disclosure) { showMore = false }
                    }
                    .controlSize(.small)
                }
            }

            Text(KAStr.automation)
                // `smallPrint`, the settings scale's fine print, which is also
                // the panel card's group heading.
                .font(HelmText.smallPrint)
                // A literal colour, not `.secondary`. Hierarchical styles are
                // resolved against the rendering context, and this block gets
                // its own layer while its height animates (that is what
                // `.clipped()` needs). When the layer goes away at the end of
                // the animation the style resolves again — visibly, as a blink.
                // primary-with-alpha tracks light and dark on its own and does
                // not depend on the layer.
                .foregroundStyle(HelmText.quiet)
                .padding(.top, HelmSpace.s1)

            // Hidden on a Mac with no display of its own, the way the settings
            // page hides the same rule and the engine refuses it: every display a
            // mini or a Studio has is external, so the rule would mean «never
            // sleep». The panel is a writer too: offering the switch here while
            // the page hides its row would let a desktop be put into a state
            // whose only control is on the screen that does not draw it.
            //
            // The row's visible Text is a sibling, not the toggle's label, so
            // the title goes into the Toggle itself and labelsHidden keeps it
            // for VoiceOver only.
            if MacHardware.hasBuiltInDisplay {
                settingRow(KAStr.onExternalDisplay) {
                    Toggle(KAStr.onExternalDisplay, isOn: $autoExternalDisplay)
                        .labelsHidden()
                        .onChange(of: autoExternalDisplay) { _, v in
                            vm.save(in: store) { $0.setAutoExternalDisplay(v) }
                        }
                }
            }

            settingRow(KAStr.onPower) {
                Toggle(KAStr.onPower, isOn: $autoPower)
                    .labelsHidden()
                    .onChange(of: autoPower) { _, v in vm.save(in: store) { $0.setAutoPower(v) } }
            }
        }
    }

    // Round durations only: a compound label ("1 ч 30 мин") would force the menu
    // wide enough to push Start out of the card.
    private static let timerOptions = [5, 10, 15, 20, 30, 45, 60, 120, 180, 240]

    /// Label on the left, trailing control(s) pinned to the right edge.
    private func settingRow<Control: View>(_ title: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: HelmSpace.s4) {
            Text(title).font(HelmText.rowDetail).lineLimit(1)
            Spacer(minLength: HelmSpace.s4)
            control()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    /// The tile's own memory of what was last picked here, which nothing else
    /// reads — so it stays out of `KeepAwakeSettings`, the way `MenuBarLook`
    /// keeps the keys the engine never acts on.
    static let panelTimerMinutes = "panelTimerMinutes"

    /// What the countdown's one button adds, in its label and in what it asks
    /// for: one number, so the two cannot drift apart.
    private static let extraMinutes = 15

    /// The longest timer this tile offers, for the typed entry and for the
    /// stored choice alike. Neither needs a floor: both are read behind a
    /// `> 0`, where anything smaller already means "nothing chosen" rather
    /// than a duration.
    private static let maxCustomMinutes = 720

    /// The duration the tile opens on: the last panel choice, otherwise the
    /// module's default duration (0 = indefinite, which isn't a timer value)
    /// and finally 30.
    ///
    /// The remembered value is capped here, where it is read, to what the tile
    /// itself can produce (`maxCustomMinutes`), so a hand-edited `Int.max` in
    /// the plist reaches the engine as that; `startSession` clamps again before
    /// its `minutes * 60`. It goes straight into `vm.start(minutes:)`. The key is the tile's own and the engine never reads it, which is why it
    /// stays out of the settings type; that is about who reads it, not about
    /// whether the file can be trusted.
    ///
    /// The ceiling is this tile's, not the settings type's day: the entry below
    /// caps at the same number, so nothing that can be typed here is above it.
    /// The module's default arrives already clamped by `KeepAwakeSettings` and
    /// is taken as it comes — narrowing it again here would be the tile
    /// overruling a duration the module considers legal.
    static func openingMinutes(_ store: NamespacedStore) -> Int {
        let remembered = store.int(panelTimerMinutes, default: 0)
        let fallback = KeepAwakeSettings(store: store).defaultDurationMinutes
        return remembered > 0
            ? min(remembered, maxCustomMinutes)
            : (fallback > 0 ? fallback : 30)
    }

    private func setMinutes(_ minutes: Int) {
        customMinutes = minutes
        store.set(minutes, for: Self.panelTimerMinutes)
    }

    /// Free-form duration entry, opened from the menu's «Other…» entry: the
    /// field the settings page draws, in the prompt both surfaces share.
    private var customTimeEditor: some View {
        // Unlike the page's, this number is a *setting* — what the Start
        // button starts next time — so zero is not «Indefinite» here, it is a
        // duration the tile could not act on; the prompt disables its verb at 0,
        // so `applyCustomTime` is never reached with it.
        HelmDurationPrompt(KAStr.customTimeTitle, minutes: $editedMinutes,
                           ceiling: Self.maxCustomMinutes,
                           hourLabel: KAStr.hoursUnitShort,
                           minuteLabel: KAStr.minutesUnitShort,
                           verb: KAStr.done, apply: applyCustomTime)
    }

    private func applyCustomTime() {
        showCustomTime = false
        // `HelmDurationField` clamps to the ceiling it was handed, which is
        // this one — so the value only has to be stored.
        setMinutes(editedMinutes)
    }

    // MARK: - Active countdown

    private func countdownRow(_ end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let remaining = max(0, end.timeIntervalSince(ctx.date))
            HStack(spacing: HelmSpace.s3) {
                Image(systemName: "timer").foregroundStyle(HelmText.quiet)
                    // Decoration beside a figure that already says what it is;
                    // read aloud it announced «timer» before the time.
                    .accessibilityHidden(true)
                Text(TimerProgress.label(remaining: remaining))
                    .font(HelmText.figureFont.weight(.semibold))
                    .layoutPriority(1)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(HelmMotion.interface, value: remaining)
                    // Once a second, this row is rebuilt. Without the trait
                    // VoiceOver re-speaks the figure every time and interrupts
                    // itself doing it, so the panel cannot be used while a
                    // timer runs — and the panel is where the timer lives.
                    .accessibilityLabel(KAStr.a11yRemaining(
                        TimerProgress.label(remaining: remaining)))
                    .accessibilityAddTraits(.updatesFrequently)
                // No minimum: every sibling is rigid and the figure is the one
                // thing that can give, so the default gap here truncated
                // «23:59:56» beside the longer Russian and German captions.
                Spacer(minLength: 0)
                Button("+" + KAStr.duration(Self.extraMinutes, compact: true)) {
                    vm.start(minutes: TimerPolicy.extendedMinutes(
                        remaining: remaining, adding: Self.extraMinutes))
                }
                .controlSize(.small)
                .fixedSize()
                // Ends the timed session; the header toggle is the all-or-nothing
                // switch, this stops just the countdown.
                //
                // **The word never changes here, and it does not need to.** This
                // button is drawn only while a countdown is running, and a
                // session running is precisely what rules out `StopPress`'s
                // second step — so this press is `.stopEverything` or
                // `.stopSessionOnly`, and «Стоп» is the word for both. The page
                // spells its button from `KAStr.stopWord` because its Stop
                // outlives the countdown; this one does not.
                Button(KAStr.stop) { vm.stopSession() }
                    .controlSize(.small)
                    .fixedSize()
                // The automation controls must stay reachable while a timer runs.
                // A fixed width, not fixedSize(): the pill stretches inside the
                // preset row, so left to itself here it shrank to the glyph.
                morePill.frame(width: 46)
            }
        }
    }

}
