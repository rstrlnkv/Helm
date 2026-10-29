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
    /// Every one of these arrives from the engine over the wire, and law 2 of
    /// this house's motion notes is that a value handed over from outside
    /// carries no transaction with it: `.animation(_:value:)` on the row would
    /// be measured indistinguishable from no animation at all. So the arriving
    /// value lands in state of this view's own, written inside `withAnimation`
    /// where it lands, and the rows read only these. Seeded from the view model
    /// rather than from a constant — a page opened while a rule is already
    /// holding must show the tick, not play it arriving.
    @State private var shownConditions: Set<ActiveCondition>
    @State private var shownTriggered: Set<ActiveCondition>
    @State private var shownSuppressed: Bool
    /// Which rows of the automation card are **drawn** as carrying a mark.
    ///
    /// Press-driven rather than engine-driven, and it needs the same treatment
    /// for the same reason: a `Toggle` writes its binding outside any animation,
    /// so a mark decided by `binding.wrappedValue` flips in one frame — and it
    /// would be the *pressed* row, the one being looked at, whose own tick
    /// appeared instantly while its column slid under it.
    ///
    /// The switch itself keeps the live binding: one that lagged behind the finger
    /// would be a worse fault than this. What waits for the curve is what the row
    /// *says*, not what it does. A `MarkableRules` and not a set of conditions,
    /// because the lid row carries a mark too — one value for the whole column.
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

    /// The hero and five sections, each its own fragment: one expression of
    /// all of them is more than anyone can hold at once and more than SwiftUI's
    /// type-checker enjoys. Each is one `HelmSettingsSection` (or the hero), a
    /// direct child of the stack. The column's padding and cap sit on the stack
    /// inside the scroller (a cap on the scroller leaves dead sides,
    /// `HelmLayout.swift`); every modifier after the `ScrollView` stays on it,
    /// including the store observer that keeps this page and the panel agreeing.
    ///
    /// The hero is the stack's first child so that it scrolls with the page:
    /// pinned above it, it would hold a fifth of the window for a sentence however
    /// far down the settings somebody has scrolled.
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
        // stale values when both are open (the reverse direction already works).
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
        // change, not once a second, so a figure drawn from it would freeze at
        // whatever it read when the page opened. The panel tile solves it the
        // same way. The tick goes *into* the hero rather than being read off
        // the clock inside it, so the figure is a function of the tick.
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            KeepAwakeHero(
                state: SessionHero.of(isActive: vm.isActive, endDate: vm.endDate,
                                      conditions: vm.activeConditions, now: timeline.date),
                now: timeline.date,
                anyRuleOn: anyRuleOn,
                defaultDurationMinutes: defaultDurationMinutes,
                suppressed: vm.suppressed,
                ruleHolds: vm.ruleHolds,
                // The switch in the Automation card, because the same setting decides
                // what pressing Stop does — see `StopPress`. The mirrored
                // `@State`, so a change made on this page reaches the button on
                // the same frame it reaches the row.
                timerEndsAutomation: timerEndsAutomation,
                // Resolved here, not in the hero: the hero is rebuilt once a
                // second by its `TimelineView`, and a Launch Services lookup
                // per tick for a string that changes when an app launches is
                // work nobody asked for.
                appNames: vm.holdingApps.map { AppInfo.resolve($0).name },
                // Both are passed, or «Stopped below 20 %» sits in a branch
                // nothing can reach: pressing «15 min» at 5 % would be silence
                // here while the panel said why. The floor is the drawn one, so
                // the sentence names the number the row below shows.
                batteryStopped: vm.batteryStopped,
                batteryFloor: batteryGuardPercent,
                timedNote: timedNote,
                start: start,
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

    /// True when anything is configured that *could* hold the Mac — which is
    /// the difference between «nothing is set up» and «nothing applies now».
    /// Through `enabledRules`, so the hardware is in the answer: off the raw flags
    /// it would count the display rule on a desktop, whose row is not drawn and
    /// whose engine refuses it. `.rules`, because the lid is not one.
    private var anyRuleOn: Bool {
        !enabledRules.rules.isEmpty || !appTriggers.isEmpty
    }

    private func start(_ minutes: Int) { vm.start(minutes: minutes) }

    /// Four rules, and every row answers two questions at once: the mark on the
    /// left is what is happening now — a condition off the wire — and the
    /// control on the right is what is configured, out of the store. Kept close
    /// together, so a person who sees that a rule is holding the Mac sees what to
    /// change about it.
    @ViewBuilder private var automationSection: some View {
        HelmSettingsSection(KAStr.automation) {
            // Hidden on a Mac that has no display of its own. «Keep awake with
            // an external display» is a rule about being docked, and a mini or
            // a Studio has no notion of docked: every display it has is
            // external, so the rule is unconditionally true there and amounts
            // to «never sleep» — while the row cheerfully reports it applying.
            //
            // The hardware, not the current display list: a laptop with the lid
            // shut reports only external displays too, and hiding the rule on
            // that evidence would take it away exactly when somebody docked.
            if MacHardware.hasBuiltInDisplay {
                ruleRow(KAStr.condition(.externalDisplay), on: $autoExternalDisplay,
                        satisfiedBy: .externalDisplay) { v in
                    vm.save(in: store) { $0.setAutoExternalDisplay(v) }
                }
            }
            ruleRow(KAStr.onPower, on: $autoPower, satisfiedBy: .power) { v in
                vm.save(in: store) { $0.setAutoPower(v) }
            }
            // **The one thing this module does that outlives the process.**
            // `clamshellActive` crosses the wire and the panel tile's subtitle
            // reads it; this row reads it too, so somebody who shut the lid sees
            // what the switch they set is doing and not only the switch.
            //
            // `.holding` or nothing, and no `.waiting` between: the switch on with
            // the lid open is what the control says, and a clock there would be the
            // row reporting the setting twice. No lid, no row — this is what writes
            // a passwordless sudo rule into `/etc/sudoers.d`, so drawing it where it
            // can do nothing offers a permanent grant for an unusable feature.
            if MacHardware.hasLid {
                // Four sentences, and `LidRowNote` says which. The note reads the
                // live values while the mark reads the drawn one: a mark shares the
                // column's clock (`enabledRules`), a sentence has no column.
                HelmSettingRow(KAStr.keepAwakeLidClosed,
                               note: KAStr.lidNote(vm.lidRowNote),
                               // What a passwordless `sudo pmset` rule costs is
                               // four sentences, and four sentences under a
                               // switch is a wall (`HelmExplainer`). The row
                               // keeps what the decision needs; the ⓘ beside the
                               // name holds what follows from it.
                               explainer: KAStr.lidExplainer(vm.lidRowNote),
                               mark: shownEnabled.lidHolding
                                   ? .holding
                                   : .spacer(inCardWithMarks: shownMarksPossible)) {
                    Toggle(KAStr.keepAwakeLidClosed, isOn: $clamshellEnabled)
                        .labelsHidden()
                        .onChange(of: clamshellEnabled) { _, v in
                            vm.save(in: store) { $0.setClamshellEnabled(v) }
                        }
                }
            }

            // Between the conditions and the guard that ends a session: this is
            // about the end of one too, and it means nothing to somebody who
            // has no conditions above it. It belongs beside the rules whose end
            // it changes.
            HelmSettingRow(KAStr.timerEndsAutomation, note: KAStr.timerEndsAutomationNote,
                           mark: .spacer(inCardWithMarks: shownMarksPossible)) {
                Toggle(KAStr.timerEndsAutomation, isOn: $timerEndsAutomation)
                    .labelsHidden()
                    .onChange(of: timerEndsAutomation) { _, v in
                        vm.save(in: store) { $0.setTimerEndsAutomation(v) }
                    }
            }
            // The threshold and the switch on one row — a level means nothing with
            // the guard off, and the control is disabled rather than hidden so the
            // number you set is still the number you see. Not drawn at all on a
            // Mac with no battery for the guard to watch.
            if MacHardware.hasBattery {
                // A slider with stops, the way Battery's own charge limit is
                // set. A menu would make a *quantity* into a list of words — ten
                // rows of «At 30 % or less» to compare by reading — where the
                // thing being chosen is a point on a scale and reads as one. The
                // floor's own row carries the figure, so the number is on screen
                // without opening anything.
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
                    Toggle(KAStr.turnOffLowBattery, isOn: $batteryGuardEnabled)
                        .labelsHidden()
                        .onChange(of: batteryGuardEnabled) { _, v in
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
    /// have to move on one clock. A row reading the live value while the marked
    /// ones read the drawn one is worse than no animation: the row gaining a tick
    /// ramps while the rows beside it jump, so the card comes apart down the
    /// middle on every press.
    ///
    /// The two rules and the lid can be marked; the timer setting and the battery
    /// guard never are. With none of them countable the column is not drawn at
    /// all — 14 pt of indent against nobody reads as icons that failed to load,
    /// and it is the state a fresh install opens in. Which rows count is
    /// `MarkableRules`, hardware included.
    private var enabledRules: MarkableRules {
        MarkableRules.onThisMac(autoExternalDisplay: autoExternalDisplay,
                                autoPower: autoPower, lidHolding: vm.clamshellActive)
    }

    /// The column's own question, asked of the *drawn* set. One value behind
    /// both — a second `@State` for the column could disagree with the marks
    /// it makes room for, which is three clocks again by another route.
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
        // The four cases live in `RuleNote`, out in the engine's logic. Nested
        // ternaries here have no room for the fourth — a rule that is on, whose
        // trigger holds, and which is paused — and would read «Not applying
        // right now» directly under a banner saying it was paused.
        let note = RuleNote.of(enabled: enabled, satisfied: satisfied,
                               batteryStopped: vm.batteryStopped,
                               suppressed: shownSuppressed,
                               triggerHolds: shownTriggered.contains(condition))
        HelmSettingRow(title,
                       note: KAStr.ruleNote(note, condition, batteryFloor: batteryGuardPercent),
                       mark: .of(enabled: enabled, satisfied: satisfied,
                                 inCardWithMarks: shownMarksPossible)) {
            Toggle(title, isOn: binding)
                .labelsHidden()
                .onChange(of: binding.wrappedValue) { _, v in save(v) }
        }
    }

    @ViewBuilder private var appsSection: some View {
        HelmSettingsSection(KAStr.appsSection) {
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
                Toggle(KAStr.keepDisplayOn, isOn: $keepDisplayOn)
                    .labelsHidden()
                    .onChange(of: keepDisplayOn) { _, v in
                        vm.save(in: store) { $0.setKeepDisplayOn(v) }
                    }
            }
            // The interval means nothing with the switch off, so it shares the
            // row rather than floating below it — and it is a pop-up, because
            // a stepper over every minute from 1 to 60 is a question with
            // about seven answers.
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
                Toggle(KAStr.movePointer, isOn: $jiggleEnabled)
                    .labelsHidden()
                    .onChange(of: jiggleEnabled) { _, v in
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
                // Disabled, never absent. Taken away when the switch goes off,
                // the row would lose its tallest control and become visibly
                // shorter than its neighbours — the card would twitch on a
                // setting that has nothing to do with its height. The two paired
                // rows above do it this way too, and the shape you chose stays
                // readable.
                IconShapePicker(selection: $activeIconShape, tintToken: activeTintColor)
                    .labelsHidden()
                    .fixedSize()
                    .helmSectionMenu()
                    .disabled(!customActiveIcon)
                    .onChange(of: activeIconShape) { _, v in
                        writeLook(v, MenuBarLook.Key.iconShape)
                    }
                Toggle(KAStr.customActiveIcon, isOn: $customActiveIcon)
                    .labelsHidden()
                    .onChange(of: customActiveIcon) { _, v in
                        writeLook(v, MenuBarLook.Key.customIcon)
                    }
            }
            HelmSettingRow(KAStr.ringTimer, note: KAStr.ringTimerNote) {
                Toggle(KAStr.ringTimer, isOn: $ringTimer)
                    .labelsHidden()
                    .onChange(of: ringTimer) { _, v in writeLook(v, MenuBarLook.Key.ringTimer) }
            }
            HelmSettingRow(KAStr.showTimerText) {
                Toggle(KAStr.showTimerText, isOn: $showTimerText)
                    .labelsHidden()
                    .onChange(of: showTimerText) { _, v in
                        writeLook(v, MenuBarLook.Key.showTimerText)
                    }
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
    /// Both palettes open on orange, which is the same answer twice rather than
    /// a disagreement: two rings on two different colours, neither chosen, would
    /// read as a fault. The `isEmpty` branch is for a store that answers nothing
    /// at all; it is not a fallback the defaults can reach.
    private var timerColorSwatches: some View {
        HelmPaletteSwatches(KAStr.timerColor,
                            selection: timerTintColor.isEmpty ? activeTintColor : timerTintColor) { token in
            timerTintColor = token
            writeLook(token, MenuBarLook.Key.timerTint)
        }
        .helmSectionMenu()
    }
}
