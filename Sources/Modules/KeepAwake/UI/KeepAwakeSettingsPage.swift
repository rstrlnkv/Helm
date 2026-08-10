import SwiftUI
import AppKit
import Carbon.HIToolbox
import HelmRuntime
import HelmUI
import Module_KeepAwake_Engine

/// Settings page for the Keep Awake module. The `NamespacedStore` isn't
/// observable, so values are seeded into local `@State` and written through
/// on every change, notifying the engine via `settingsChanged`.
public struct KeepAwakeSettingsPage: View {
    // Observed, not held: the state strip reads isActive and the live
    // conditions, and a plain `let` means SwiftUI never hears them change —
    // the figures froze at whatever they were when the page opened.
    @ObservedObject private var vm: KeepAwakeViewModel
    private let store: NamespacedStore

    @State private var accessibility: PermissionState = .granted
    @State private var autoExternalDisplay: Bool
    @State private var autoPower: Bool
    @State private var appTriggers: [AppTrigger]

    @State private var keepDisplayOn: Bool
    @State private var jiggleEnabled: Bool
    @State private var jiggleIntervalMinutes: Int
    @State private var defaultDurationMinutes: Int

    @State private var clamshellEnabled: Bool
    @State private var timerEndsAutomation: Bool

    @State private var batteryGuardEnabled: Bool
    @State private var batteryGuardPercent: Int

    @State private var activeTintColor: String
    @State private var ringTimer: Bool
    @State private var showTimerText: Bool
    @State private var timerTintColor: String
    @State private var customActiveIcon: Bool
    @State private var activeIconShape: String
    @StateObject private var recorder: HelmHotkeyRecorder

    public init(vm: ModuleViewModel, store: NamespacedStore) {
        self.vm = KeepAwakeViewModel.shared(vm: vm)
        self.store = store
        _recorder = StateObject(wrappedValue: HelmHotkeyRecorder(store: store))
        // Every one of these through the settings struct, not a second literal:
        // the engine's battery-guard default is on, and a toggle drawn off above
        // a guard that is armed would be the page lying about what the Mac will
        // do. The same holds for the rest of them, and for the jiggle clamp.
        let settings = KeepAwakeSettings(store: store)
        _autoExternalDisplay = State(initialValue: settings.autoExternalDisplay)
        _autoPower = State(initialValue: settings.autoPower)
        _appTriggers = State(initialValue: settings.appTriggers)
        _keepDisplayOn = State(initialValue: settings.keepDisplayOn)
        _jiggleEnabled = State(initialValue: settings.jiggleEnabled)
        _jiggleIntervalMinutes = State(initialValue: settings.jiggleIntervalMinutes)
        _defaultDurationMinutes = State(initialValue: settings.defaultDurationMinutes)
        _clamshellEnabled = State(initialValue: settings.clamshellEnabled)
        _timerEndsAutomation = State(initialValue: settings.timerEndsAutomation)
        _batteryGuardEnabled = State(initialValue: settings.batteryGuardEnabled)
        _batteryGuardPercent = State(initialValue: settings.batteryGuardPercent)
        _activeTintColor = State(initialValue: MenuBarLook.activeTint(store))
        _ringTimer = State(initialValue: MenuBarLook.ringTimer(store))
        _showTimerText = State(initialValue: MenuBarLook.showTimerText(store))
        _timerTintColor = State(initialValue: MenuBarLook.timerTint(store))
        _customActiveIcon = State(initialValue: MenuBarLook.customIcon(store))
        _activeIconShape = State(initialValue: MenuBarLook.iconShape(store))
    }

    public var body: some View {
        // The hero is not a section of the form. A grouped `Form` draws every
        // section as a card, and a card holds *a list of things*; the state of
        // the module is one thing, and v3 puts it on the bare pane with air
        // around it. In a card it read as the first row of the settings list it
        // had just stopped being.
        VStack(spacing: 0) {
            sessionHero
            keepAwakeForm
        }
            .helmOnAppActive { accessibility = PermissionCheck.currentAccessibility() }
        .task { accessibility = PermissionCheck.currentAccessibility() }
    }

    /// The same countdown the menu bar and the panel show.
    ///
    /// This was a third spelling with no hours field, so a two-hour session —
    /// one of the offered presets — read "120:00" here while the menu bar read
    /// "2:00:00" at the same instant.
    private var remainingText: String {
        guard let end = vm.endDate else { return "—" }
        return TimerProgress.label(remaining: end.timeIntervalSinceNow)
    }

    /// Seven sections, each its own fragment.
    ///
    /// This was one 123-line expression: more than anyone can hold at once and
    /// more than SwiftUI's type-checker enjoys. `Section` stays the outermost
    /// view of every fragment — a `Form` groups by what its direct children
    /// are, so wrapping one in anything would change the layout — and every
    /// modifier below stays on the `Form` itself, including the store observer
    /// that keeps this page and the panel agreeing.
    private var keepAwakeForm: some View {
        Form {

            automationSection
            appsSection

            behaviourSection

            menuBarIconSection
            timerSection
            shortcutSection
        }
        .formStyle(.grouped)
        .helmSettingsColumn()
        // The panel's ⋯ block writes the same keys; without this the page shows
        // stale values when both are open (the reverse direction already works).
        .keepAwakeAutomationMirror(store, externalDisplay: $autoExternalDisplay,
                                   power: $autoPower)
    }

    // MARK: - The sections

    /// What is happening, and the verbs for it.
    ///
    /// It was `HelmMetricStrip` — «ВЫКЛ · — · 0» before anything is configured.
    /// Two of those three figures are the unreadable kind this house does not
    /// draw at all, and above twenty controls there was not one that could
    /// begin or end a session: the screen whose whole job is to say what is
    /// happening was the only screen that could not change it. Every command
    /// here was already on the wire; the panel tile sends the same ones.
    @ViewBuilder private var sessionHero: some View {
        VStack(spacing: 10) {
            // A countdown needs a tick of its own: the engine emits state on
            // change, not once a second, so a figure drawn from it froze at
            // whatever it read when the page opened. The panel tile solves it
            // the same way.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                hero(SessionHero.of(isActive: vm.isActive, endDate: vm.endDate,
                                    conditions: vm.activeConditions, now: timeline.date))
            }
            // The Mac is asleep, a rule that applies is on screen saying
            // nothing, and until now there was no third thing to read. Only
            // shown while it is true, and it stops being true by itself when
            // the condition drops.
            if vm.suppressed {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(HelmSignal.warning)
                        .accessibilityHidden(true)
                    Text(KAStr.automationPaused)
                        .font(.callout).foregroundStyle(HelmText.quiet)
                    Spacer(minLength: 8)
                    Button(KAStr.resume) { vm.send(KeepAwakeCommand.resumeAutomation) }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 18)
        .helmSettingsColumn()
    }

    @ViewBuilder private func hero(_ state: SessionHero) -> some View {
        VStack(spacing: 8) {
            switch state {
            case .idle:
                // The figure's slot, in words. 40 pt light is the size the
                // countdown gets, and an idle page that dropped to body text
                // there made the whole screen change shape when a timer began.
                Text(KAStr.heroIdle)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(HelmText.quiet)
                Text(anyRuleOn ? KAStr.heroIdleReason : KAStr.heroNoRules)
                    .font(.callout).foregroundStyle(HelmText.faint)
                HStack(spacing: 8) {
                    startButton(KAStr.duration(15), minutes: 15)
                    startButton(KAStr.oneHour, minutes: 60)
                    startButton(KAStr.twoHours, minutes: 120)
                    startButton(KAStr.indefinite, minutes: 0)
                }
                .padding(.top, 10)
            case .timed(let end):
                // Monospaced, so the figure does not jitter as the digits
                // change width — it is redrawn once a second for hours.
                Text(TimerProgress.label(remaining: end.timeIntervalSinceNow))
                    .font(.system(size: 40, weight: .light, design: .monospaced))
                    .tracking(-2)
                    .contentTransition(.numericText(countsDown: true))
                Text(timedNote(end)).font(.callout).foregroundStyle(HelmText.quiet)
                HStack(spacing: 8) {
                    // The same arithmetic the panel's «+15» uses, and for the
                    // same reason: this is a `Double` that came off disk.
                    Button("+" + KAStr.duration(15)) {
                        start(TimerPolicy.extendedMinutes(remaining: end.timeIntervalSinceNow,
                                                          adding: 15))
                    }
                    .controlSize(.large)
                    Button(KAStr.indefinite) { start(0) }
                        .controlSize(.large)
                    stopButton
                }
                .padding(.top, 10)
            case .indefinite:
                Text(KAStr.heroIndefinite)
                    .font(.system(size: 40, weight: .light))
                HStack(spacing: 8) { stopButton }
                    .padding(.top, 10)
            case .automatic(let conditions):
                Text(KAStr.heroAutomatic)
                    .font(.system(size: 40, weight: .light))
                Text(conditions.map(KAStr.condition).sorted().joined(separator: " · "))
                    .font(.callout).foregroundStyle(HelmText.quiet)
                HStack(spacing: 8) {
                    Button(KAStr.startTimerFor(defaultDurationMinutes)) {
                        start(defaultDurationMinutes)
                    }
                    .controlSize(.large)
                    stopButton
                }
                .padding(.top, 10)
                // Stop does not end an automatic session, it silences the rule
                // — the one thing nobody could learn from any screen. Said
                // beside the button that does it.
                Text(KAStr.heroStopSuppresses)
                    .font(.caption).foregroundStyle(HelmText.faint)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// «Таймер до 15:42 · дальше держит внешний дисплей». The second clause is
    /// the only answer on the page to what happens at zero.
    private func timedNote(_ end: Date) -> String {
        let until = KAStr.timerUntil(end)
        guard let holder = SessionHero.holderAfterTimer(
                conditions: vm.activeConditions,
                timerEndsAutomation: timerEndsAutomation) else { return until }
        return until + " · " + KAStr.thenHeldBy(holder)
    }

    /// True when anything is configured that *could* hold the Mac — which is
    /// the difference between «nothing is set up» and «nothing applies now».
    private var anyRuleOn: Bool {
        autoExternalDisplay || autoPower || !appTriggers.isEmpty
    }

    /// The preset the menu-bar switch and the shortcut start is the prominent
    /// one. It is the only place on any screen that says which that is — the
    /// row that used to say it in words is gone with the rest of the settings.
    @ViewBuilder private func startButton(_ title: String, minutes: Int) -> some View {
        // `.borderedProminent`, not `.tint` on a plain button: a tint colours a
        // button's *label* and leaves the fill alone, so all four presets came
        // out identical and the one the switch actually starts was a claim
        // nothing on screen backed up.
        if minutes == defaultDurationMinutes {
            Button(title) { start(minutes) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else {
            Button(title) { start(minutes) }
                .controlSize(.large)
        }
    }

    private var stopButton: some View {
        Button(KAStr.stop) { vm.send(KeepAwakeCommand.stop) }
            .controlSize(.large)
    }

    private func start(_ minutes: Int) {
        guard let payload = try? JSONEncoder().encode(KeepAwakeStart(minutes: minutes)) else { return }
        vm.send(KeepAwakeCommand.start, payload: payload)
    }

    /// Four rules, and every row answers two questions at once: the mark on the
    /// left is what is happening now — a condition off the wire — and the
    /// control on the right is what is configured, out of the store. The second
    /// edition put those 268 pt apart, so a person reading the page saw that a
    /// rule was holding the Mac and could not see what to change about it.
    @ViewBuilder private var automationSection: some View {
        Section(header: HelmSectionTitle(KAStr.automation)) {
            ruleRow(KAStr.condition(.externalDisplay), on: $autoExternalDisplay,
                    satisfiedBy: .externalDisplay) { v in
                vm.save(in: store) { $0.setAutoExternalDisplay(v) }
            }
            ruleRow(KAStr.onPower, on: $autoPower, satisfiedBy: .power) { v in
                vm.save(in: store) { $0.setAutoPower(v) }
            }
            // No mark: the lid is not a rule that fires, it is a switch that
            // changes the whole Mac — and the note says what that costs.
            HelmSettingRow(KAStr.keepAwakeLidClosed, note: KAStr.adminNote, mark: .space) {
                Toggle(KAStr.keepAwakeLidClosed, isOn: $clamshellEnabled)
                    .labelsHidden()
                    .onChange(of: clamshellEnabled) { _, v in
                        vm.save(in: store) { $0.setClamshellEnabled(v) }
                    }
            }
            // Between the conditions and the guard that ends a session: this is
            // about the end of one too, and it means nothing to somebody who
            // has no conditions above it. v3 does not draw this row — the
            // setting was written after the mockup, and here is where it
            // belongs: beside the rules whose end it changes.
            HelmSettingRow(KAStr.timerEndsAutomation, note: KAStr.timerEndsAutomationNote,
                           mark: .space) {
                Toggle(KAStr.timerEndsAutomation, isOn: $timerEndsAutomation)
                    .labelsHidden()
                    .onChange(of: timerEndsAutomation) { _, v in
                        vm.save(in: store) { $0.setTimerEndsAutomation(v) }
                    }
            }
            // The threshold and the switch on one row: a level means nothing
            // with the guard off, and the pop-up is disabled rather than hidden
            // so the number you set is still the number you see.
            HelmSettingRow(KAStr.turnOffLowBattery, mark: .space) {
                Picker(KAStr.turnOffLowBattery, selection: $batteryGuardPercent) {
                    ForEach(HelmChoices.including(batteryGuardPercent, in: Self.batteryLevels),
                            id: \.self) { level in
                        Text(KAStr.belowPercent(level)).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(!batteryGuardEnabled)
                .onChange(of: batteryGuardPercent) { _, v in
                    vm.save(in: store) { $0.setBatteryGuardPercent(v) }
                }
                Toggle(KAStr.turnOffLowBattery, isOn: $batteryGuardEnabled)
                    .labelsHidden()
                    .onChange(of: batteryGuardEnabled) { _, v in
                        vm.save(in: store) { $0.setBatteryGuardEnabled(v) }
                    }
            }
        }
    }

    /// Five per cent to fifty, as the stepper this replaced stepped.
    private static let batteryLevels = Array(stride(from: 5, through: 50, by: 5))

    /// A rule the engine can report on: the mark comes from `activeConditions`,
    /// the switch from the store, and the note from the two together.
    @ViewBuilder
    private func ruleRow(_ title: String, on binding: Binding<Bool>,
                         satisfiedBy condition: ActiveCondition,
                         save: @escaping (Bool) -> Void) -> some View {
        let enabled = binding.wrappedValue
        let satisfied = vm.activeConditions.contains(condition)
        HelmSettingRow(title,
                       note: enabled ? (satisfied ? KAStr.ruleApplies : KAStr.ruleWaiting) : nil,
                       mark: .of(enabled: enabled, satisfied: satisfied)) {
            Toggle(title, isOn: binding)
                .labelsHidden()
                .onChange(of: binding.wrappedValue) { _, v in save(v) }
        }
    }

    @ViewBuilder private var appsSection: some View {
        Section(header: HelmSectionTitle(KAStr.appsSection)) {
            appTriggersEditor
        }
    }

    @ViewBuilder private var behaviourSection: some View {
        Section(header: HelmSectionTitle(KAStr.behavior)) {
            Toggle(KAStr.keepDisplayOn, isOn: $keepDisplayOn)
                .onChange(of: keepDisplayOn) { _, v in vm.save(in: store) { $0.setKeepDisplayOn(v) } }
            // One row: the interval only means anything with the switch on,
            // so it sits beside it instead of on a line of its own.
            LabeledContent(KAStr.movePointer) {
                HStack(spacing: 10) {
                    Stepper(KAStr.everyMinutes(jiggleIntervalMinutes),
                            value: $jiggleIntervalMinutes, in: 1...60)
                        .disabled(!jiggleEnabled)
                        .onChange(of: jiggleIntervalMinutes) { _, v in
                            vm.save(in: store) { $0.setJiggleIntervalMinutes(v) }
                        }
                        .fixedSize()
                    Toggle(KAStr.movePointer, isOn: $jiggleEnabled)
                        .labelsHidden()
                        .onChange(of: jiggleEnabled) { _, v in
                            vm.save(in: store) { $0.setJiggleEnabled(v) }
                        }
                }
            }
            // macOS drops synthetic mouse events from an untrusted app, so
            // without this grant the switch above is on and nothing moves.
            // Say so where the switch is, not only in the app's settings.
            if jiggleEnabled, accessibility == .denied {
                HelmPermissionNote(need: .accessibility,
                                   text: KAStr.pointerNeedsAccessibility)
            }
            // The minutes entry is the tile's own label; the two hour entries are
            // not, on purpose — `KAStr.duration` spells them "1 h" / "2 h", which
            // is what a preset pill needs and not what this row wants.
            Picker(KAStr.defaultDuration, selection: $defaultDurationMinutes) {
                Text(KAStr.duration(15)).tag(15)
                Text(KAStr.oneHour).tag(60)
                Text(KAStr.twoHours).tag(120)
                Text(KAStr.indefinite).tag(0)
            }
            .onChange(of: defaultDurationMinutes) { _, v in
                vm.save(in: store) { $0.setDefaultDurationMinutes(v) }
            }
        }
    }

    @ViewBuilder private var menuBarIconSection: some View {
        Section(header: HelmSectionTitle(KAStr.menuBarIcon)) {
            LabeledContent(KAStr.activeIconColor) { colorSwatches }
            Toggle(KAStr.customActiveIcon, isOn: $customActiveIcon)
                .onChange(of: customActiveIcon) { _, v in writeLook(v, MenuBarLook.Key.customIcon) }
            if customActiveIcon {
                IconShapePicker(selection: $activeIconShape, tintToken: activeTintColor)
                    .onChange(of: activeIconShape) { _, v in writeLook(v, MenuBarLook.Key.iconShape) }
            }
            Text(KAStr.ringColorNote)
                .font(.caption).foregroundStyle(HelmText.quiet)
        }
    }

    @ViewBuilder private var timerSection: some View {
        Section(header: HelmSectionTitle(KAStr.timer)) {
            Toggle(KAStr.ringTimer, isOn: $ringTimer)
                .onChange(of: ringTimer) { _, v in writeLook(v, MenuBarLook.Key.ringTimer) }
            Text(KAStr.ringTimerNote)
                .font(.caption).foregroundStyle(HelmText.quiet)
            Toggle(KAStr.showTimerText, isOn: $showTimerText)
                .onChange(of: showTimerText) { _, v in writeLook(v, MenuBarLook.Key.showTimerText) }
            LabeledContent(KAStr.timerColor) { timerColorSwatches }
        }
    }

    @ViewBuilder private var shortcutSection: some View {
        Section(header: HelmSectionTitle(KAStr.globalShortcut)) {
            HelmHotkeyRow(KAStr.toggleAction, recorder: recorder,
                          taken: HotkeyStatus.isTaken("keep-awake.toggle"))
        }
    }

    // MARK: - Write-through

    /// The menu-bar look only, whose keys `MenuBarLook` owns and the engine never
    /// reads. Everything the engine acts on goes through `vm.save(in:)` instead,
    /// which spells no key at all.
    private func writeLook(_ value: Any?, _ key: String) {
        store.set(value, for: key)
        vm.send(KeepAwakeCommand.settingsChanged)
    }

    // MARK: - App picker

    /// Rows handed to the `Section` one by one, not wrapped in a `VStack`.
    ///
    /// The wrapper made this the only per-app list in Helm without the system's
    /// row padding and hairlines: measured against the identical list in VPN it
    /// came out 13 pt shorter with no separators at all. The form draws both,
    /// and draws them the way every other section is drawn.
    @ViewBuilder
    private var appTriggersEditor: some View {
        if appTriggers.isEmpty {
            Text(KAStr.noAppsYet)
                .font(.callout).foregroundStyle(HelmText.quiet)
        }
            // One row per app: icon, name, when it applies, and the remove
            // button. The condition is a single menu because the two flags are
            // not independent choices — "display and power" means both.
            ForEach(Array(appTriggers.enumerated()), id: \.element.bundleID) { index, trigger in
                HelmAppRuleRow(bundleID: trigger.bundleID) {
                    Picker(AppInfo.resolve(trigger.bundleID).name,
                           selection: conditionBinding(index)) {
                        ForEach(AppTrigger.Condition.allCases, id: \.self) { condition in
                            Text(KAStr.triggerCondition(condition)).tag(condition)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } remove: {
                    appTriggers.remove(at: index)
                    saveTriggers()
                }
        }
        Button {
            pickApp()
        } label: {
            Label(KAStr.addApp, systemImage: "plus")
        }
    }

    private func conditionBinding(_ index: Int) -> Binding<AppTrigger.Condition> {
        Binding(
            get: { appTriggers.indices.contains(index) ? appTriggers[index].condition : .always },
            set: { newValue in
                guard appTriggers.indices.contains(index) else { return }
                appTriggers[index].set(newValue)
                saveTriggers()
            })
    }

    private func saveTriggers() {
        vm.save(in: store) { $0.setAppTriggers(appTriggers) }
    }

    private func pickApp() {
        var added = false
        for bundleID in AppPicker.choose()
        where !appTriggers.contains(where: { $0.bundleID == bundleID }) {
            appTriggers.append(AppTrigger(bundleID: bundleID))
            added = true
        }
        if added { saveTriggers() }
    }

    // MARK: - Color swatches

    private var colorSwatches: some View {
        HelmPaletteSwatches(selection: activeTintColor) { token in
            activeTintColor = token
            writeLook(token, MenuBarLook.Key.activeTint)
        }
    }

    /// Timer palette: the countdown can stand out from the active colour.
    ///
    /// Both palettes open on orange, which is the same answer twice rather than
    /// a disagreement — the timer's own default used to be red, so the page
    /// showed two rings on two different colours and neither had been chosen.
    /// The `isEmpty` branch survives for a store that answers nothing at all;
    /// it is not a fallback the defaults can reach.
    private var timerColorSwatches: some View {
        HelmPaletteSwatches(selection: timerTintColor.isEmpty ? activeTintColor : timerTintColor) { token in
            timerTintColor = token
            writeLook(token, MenuBarLook.Key.timerTint)
        }
    }
}

/// Records a global-shortcut combo into the module store and notifies the app's
/// HotkeyManager (via `helmHotkeyChanged`) to (re)register it. Capture uses a
/// local key monitor while the settings window is key — no Accessibility needed.
