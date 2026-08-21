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
    // Observed, not held: the state strip reads isActive and the live
    // conditions, and a plain `let` means SwiftUI never hears them change —
    // the figures froze at whatever they were when the page opened.
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
    /// so a mark decided by `binding.wrappedValue` flips in one frame. That was
    /// the last thing on this card still jumping — and it was the *pressed* row,
    /// the one being looked at, whose own tick appeared instantly while its
    /// column slid under it.
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

    init(vm: ModuleViewModel, store: NamespacedStore) {
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
        let live = KeepAwakeViewModel.shared(vm: vm)
        _shownConditions = State(initialValue: live.activeConditions)
        _shownTriggered = State(initialValue: live.triggeredConditions)
        _shownSuppressed = State(initialValue: live.suppressed)
        // The function `enabledRules` reads, not a second copy: the seed spelled
        // the two `insert`s again, and was the half that never learned the
        // hardware.
        _shownEnabled = State(initialValue: MarkableRules.onThisMac(
            autoExternalDisplay: settings.autoExternalDisplay,
            autoPower: settings.autoPower, lidHolding: live.clamshellActive))
        _activeTintColor = State(initialValue: MenuBarLook.activeTint(store))
        _ringTimer = State(initialValue: MenuBarLook.ringTimer(store))
        _showTimerText = State(initialValue: MenuBarLook.showTimerText(store))
        _timerTintColor = State(initialValue: MenuBarLook.timerTint(store))
        _customActiveIcon = State(initialValue: MenuBarLook.customIcon(store))
        _activeIconShape = State(initialValue: MenuBarLook.iconShape(store))
    }

    var body: some View {
        keepAwakeForm
            .helmTracksAccessibility($accessibility)
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
            shortcutSection
        }
        .formStyle(.grouped)
        .helmSettingsColumn()
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
    /// It was `HelmMetricStrip` — «ВЫКЛ · — · 0» before anything is configured.
    /// Two of those three figures are the unreadable kind this house does not
    /// draw at all, and above twenty controls there was not one that could
    /// begin or end a session: the screen whose whole job is to say what is
    /// happening was the only screen that could not change it. Every command
    /// here was already on the wire; the panel tile sends the same ones.
    @ViewBuilder private var sessionHero: some View {
        // A countdown needs a tick of its own: the engine emits state on
        // change, not once a second, so a figure drawn from it froze at
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
                // Resolved here, not in the hero: the hero is rebuilt once a
                // second by its `TimelineView`, and a Launch Services lookup
                // per tick for a string that changes when an app launches is
                // work nobody asked for.
                appNames: vm.holdingApps.map { AppInfo.resolve($0).name },
                // Both defaulted in the hero's initialiser and neither was ever
                // passed, so «Stopped below 20 %» sat in a branch nothing could
                // reach: pressing «15 min» at 5 % was silence here while the panel
                // said why. The floor is the drawn one, so the sentence names the
                // number the row below shows.
                batteryStopped: vm.batteryStopped,
                batteryFloor: batteryGuardPercent,
                timedNote: timedNote,
                start: start,
                stop: { vm.send(KeepAwakeCommand.stop) },
                resume: { vm.send(KeepAwakeCommand.resumeAutomation) })
        }
        // **18 and 12, and neither is what anybody sees.** This block rides on a
        // section header inside a grouped `Form`, which adds 20 pt of its own, so
        // 12 draws as 32 against a page rhythm of 30. Measured on the render at
        // 810 pt, ink to ink because a pill's box reaches past its label: 48 pt of
        // air over the figure, 34 from the buttons down to «Automation». The bottom
        // was 31 — 19 pt more than that, under the tallest block on the page. Of
        // the two steps the ladder offers above, 28 takes the figure's air to 58
        // while the gap below stays 34, and the window has a strip for the traffic
        // lights over that again: it would spend the most air on the page at the
        // very top of it. 18 is the hero's own rhythm as well.
        .padding(.bottom, 12)
        .helmSettingsColumn()
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
    /// it counted the display rule on a desktop, whose row is not drawn and whose
    /// engine refuses it. `.rules`, because the lid is not one.
    private var anyRuleOn: Bool {
        !enabledRules.rules.isEmpty || !appTriggers.isEmpty
    }

    private func start(_ minutes: Int) { vm.start(minutes: minutes) }

    /// Four rules, and every row answers two questions at once: the mark on the
    /// left is what is happening now — a condition off the wire — and the
    /// control on the right is what is configured, out of the store. The second
    /// edition put those 268 pt apart, so a person reading the page saw that a
    /// rule was holding the Mac and could not see what to change about it.
    @ViewBuilder private var automationSection: some View {
        // The hero rides on this section's header.
        //
        // It has to be inside the form to scroll with the page — pinned above
        // it, it held a fifth of the window for a sentence however far down the
        // settings you had gone. But a *row* of a grouped form is drawn inside
        // the section's card, and `listRowBackground(.clear)` does not take
        // that fill away on macOS: measured, the block came back in a card
        // either way. A section **header** is the one part of a grouped form
        // that is drawn on the bare pane and still scrolls, which is exactly
        // the two things this block needs.
        Section(header: heroAndTitle) {
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
            // **The one thing this module does that outlives the process, and no
            // window said so.** `clamshellActive` was published, crossed the wire,
            // and was read by the panel tile's subtitle alone — so this row was
            // nailed to `.spacer`, and somebody who shut the lid saw the switch
            // they had set and nothing of what it was doing.
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
            // has no conditions above it. v3 does not draw this row — the
            // setting was written after the mockup, and here is where it
            // belongs: beside the rules whose end it changes.
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
                // set. The menu it replaces made a *quantity* into a list of
                // words — ten rows of «At 30 % or less» to compare by reading —
                // where the thing being chosen is a point on a scale and reads
                // as one. The floor's own row carries the figure, so the number
                // is on screen without opening anything.
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

    /// Five per cent to fifty, as the stepper this replaced stepped.
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

    private var heroAndTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionHero
            HelmSectionTitle(KAStr.automation)
        }
    }

    /// Which rows of the card can carry a mark — the live answer, read in exactly
    /// one place: the `onChange` that gives it a transaction.
    ///
    /// Every row is indented by the mark column, marked or not, so all of them
    /// have to move on one clock. Three went on reading the live value after the
    /// marked ones moved to the drawn one, and that was worse than no animation:
    /// the row gaining a tick ramped while the three beside it jumped, so the card
    /// came apart down the middle on every press. `MarkColumnHasOneClockTests`
    /// fails on a second reader.
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
        // The four cases live in `RuleNote`, out in the engine's logic where a
        // test can reach them. Written here as nested ternaries there was no
        // room for the fourth — a rule that is on, whose trigger holds, and
        // which is paused — so it read as «Not applying right now» directly
        // under a banner saying it was paused.
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
        Section(header: HelmSectionTitle(KAStr.appsSection)) {
            // A rules string nothing can read answers as «no rules» — safe, the
            // Mac sleeps — and is indistinguishable from having chosen none. One
            // line in the log at launch was the whole account of it.
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
        Section(header: HelmSectionTitle(HelmSectionName.behaviour)) {
            HelmSettingRow(KAStr.keepDisplayOn) {
                Toggle(KAStr.keepDisplayOn, isOn: $keepDisplayOn)
                    .labelsHidden()
                    .onChange(of: keepDisplayOn) { _, v in
                        vm.save(in: store) { $0.setKeepDisplayOn(v) }
                    }
            }
            // The interval means nothing with the switch off, so it shares the
            // row rather than floating below it — and it is a pop-up, because
            // the stepper offered every minute from 1 to 60 for a question with
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
                    Text(KAStr.duration(15)).tag(15)
                    Text(KAStr.oneHour).tag(60)
                    Text(KAStr.twoHours).tag(120)
                    Text(KAStr.indefinite).tag(0)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .onChange(of: defaultDurationMinutes) { _, v in
                    vm.save(in: store) { $0.setDefaultDurationMinutes(v) }
                }
            }
        }
    }

    /// The intervals a pointer nudge is worth asking for; a stored value
    /// outside this list is kept by `HelmChoices`.
    private static let jiggleMinutes = [1, 2, 5, 10, 15, 30, 60]

    /// One section, where there were two.
    ///
    /// «Menu-bar icon» and «Timer» were two headings about one subject — what
    /// the icon looks like — and being two is how the app came to ship two
    /// palettes that disagreed with each other: the active colour ringed on
    /// orange under one heading, the countdown ringed on red under the other,
    /// and no way to see that it was one question asked twice.
    @ViewBuilder private var menuBarIconSection: some View {
        Section(header: HelmSectionTitle(KAStr.menuBarIcon)) {
            HelmSettingRow(KAStr.activeIconColor, note: KAStr.ringColorNote) {
                colorSwatches
            }
            HelmSettingRow(KAStr.customActiveIcon) {
                // Disabled, never absent. Taken away when the switch went off,
                // the row lost its tallest control and became visibly shorter
                // than its neighbours — the card twitched on a setting that had
                // nothing to do with its height. The two paired rows above do
                // it this way too, and the shape you chose stays readable.
                IconShapePicker(selection: $activeIconShape, tintToken: activeTintColor)
                    .labelsHidden()
                    .fixedSize()
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

    // MARK: - Color swatches

    private var colorSwatches: some View {
        HelmPaletteSwatches(KAStr.activeIconColor, selection: activeTintColor) { token in
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
        HelmPaletteSwatches(KAStr.timerColor,
                            selection: timerTintColor.isEmpty ? activeTintColor : timerTintColor) { token in
            timerTintColor = token
            writeLook(token, MenuBarLook.Key.timerTint)
        }
    }
}
