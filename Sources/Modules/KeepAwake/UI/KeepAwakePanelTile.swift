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
    /// inside `withAnimation` is eleven. Both animations in this file were the
    /// first spelling, and the comment below claiming a cross-fade described
    /// something that never happened.
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

    init(vm: ModuleViewModel, store: NamespacedStore) {
        self.vm = KeepAwakeViewModel.shared(vm: vm)
        self.store = store
        let settings = KeepAwakeSettings(store: store)
        _autoExternalDisplay = State(initialValue: settings.autoExternalDisplay)
        _autoPower = State(initialValue: settings.autoPower)
        _customMinutes = State(initialValue: Self.openingMinutes(store))
        let state = KeepAwakeViewModel.shared(vm: vm)
        _shownActive = State(initialValue: state.isActive)
        _shownSuppressed = State(initialValue: state.suppressed || state.batteryStopped)
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
            // the honest answer, and it took two attempts to actually get one:
            // this comment described a cross-fade for months while the modifier
            // under it carried nothing at all.
            Group {
                if shownActive, let end = vm.endDate {
                    countdownRow(end).transition(.opacity)
                } else {
                    presetRow.transition(.opacity)
                }
            }
            .padding(.top, 10)
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
            // opens the same automation controls either way. Its «no `.opacity`
            // here on purpose» is the modifier's now — this is the block whose
            // "Automation" heading snapped colour when the fade's layer was
            // dropped, and whose divider and switches washed out under a
            // compositing group.
            moreControls
                .helmAccordion(open: showMore, height: $moreHeight)
        }
        .helmPanelCard()
        // The transaction, not the modifier — see the note on `shownActive`.
        .onChange(of: vm.isActive) { _, running in
            withAnimation(HelmMotion.disclosure) { shownActive = running }
        }
        // Either notice fills the same slot, so the drawn flag is «there is
        // something to say» rather than «a rule is paused» — the battery guard
        // sets no `suppressed` of its own, and gating on that one would leave
        // its banner collapsed to nothing. The hero keeps the same pair.
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
        // #DE7A21 and this drew the system colour, so resizing a tile between
        // the two repainted its plate in place — which is the very defect
        // `HelmWidgetHeader` was written to end.
        HelmWidgetHeader(symbol: "moon.zzz.fill", tint: KeepAwakeDescriptor.tint.colour,
                         name: KAStr.moduleName,
                         subtitle: activeSubtitle, active: vm.isActive) {
            Toggle("", isOn: Binding(get: { vm.isActive }, set: { _ in vm.send(KeepAwakeCommand.toggle) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                // Orange switch = an automation rule (display/power/app) is
                // holding the session, so flipping it off may not stick.
                .tint(autoDriven ? .orange : nil)
                // Live but dead while the battery guard vetoes: the engine
                // refuses the session instantly and the switch springs back, so
                // the one control in the menu bar that starts a session was a
                // control that visibly did nothing. The notice below it is on
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
        // **What is true of the machine, not what is true of the lid.** This said
        // «Lid closed — staying awake», in a list of what was holding the Mac —
        // and the lid is not holding anything: sleep is off for the whole Mac,
        // through a rule that outlives this process, and the lid being closed is
        // merely the reason somebody asked for that. The settings row says the
        // same sentence, with the way back out of it after it.
        if vm.clamshellActive { parts.append(KAStr.sleepIsOffNow) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Presets + more

    private var presetRow: some View {
        HStack(spacing: 6) {
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
    /// reached before anything is held. Pressing one was silence with a banner
    /// beside it explaining a state the person had no reason to connect to the
    /// press. Disabled, not hidden: a row of pills that came and went would take
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
        // only feedback for pressing it was silence.
        .accessibilityValue(showMore ? KAStr.disclosureExpanded : KAStr.disclosureCollapsed)
    }

    private func pillLabel(_ content: some View, active: Bool = false) -> some View {
        content
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 16)
            .padding(.vertical, 6)
            .background(Capsule().fill(active ? Color.accentColor.opacity(0.25) : HelmSurface.onPanelFill))
            .contentShape(Capsule())
    }

    /// A rule applies, and the Mac is asleep anyway.
    ///
    /// Stopping a session while a rule still holds silences that rule until it
    /// fires again — and a timer that ends automation does the same when it
    /// runs out. Both are correct and neither is visible: the switch reads off,
    /// the rule reads on, and the Mac sleeps with the app that should be
    /// holding it still on screen. The settings page grew a line for it; this
    /// is the panel, which is where somebody actually looks when the Mac
    /// slept and they did not expect it to.
    ///
    /// It ends by itself when the condition drops, so there is nothing to
    /// dismiss — only a way to say «no, keep going».
    /// The same shape the settings page draws, from the same component.
    ///
    /// This was a hand-built `HStack` — a mark, `.caption` text, a button, no
    /// fill — while the hero drew the identical sentence through `HelmBanner`
    /// as a tinted field at 13 pt. One statement, two appearances, decided by
    /// which window you happened to open. `HelmBanner` was extracted for the
    /// hero and this copy simply outlived the extraction; the wrapping and the
    /// literal colours it needed are both already in there, for the same two
    /// reasons they were written here.
    /// Whether the slot under the presets has anything in it at all.
    private var hasNotice: Bool { vm.suppressed || vm.batteryStopped }

    @ViewBuilder private var suppressedRow: some View {
        Group {
            // The battery wins. Both can be true — a rule is paused *and* the
            // charge is under the floor — and of the two only one explains why
            // nothing at all is happening. No button beside it either:
            // «Resume» while the guard is in force is a control that cannot do
            // what it says, and the notice goes by itself when the charger goes
            // in. The settings page draws the same pair the same way round.
            if vm.batteryStopped {
                // The short form. The hero says «— plug in» after it, which is
                // the way out; here there is no room for a second clause beside a
                // symbol in a 320 pt card, and the presets going grey above it
                // are what says the panel cannot help.
                HelmBanner(KAStr.stoppedByBatteryShort(batteryFloor), symbol: "battery.25")
            } else {
                // The short form. In a 320 pt card beside a button the long
                // sentence wrapped to four lines — a paragraph where everything
                // else is a row.
                HelmBanner(KAStr.automationPausedShort, symbol: "pause.circle.fill") {
                    Button(KAStr.resume) { vm.send(KeepAwakeCommand.resumeAutomation) }
                        .controlSize(.small)
                        .fixedSize()
                }
            }
        }
        .padding(.top, 10)
    }

    /// Quick automation toggles + a custom timer, revealed inline under the
    /// presets — same disclosure language as the panel's Utilities section
    /// (rows fade in cascading, the card grows downward).
    private var moreControls: some View {
        // The top gap lives INSIDE the measured block: with stack spacing at 0
        // it must not exist while collapsed, and it should animate in with the
        // rest of the block.
        // Order follows intent: the custom timer continues the preset row above
        // it (same action, arbitrary length), then the automation rules — which
        // are standing settings, not actions — sit under their own heading so
        // their labels read as conditions.
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.top, 10)

            settingRow(KAStr.timer) {
                HStack(spacing: 6) {
                    // A menu of sensible durations beats nudging a stepper five
                    // minutes at a time in a 300pt panel.
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
                // 10, and the panel's own scale rather than the settings
                // window's — this tile is drawn inside the menu-bar panel.
                .font(.caption)
                // A literal colour, not `.secondary`. Hierarchical styles are
                // resolved against the rendering context, and this block gets
                // its own layer while its height animates (that is what
                // `.clipped()` needs). When the layer goes away at the end of
                // the animation the style resolves again — visibly, as a blink.
                // primary-with-alpha tracks light and dark on its own and does
                // not depend on the layer.
                .foregroundStyle(HelmText.quiet)
                .padding(.top, 2)

            // Hidden on a Mac with no display of its own, the way the settings
            // page hides the same rule and the engine refuses it: every display a
            // mini or a Studio has is external, so the rule would mean «never
            // sleep». This was the **writer** — the page hid its row and the panel
            // went on offering the switch, so a desktop could be put into a state
            // whose only control was on the screen that does not draw it.
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

    // Round durations only: a compound label ("1 ч 30 мин") forced the menu wide
    // enough to push Start out of the card.
    private static let timerOptions = [5, 10, 15, 20, 30, 45, 60, 120, 180, 240]

    /// Label on the left, trailing control(s) pinned to the right edge.
    private func settingRow<Control: View>(_ title: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline).lineLimit(1)
            Spacer(minLength: 8)
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
    /// for — the two were the same literal twice, one of them inside a string.
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
    /// The remembered value is capped here, where it is read, for the reason
    /// `KeepAwakeSettings` clamps its two: it goes straight into `startPayload`,
    /// and `startSession` turns minutes into seconds with a multiply that
    /// **traps** on `Int` overflow — so a hand-edited `Int.max` in the plist is
    /// the app terminating when Start is pressed, not a very long timer. The
    /// key is the tile's own and the engine never reads it, which is why it
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

    /// Free-form duration entry, opened from the menu's "Custom…" entry.
    ///
    /// The same field the settings page draws — a shape two surfaces draw
    /// belongs to `HelmUI`, and this was the older of the two: one box asking
    /// for minutes, so «two hours» was a sum the person had to do and `120`
    /// read the same as `12`.
    private var customTimeEditor: some View {
        VStack(spacing: 12) {
            Text(KAStr.customTimeTitle)
                .font(.subheadline.weight(.semibold))
            HelmDurationField(minutes: $editedMinutes,
                              ceiling: Self.maxCustomMinutes,
                              hourLabel: KAStr.hoursUnitShort,
                              minuteLabel: KAStr.minutesUnitShort)
            Button(KAStr.done, action: applyCustomTime)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                // Unlike the page's, this number is a *setting* — what the
                // switch starts next time — so zero is not «Indefinite» here,
                // it is a duration the tile could not act on.
                .disabled(editedMinutes == 0)
        }
        .padding(14)
        .frame(width: 226)
    }

    private func applyCustomTime() {
        showCustomTime = false
        guard editedMinutes > 0 else { return }
        // `HelmDurationField` clamps to the ceiling it was handed, which is
        // this one — so the value only has to be stored.
        setMinutes(editedMinutes)
    }

    // MARK: - Active countdown

    private func countdownRow(_ end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let remaining = max(0, end.timeIntervalSince(ctx.date))
            HStack(spacing: 8) {
                Image(systemName: "timer").foregroundStyle(HelmText.quiet)
                    // Decoration beside a figure that already says what it is;
                    // read aloud it announced «timer» before the time.
                    .accessibilityHidden(true)
                Text(TimerProgress.label(remaining: remaining))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(HelmMotion.interface, value: remaining)
                    // Once a second, this row is rebuilt. Without the trait
                    // VoiceOver re-speaks the figure every time and interrupts
                    // itself doing it, so the panel cannot be used while a
                    // timer runs — and the panel is where the timer lives.
                    .accessibilityLabel(KAStr.a11yRemaining(
                        TimerProgress.label(remaining: remaining)))
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer()
                Button("+" + KAStr.duration(Self.extraMinutes, compact: true)) {
                    vm.start(minutes: TimerPolicy.extendedMinutes(
                        remaining: remaining, adding: Self.extraMinutes))
                }
                .controlSize(.small)
                // Ends the timed session; the header toggle is the all-or-nothing
                // switch, this stops just the countdown.
                Button(KAStr.stop) { vm.send(KeepAwakeCommand.stop) }
                    .controlSize(.small)
                // The automation controls must stay reachable while a timer runs.
                // A fixed width, not fixedSize(): the pill stretches inside the
                // preset row, so left to itself here it shrank to the glyph.
                morePill.frame(width: 46)
            }
        }
    }

}
