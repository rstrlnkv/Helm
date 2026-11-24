import SwiftUI
import AppKit
import Carbon.HIToolbox
import HelmRuntime
import HelmUI
import Module_KeepAwake_Engine

/// Settings page for the Keep Awake module. The `NamespacedStore` isn't
/// observable, so values are seeded into local `@State` and written through
/// on every change, notifying the engine via `settingsChanged`.
struct KeepAwakeSettingsPage: View {
    // Observed, not held: the hero reads isActive and the live conditions, and
    // a plain `let` means SwiftUI never hears them change.
    @ObservedObject var vm: KeepAwakeViewModel
    let store: NamespacedStore

    @State private var accessibility: PermissionState = .granted
    @State private var autoExternalDisplay: Bool
    @State private var autoPower: Bool
    /// Internal, not private: the app-rules editor reads and writes it from
    /// `KeepAwakeAppRules.swift`, and an extension in another file of the same
    /// module sees `internal` and not `private`.
    @State var appTriggers: [AppTrigger]

    @State private var keepDisplayOn: Bool
    @State private var jiggleEnabled: Bool
    @State private var jiggleIntervalMinutes: Int
    @State private var defaultDurationMinutes: Int

    @State private var clamshellEnabled: Bool
    @State private var timerEndsAutomation: Bool

    @State private var batteryGuardEnabled: Bool
    @State private var batteryGuardPercent: Int

    /// What the rule rows are **drawn** from, as against what is true.
    ///
    /// Every one of these arrives from the engine with no transaction, so it
    /// lands in this view's own state inside `withAnimation`, and the rows read
    /// only these (Architecture/DesignSystem.md § Motion). Seeded from the view
    /// model, so a page opened while a rule holds shows the tick rather than
    /// playing it arriving.
    @State private var shownConditions: Set<ActiveCondition>
    @State private var shownTriggered: Set<ActiveCondition>
    @State private var shownSuppressed: Bool
    /// Which rows of the automation card are **drawn** as carrying a mark.
    ///
    /// Press-driven, and it needs the same treatment: a `Toggle` writes its
    /// binding outside any animation, so a mark decided by
    /// `binding.wrappedValue` would flip in one frame on the pressed row while
    /// its column slid under it.
    ///
    /// The switch itself keeps the live binding; what waits for the curve is
    /// what the row says, not what it does. A `MarkableRules`, because the lid
    /// row carries a mark too: one value for the whole column.
    @State private var shownEnabled: MarkableRules

    @State private var activeTintColor: String
    @State private var ringTimer: Bool
    @State private var showTimerText: Bool
    @State private var timerTintColor: String
    @State private var customActiveIcon: Bool
    @State private var activeIconShape: String
    @StateObject private var recorder: HelmHotkeyRecorder

    init(vm: KeepAwakeViewModel, store: NamespacedStore) {
        self.vm = vm
        self.store = store
        _recorder = StateObject(wrappedValue: HelmHotkeyRecorder(store: store, prefix: KeepAwakeHotkey.storePrefix))
        // Every one of these through the settings struct, not a second literal,
        // so the page draws the engine's defaults and clamps (the battery guard
        // is on by default).
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
        _shownConditions = State(initialValue: vm.activeConditions)
        _shownTriggered = State(initialValue: vm.triggeredConditions)
        _shownSuppressed = State(initialValue: vm.suppressed)
        // The function `enabledRules` reads, not a second copy: a copy of the
        // two `insert`s would be the half that never learns the hardware.
        _shownEnabled = State(initialValue: MarkableRules.onThisMac(
            autoExternalDisplay: settings.autoExternalDisplay,
            autoPower: settings.autoPower, lidHolding: vm.clamshellActive))
        _activeTintColor = State(initialValue: MenuBarLook.activeTint(store))
        _ringTimer = State(initialValue: MenuBarLook.ringTimer(store))
        _showTimerText = State(initialValue: MenuBarLook.showTimerText(store))
        _timerTintColor = State(initialValue: MenuBarLook.timerTint(store))
        _customActiveIcon = State(initialValue: MenuBarLook.customIcon(store))
        _activeIconShape = State(initialValue: MenuBarLook.iconShape(store))
    }

    var body: some View {
        keepAwakePage
            .helmTracksAccessibility($accessibility)
    }

    /// The hero and five sections, each its own fragment, for the reader and
    /// for SwiftUI's type-checker. Each is a direct child of the stack. The
    /// column's padding and cap sit on the stack inside the scroller (a cap on
    /// the scroller leaves dead sides, `HelmLayout.swift`); every modifier after
    /// the `ScrollView` stays on it, including the store observer that keeps
    /// this page and the panel agreeing.
    ///
    /// The hero is the stack's first child so that it scrolls with the page
    /// rather than holding a fifth of the window however far down somebody is.
    private var keepAwakePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpace.s7) {
                sessionHero
                automationSection
                appsSection
                behaviourSection
                menuBarIconSection
                shortcutSection
            }
            .padding(.horizontal, HelmLayout.formInset)
            .padding(.vertical, HelmSpace.s6)
            // Caps the column, centres it, and idles the page while its window
            // is off screen.
            .helmSettingsColumn()
        }
        // Where the engine's values land, and the only place they are animated.
        .onChange(of: vm.activeConditions) { _, arrived in
            withAnimation(HelmMotion.disclosure) { shownConditions = arrived }
        }
        .onChange(of: vm.triggeredConditions) { _, arrived in
            withAnimation(HelmMotion.disclosure) { shownTriggered = arrived }
        }
        .onChange(of: vm.suppressed) { _, silenced in
            withAnimation(HelmMotion.disclosure) { shownSuppressed = silenced }
        }
        // …and where the press does. One set for both switches, so the two
        // rules and the column they share cannot be given three clocks.
        .onChange(of: enabledRules) { _, enabled in
            withAnimation(HelmMotion.disclosure) { shownEnabled = enabled }
        }
        // The panel's ⋯ block writes the same keys; without this the page shows
        // stale values when both are open.
        .keepAwakeAutomationMirror(store, externalDisplay: $autoExternalDisplay,
                                   power: $autoPower)
    }

    // MARK: - The sections

    /// What is happening, and the verbs for it.
    ///
    /// Every command here is one the panel tile sends too: the page that says
    /// what is happening is also the one that can begin or end a session.
    @ViewBuilder private var sessionHero: some View {
        // A countdown needs a tick of its own: the engine emits state on
        // change, not once a second. The tick goes into the hero rather than
        // being read off the clock inside it, so the figure is a function of it.
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            KeepAwakeHero(
                state: SessionHero.of(isActive: vm.isActive, endDate: vm.endDate,
                                      conditions: vm.activeConditions, now: timeline.date),
                now: timeline.date,
                anyRuleOn: anyRuleOn,
                defaultDurationMinutes: defaultDurationMinutes,
                notice: vm.notice,
                ruleHolds: vm.ruleHolds,
                // The switch in the Automation card, because the same setting decides
                // what pressing Stop does — see `StopPress`. The mirrored
                // `@State`, so a change made on this page reaches the button on
                // the same frame it reaches the row.
                timerEndsAutomation: timerEndsAutomation,
                // Resolved here, not in the hero, which is rebuilt once a
                // second: a Launch Services lookup per tick is wasted work.
                appNames: vm.holdingApps.map { AppInfo.resolve($0).name },
                // Both are passed, or the battery notice sits in a branch
                // nothing can reach. The floor is the drawn one, so the sentence
                // names the number the row below shows.
                batteryFloor: batteryGuardPercent,
                timedNote: timedNote,
                start: { vm.start(minutes: $0) },
                stop: { vm.stopSession() },
                resume: { vm.resumeAutomation() })
        }
    }

    /// «Таймер до 15:42 · дальше держит внешний дисплей». The second clause is
    /// the only answer on the page to what happens at zero.
    private func timedNote(_ end: Date) -> String {
        let until = KAStr.timerUntil(end)
        let after = SessionHero.afterTimer(conditions: vm.activeConditions,
                                           timerEndsAutomation: timerEndsAutomation)
        switch after {
        case .nothing: return until
        case .heldBy(let condition): return until + " · " + KAStr.thenHeldBy(condition)
        case .rulePaused: return until + " · " + KAStr.thenRulePaused
        }
    }

    /// True when anything is configured that could hold the Mac: the difference
    /// between «nothing is set up» and «nothing applies now». Through
    /// `enabledRules`, so the hardware is in the answer
    /// (Architecture/KeepAwake.md § Rules read from the machine). `.rules`,
    /// because the lid is not one.
    private var anyRuleOn: Bool {
        !enabledRules.rules.isEmpty || !appTriggers.isEmpty
    }

    /// Four rules, and every row answers two questions at once: the mark on the
    /// left is what is happening now — a condition from the engine — and the
    /// control on the right is what is configured, out of the store. Kept close
    /// together, so a person who sees that a rule is holding the Mac sees what to
    /// change about it.
    @ViewBuilder private var automationSection: some View {
        HelmSettingsSection(KAStr.automation) {
            // Hidden on a Mac that has no lid: every display of a mini or a
            // Studio is external, so the rule would mean «never sleep».
            //
            // The hardware, not the current display list: a laptop with the lid
            // shut reports only external displays too, and hiding the rule on
            // that evidence would take it away exactly when somebody docked.
            if MacHardware.hasLid {
                ruleRow(KAStr.condition(.externalDisplay), on: $autoExternalDisplay,
                        satisfiedBy: .externalDisplay) { v in
                    vm.save(in: store) { $0.setAutoExternalDisplay(v) }
                }
            }
            ruleRow(KAStr.onPower, on: $autoPower, satisfiedBy: .power) { v in
                vm.save(in: store) { $0.setAutoPower(v) }
            }
            // The one thing this module does that outlives the process. The row
            // reads `clamshellActive`, as the panel's subtitle does, so somebody
            // who shut the lid sees what the switch is doing.
            //
            // `.holding` or nothing, no `.waiting`: the switch on with the lid
            // open is what the control already says. No lid, no row: this writes
            // a passwordless sudo rule into `/etc/sudoers.d`, which must not be
            // offered for a feature that can do nothing.
            if MacHardware.hasLid {
                // Four sentences, and `LidRowNote` says which. The note reads the
                // live values while the mark reads the drawn one: a mark shares the
                // column's clock (`enabledRules`), a sentence has no column.
                HelmSettingRow(KAStr.keepAwakeLidClosed,
                               note: KAStr.lidNote(vm.lidRowNote),
                               // The row keeps what the decision needs; the ⓘ
                               // beside the name holds what follows from it
                               // (`HelmExplainer`).
                               explainer: KAStr.lidExplainer(vm.lidRowNote),
                               mark: shownEnabled.lidHolding
                                   ? .holding
                                   : .spacer(inCardWithMarks: shownMarksPossible)) {
                    savingSwitch(KAStr.keepAwakeLidClosed, $clamshellEnabled) { vm.lidSwitchTurned($0) }
                }
            }

            // Between the conditions and the guard that ends a session: it is
            // about the end of one too, and belongs beside the rules whose end
            // it changes.
            HelmSettingRow(KAStr.timerEndsAutomation, note: KAStr.timerEndsAutomationNote,
                           mark: .spacer(inCardWithMarks: shownMarksPossible)) {
                savingSwitch(KAStr.timerEndsAutomation, $timerEndsAutomation) { v in
                    vm.save(in: store) { $0.setTimerEndsAutomation(v) }
                }
            }
            // The threshold and the switch on one row — a level means nothing with
            // the guard off, and the control is disabled rather than hidden so the
            // number you set is still the number you see. Not drawn at all on a
            // Mac with no battery for the guard to watch.
            if MacHardware.hasBattery {
                // A slider with stops, the way Battery's own charge limit is
                // set: the thing chosen is a point on a scale, not a list of
                // words. The floor's own row carries the figure.
                HelmSettingRow(KAStr.turnOffLowBattery,
                               note: batteryGuardEnabled ? KAStr.belowPercent(batteryGuardPercent)
                                                         : nil,
                               mark: .spacer(inCardWithMarks: shownMarksPossible)) {
                    Slider(value: batteryPercentBinding,
                           in: Double(Self.batteryFloorRange.lowerBound)
                               ... Double(Self.batteryFloorRange.upperBound),
                           step: Double(Self.batteryFloorStep))
                        // Wide enough for ten stops to be aimed at rather than
                        // dragged past, and no wider: the row still has a
                        // switch at its end.
                        .frame(width: 160)
                        .labelsHidden()
                        .disabled(!batteryGuardEnabled)
                        .accessibilityLabel(KAStr.turnOffLowBattery)
                        .accessibilityValue(KAStr.belowPercent(batteryGuardPercent))
                    savingSwitch(KAStr.turnOffLowBattery, $batteryGuardEnabled) { v in
                        vm.save(in: store) { $0.setBatteryGuardEnabled(v) }
                    }
                }
            }
        }
    }

    /// The floor, as a range with a step rather than a list of choices.
    ///
    /// Five to fifty in fives: below five the guard cannot act before the Mac
    /// does, and above fifty it is not a low-battery guard any more. The step
    /// is what makes the slider land on the numbers a person would have picked
    /// from a menu.
    private static let batteryFloorRange = 5...50
    private static let batteryFloorStep = 5

    /// `Slider` speaks `Double`; the setting is an `Int` and everything that
    /// reads it — the engine's guard, the note beside the control — wants it
    /// that way. Rounded rather than truncated, so a drag that lands a hair
    /// under a stop does not step down one.
    private var batteryPercentBinding: Binding<Double> {
        Binding(get: { Double(batteryGuardPercent) },
                set: { new in
                    let rounded = Int(new.rounded())
                    guard rounded != batteryGuardPercent else { return }
                    batteryGuardPercent = rounded
                    vm.save(in: store) { $0.setBatteryGuardPercent(rounded) }
                })
    }

    /// Which rows of the card can carry a mark — the live answer, read in exactly
    /// one place: the `onChange` that gives it a transaction.
    ///
    /// Every row is indented by the mark column, marked or not, so all of them
    /// move on one clock; a row reading the live value while its neighbours read
    /// the drawn one would make the card come apart on every press.
    ///
    /// The two rules and the lid can be marked; the timer setting and the battery
    /// guard never are. With none of them countable the column is not drawn at
    /// all: an indent against nobody reads as icons that failed to load. Which
    /// rows count is `MarkableRules`, hardware included.
    private var enabledRules: MarkableRules {
        MarkableRules.onThisMac(autoExternalDisplay: autoExternalDisplay,
                                autoPower: autoPower, lidHolding: vm.clamshellActive)
    }

    /// The column's own question, asked of the drawn set: a second `@State`
    /// for the column could disagree with the marks it makes room for.
    private var shownMarksPossible: Bool { !shownEnabled.isEmpty }

    /// A rule the engine can report on: the mark comes from `activeConditions`,
    /// the switch from the store, and the note from the two together.
    @ViewBuilder
    private func ruleRow(_ title: String, on binding: Binding<Bool>,
                         satisfiedBy condition: ActiveCondition,
                         save: @escaping (Bool) -> Void) -> some View {
        // Drawn, not live: `binding.wrappedValue` is what the switch says this
        // instant, and a mark decided by it appears in one frame under a column
        // that is still sliding.
        let enabled = shownEnabled.contains(condition)
        let satisfied = shownConditions.contains(condition)
        // The cases live in `RuleNote`, in the engine's logic, including a rule
        // that is on, whose trigger holds, and which is paused.
        let note = RuleNote.of(enabled: enabled, satisfied: satisfied,
                               batteryStopped: vm.batteryStopped,
                               suppressed: shownSuppressed,
                               triggerHolds: shownTriggered.contains(condition))
        HelmSettingRow(title,
                       note: KAStr.ruleNote(note, condition, batteryFloor: batteryGuardPercent),
                       mark: .of(enabled: enabled, satisfied: satisfied,
                                 inCardWithMarks: shownMarksPossible)) {
            savingSwitch(title, binding, save)
        }
    }

    /// A switch that writes on the edge the person made, not on every redraw.
    private func savingSwitch(_ title: String, _ on: Binding<Bool>,
                              _ save: @escaping (Bool) -> Void) -> some View {
        Toggle(title, isOn: on)
            .labelsHidden()
            .onChange(of: on.wrappedValue) { _, v in save(v) }
    }

    @ViewBuilder private var appsSection: some View {
        HelmSettingsSection(HelmWord.apps) {
            // A rules string nothing can read answers as «no rules» — safe, the
            // Mac sleeps — and is indistinguishable from having chosen none, so
            // the page says it.
            //
            // Asked of the store on every pass rather than mirrored into `@State`:
            // the way out of this state is adding an app, which rewrites the string
            // through `setAppTriggers`, so the answer has to be the file's own.
            let unreadable = KeepAwakeSettings(store: store).appRulesUnreadable
            if unreadable {
                HelmBanner(KAStr.appRulesUnreadable)
            }
            appRules(explained: !unreadable)
        }
    }

    @ViewBuilder private var behaviourSection: some View {
        HelmSettingsSection(HelmSectionName.behaviour) {
            HelmSettingRow(KAStr.keepDisplayOn) {
                savingSwitch(KAStr.keepDisplayOn, $keepDisplayOn) { v in
                    vm.save(in: store) { $0.setKeepDisplayOn(v) }
                }
            }
            // The interval means nothing with the switch off, so it shares the
            // row. A pop-up, because a stepper over every minute from 1 to 60 is
            // a question with about seven answers.
            HelmSettingRow(KAStr.movePointer, note: KAStr.movePointerNote) {
                Picker(KAStr.movePointer, selection: $jiggleIntervalMinutes) {
                    ForEach(HelmChoices.including(jiggleIntervalMinutes, in: Self.jiggleMinutes),
                            id: \.self) { minutes in
                        Text(KAStr.everyMinutes(minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .helmSectionMenu()
                .disabled(!jiggleEnabled)
                .onChange(of: jiggleIntervalMinutes) { _, v in
                    vm.save(in: store) { $0.setJiggleIntervalMinutes(v) }
                }
                savingSwitch(KAStr.movePointer, $jiggleEnabled) { v in
                    vm.save(in: store) { $0.setJiggleEnabled(v) }
                }
            }
            // macOS drops synthetic mouse events from an untrusted app, so
            // without this grant the switch above is on and nothing moves.
            // Said where the switch is, not only in the app's settings.
            if jiggleEnabled, accessibility == .denied {
                HelmPermissionNote(need: .accessibility,
                                   text: KAStr.pointerNeedsAccessibility)
            }
            HelmSettingRow(KAStr.defaultDuration, note: KAStr.defaultDurationNote) {
                Picker(KAStr.defaultDuration, selection: $defaultDurationMinutes) {
                    ForEach(Self.durationChoices(including: defaultDurationMinutes),
                            id: \.self) { minutes in
                        Text(Self.durationLabel(minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .helmSectionMenu()
                .onChange(of: defaultDurationMinutes) { _, v in
                    vm.save(in: store) { $0.setDefaultDurationMinutes(v) }
                }
            }
        }
    }

    /// The timed lengths in order, a stored length off the list among them,
    /// «Indefinite» (0) last: `HelmChoices.including` alone would sort 0 to the
    /// top, and the setting holds anything from 0 to a day.
    private static func durationChoices(including stored: Int) -> [Int] {
        let timed = [15, 60, 120]
        return (stored == 0 ? timed : HelmChoices.including(stored, in: timed)) + [0]
    }

    private static func durationLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: KAStr.indefinite
        case 60: KAStr.oneHour
        case 120: KAStr.twoHours
        default: KAStr.duration(minutes)
        }
    }

    /// The intervals a pointer nudge is worth asking for; a stored value
    /// outside this list is kept by `HelmChoices`.
    private static let jiggleMinutes = [1, 2, 5, 10, 15, 30, 60]

    /// «Menu-bar icon» and «Timer» are one section because they are one
    /// question — what the icon looks like — and two headings would let the
    /// active colour and the countdown's disagree unseen.
    @ViewBuilder private var menuBarIconSection: some View {
        HelmSettingsSection(KAStr.menuBarIcon) {
            HelmSettingRow(KAStr.activeIconColor, note: KAStr.ringColorNote) {
                colorSwatches
            }
            HelmSettingRow(KAStr.customActiveIcon) {
                // Disabled, never absent: taken away, the row would lose its
                // tallest control and the card would twitch. The shape you chose
                // stays readable.
                IconShapePicker(selection: $activeIconShape, tintToken: activeTintColor)
                    .labelsHidden()
                    .fixedSize()
                    .helmSectionMenu()
                    .disabled(!customActiveIcon)
                    .onChange(of: activeIconShape) { _, v in
                        writeLook(v, MenuBarLook.Key.iconShape)
                    }
                savingSwitch(KAStr.customActiveIcon, $customActiveIcon) { v in writeLook(v, MenuBarLook.Key.customIcon) }
            }
            HelmSettingRow(KAStr.ringTimer, note: KAStr.ringTimerNote) {
                savingSwitch(KAStr.ringTimer, $ringTimer) { v in writeLook(v, MenuBarLook.Key.ringTimer) }
            }
            HelmSettingRow(KAStr.showTimerText) {
                savingSwitch(KAStr.showTimerText, $showTimerText) { v in writeLook(v, MenuBarLook.Key.showTimerText) }
            }
            HelmSettingRow(KAStr.timerColor, note: KAStr.timerColorNote) {
                timerColorSwatches
            }
        }
    }

    @ViewBuilder private var shortcutSection: some View {
        HelmSettingsSection(KAStr.globalShortcut) {
            HelmHotkeyRow(KAStr.toggleAction, recorder: recorder,
                          taken: HotkeyStatus.isTaken(KeepAwakeHotkey.toggle))
        }
    }

    // MARK: - Write-through

    /// The menu-bar look only, whose keys `MenuBarLook` owns and the engine never
    /// reads. Everything the engine acts on goes through `vm.save(in:)` instead,
    /// which spells no key at all.
    private func writeLook(_ value: Any?, _ key: String) {
        store.set(value, for: key)
        vm.settingsChanged()
    }

    // MARK: - Color swatches

    private var colorSwatches: some View {
        HelmPaletteSwatches(KAStr.activeIconColor, selection: activeTintColor) { token in
            activeTintColor = token
            writeLook(token, MenuBarLook.Key.activeTint)
        }
        .helmSectionMenu()
    }

    /// Timer palette: the countdown can stand out from the active colour.
    ///
    /// Both palettes open on orange: two rings on two different colours,
    /// neither chosen, would read as a fault. The `isEmpty` branch is reached
    /// only by an empty string in the store, which Helm never writes; a store
    /// that answers nothing gives the default.
    private var timerColorSwatches: some View {
        HelmPaletteSwatches(KAStr.timerColor,
                            selection: timerTintColor.isEmpty ? activeTintColor : timerTintColor) { token in
            timerTintColor = token
            writeLook(token, MenuBarLook.Key.timerTint)
        }
        .helmSectionMenu()
    }
}
