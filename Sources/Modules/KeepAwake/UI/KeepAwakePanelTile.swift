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
    /// `.animation(_:value:)` carries neither a transition nor a layout change,
    /// so both animations in this file are written inside `withAnimation`
    /// (Architecture/DesignSystem.md § Motion).
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
        _shownSuppressed = State(initialValue: vm.notice != .none)
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
            // Above the ⋯ block, never inside it: nothing else on any screen
            // says the rule has stopped working. The same accordion as below,
            // so the card does not change size under the pointer with no motion.
            suppressedRow
                .helmAccordion(open: shownSuppressed, height: $suppressedHeight)
            // The accordion, mounted whether or not a session is running, so
            // the ⋯ button opens the same automation controls either way. Why
            // there is no `.opacity` is on the modifier (`HelmAccordion.swift`).
            moreControls
                .helmAccordion(open: showMore, height: $moreHeight)
        }
        .helmPanelCard()
        // The transaction, not the modifier — see the note on `shownActive`.
        .onChange(of: vm.isActive) { _, running in
            withAnimation(HelmMotion.disclosure) { shownActive = running }
        }
        .onChange(of: vm.notice) { _, arrived in
            withAnimation(HelmMotion.disclosure) { shownSuppressed = arrived != .none }
        }
        // The store isn't observable, so these mirrored values would otherwise
        // drift once the same settings are changed in the Settings window.
        .keepAwakeAutomationMirror(store, externalDisplay: $autoExternalDisplay,
                                   power: $autoPower, batteryFloor: $batteryFloor)
    }

    // MARK: - Header

    private var header: some View {
        // The shared widget header: five widgets in one panel, one heading.
        // The token, not `.orange`: the 1×1 widget draws the module's own
        // #DE7A21, and the system colour would repaint the plate when a tile
        // is resized between the two.
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
                // Disabled while the battery guard vetoes: the engine refuses
                // the session at once and the switch would spring back. The
                // notice below says why.
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
        // What is true of the machine, not of the lid: sleep is off for the
        // whole Mac, through a rule that outlives this process. The settings
        // row says the same sentence, with the way back out after it.
        if vm.clamshellActive { parts.append(KAStr.sleepIsOffNow) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Presets + more

    private var presetRow: some View {
        HStack(spacing: HelmSpace.s3) {
            presetPill(KAStr.duration(15, compact: true), 15)
            presetPill(KAStr.duration(60, compact: true), 60)
            presetPill(KAStr.duration(120, compact: true), 120)
            // The glyph is the label a 320 pt row can take; VoiceOver gets the
            // word the settings page's own button says, not the character.
            presetPill("∞", 0, spoken: KAStr.indefinite)
            morePill
        }
    }

    /// Every one of these asks the engine for a session, which the battery veto
    /// refuses at once (`releaseForBattery` is reached before anything is held).
    /// Disabled, not hidden: pills that came and went would take the card's
    /// height with them, and the notice is the sentence.
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
        // Which of the two things this button does it has just done: the block
        // below is hidden from the tree while collapsed. `HelmA11y`'s pair, so
        // one state has one name across the app.
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

    /// A rule applies, and the Mac is asleep anyway.
    ///
    /// Stopping a session while a rule still holds silences that rule until it
    /// fires again, and a timer that ends automation does the same when it runs
    /// out. Neither is otherwise visible: the switch reads off, the rule reads
    /// on, and the Mac sleeps with the rule's app on screen. The panel is where
    /// somebody looks when the Mac slept unexpectedly.
    ///
    /// It ends by itself when the condition drops, so there is nothing to
    /// dismiss, only a way to say «no, keep going». The same component the
    /// settings page draws, so one statement has one appearance.
    @ViewBuilder private var suppressedRow: some View {
        KeepAwakeNoticeBanner(notice: vm.notice, batteryFloor: batteryFloor, compact: true,
                              resume: { vm.resumeAutomation() })
        .padding(.top, HelmSpace.s4)
    }

    /// Quick automation toggles + a custom timer, revealed inline under the
    /// presets — same disclosure language as the panel's Utilities section
    /// (the accordion: the card grows by the block's measured height, clipped,
    /// no fade).
    private var moreControls: some View {
        // The top gap lives inside the measured block, so it does not exist
        // while collapsed and animates in with the rest.
        // The custom timer continues the preset row above it; the automation
        // rules are standing settings, not actions, so they sit under their own
        // heading and their labels read as conditions.
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
                // A literal colour, not `.secondary`: this block gets its own
                // layer while its height animates, and a hierarchical style
                // resolves again when the layer goes, as a blink.
                .foregroundStyle(HelmText.quiet)
                .padding(.top, HelmSpace.s1)

            // Hidden on a Mac with no lid, as on the settings page and in the
            // engine (Architecture/KeepAwake.md § Rules read from the machine).
            // The panel is a writer too, so offering it here would let a
            // desktop reach a state no page draws a control for.
            //
            // The row's visible Text is a sibling, not the toggle's label, so
            // the title goes into the Toggle itself and labelsHidden keeps it
            // for VoiceOver only.
            if MacHardware.hasLid {
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

    /// The duration the tile opens on: the last panel choice, otherwise the
    /// module's default duration (0 = indefinite, which isn't a timer value)
    /// and finally 30.
    ///
    /// The remembered value is capped here, where it is read, to what the tile
    /// itself can produce (`TimerPolicy.longestSessionMinutes`), so a hand-edited
    /// `Int.max` in the plist reaches `vm.start(minutes:)` as that;
    /// `startSession` clamps again before its `minutes * 60`. The key stays out
    /// of the settings type because only the tile reads it, not because the
    /// file can be trusted.
    ///
    /// The module's default arrives already clamped by `KeepAwakeSettings` and
    /// is taken as it comes, so the tile does not overrule a duration the
    /// module considers legal.
    static func openingMinutes(_ store: NamespacedStore) -> Int {
        let remembered = store.int(panelTimerMinutes, default: 0)
        let fallback = KeepAwakeSettings(store: store).defaultDurationMinutes
        return remembered > 0
            ? min(remembered, TimerPolicy.longestSessionMinutes)
            : (fallback > 0 ? fallback : 30)
    }

    private func setMinutes(_ minutes: Int) {
        customMinutes = minutes
        store.set(minutes, for: Self.panelTimerMinutes)
    }

    /// Free-form duration entry, opened from the menu's «Other…» entry: the
    /// field the settings page draws, in the prompt both surfaces share.
    var customTimeEditor: KeepAwakeCustomDuration {
        // Unlike the page's, this number is a *setting* — what the Start
        // button starts next time — so zero is not «Indefinite» here, it is a
        // duration the tile could not act on; the prompt disables its verb at 0,
        // so `applyCustomTime` is never reached with it.
        KeepAwakeCustomDuration(minutes: $editedMinutes, verb: KAStr.done,
                                apply: applyCustomTime)
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
                    // Rebuilt once a second: without the trait VoiceOver
                    // re-speaks the figure every time and interrupts itself.
                    .accessibilityLabel(KAStr.a11yRemaining(
                        TimerProgress.label(remaining: remaining)))
                    .accessibilityAddTraits(.updatesFrequently)
                // No minimum: every sibling is rigid and the figure is the one
                // thing that can give, so a default gap truncates «23:59:56»
                // beside the longer Russian and German captions.
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
                // The word never changes here: the button is drawn only while a
                // countdown runs, which rules out `StopPress`'s second step, and
                // «Stop» is the word for both remaining presses. The page spells
                // its button from `KAStr.stopWord` because its Stop outlives the
                // countdown.
                Button(HelmWord.stop) { vm.stopSession() }
                    .controlSize(.small)
                    .fixedSize()
                // The automation controls stay reachable while a timer runs.
                // A fixed width, not fixedSize(): the pill stretches inside the
                // preset row, and left to itself here it shrinks to the glyph.
                morePill.frame(width: 46)
            }
        }
    }

}
