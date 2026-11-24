import SwiftUI
import HelmUI
import Module_KeepAwake_Engine

/// The top of the Keep Awake page: what is happening, and the verbs for it.
///
/// A view of its own rather than two members of the settings page, so that its
/// motion can be hosted in a window and measured without a store or an engine.
///
/// A cross-fade and not a reveal, because nothing is being revealed: the four
/// states are different views, with no shared figure to interpolate between a
/// sentence and a countdown. Growing would play the old block closing and the
/// new one opening, two beats for a one-beat change.
///
/// The block's measured height is animated as well, on the same curve:
/// `.indefinite` is a line shorter than `.timed` and `.automatic` a caption
/// taller, and nothing else moves the cards beneath it. The clip needs that
/// animating frame: a departing view is not inside the bounds a bare
/// `.clipped()` is taken from, so without it the outgoing caption draws over
/// the cards below for a few frames.
///
/// The state arrives from the engine, so there is no press to wrap in
/// `withAnimation`, and `.animation(_:value:)` carries neither a transition nor
/// a layout change. The value lands in this view's own state inside a
/// transaction, and everything drawn reads that
/// (Architecture/DesignSystem.md § Motion).
struct KeepAwakeHero: View {
    let state: SessionHero
    /// The tick the figure is drawn from, taken from the page's `TimelineView`
    /// rather than read off the clock inside the body: a body re-run for any
    /// other reason then redraws the same digits instead of firing the numeric
    /// transition at a random moment.
    let now: Date
    let anyRuleOn: Bool
    let defaultDurationMinutes: Int
    /// What the slot under the buttons says: the battery guard, a paused rule or
    /// nothing — the view model's `notice`.
    let notice: KeepAwakeNotice
    /// A rule's trigger is true right now, whatever state the figure is in.
    /// The view model's `ruleHolds`, which is the input `StopPress` weighs when
    /// it decides whether Stop silences the rule as well as ending the session.
    let ruleHolds: Bool
    /// «The timer pauses the automation rules when it finishes», the setting.
    /// The button's word depends on it: `StopPress` has the reasoning, and this
    /// block and the engine both spell the decision from it.
    let timerEndsAutomation: Bool
    /// The battery guard is holding everything down. When it is, it is the
    /// only thing worth saying: a paused rule is a detail beside «nothing this
    /// module does will run until you plug in».
    private var batteryStopped: Bool { notice == .battery }
    /// The floor it stopped at, for the sentence.
    let batteryFloor: Int
    /// The names of the apps holding the Mac, already resolved. The hero is
    /// handed words rather than bundle ids: turning one into the other is a
    /// Launch Services lookup, and a view redrawn once a second is the wrong
    /// place for it.
    let appNames: [String]
    let timedNote: (Date) -> String
    let start: (Int) -> Void
    let stop: () -> Void
    let resume: () -> Void

    /// Natural height of whichever state is showing, so the block can ramp
    /// between two of them instead of snapping. `nil` until the first one
    /// lands; `helmMeasuredHeight` writes it.
    @State private var stateHeight: CGFloat?
    /// The same measurement for the suppression row, which grows and shrinks on
    /// the engine's say-so rather than on a press.
    @State private var suppressedHeight: CGFloat?

    /// What is *drawn*, as against what is true. Everything below reads these
    /// and nothing draws from the properties directly.
    ///
    /// Seeded from the incoming values rather than from a constant, because the
    /// first value is not a change: a page opened while a timer is already
    /// running must show the countdown, not play `.idle` swapping into it. A
    /// `State` initial value is used once per identity, and this view's
    /// identity is stable, so the seed is ignored on every rebuild after the
    /// first.
    ///
    /// Not an optional falling back to the property: while nothing has arrived
    /// the fallback is the live value, so the row would draw itself the instant
    /// the flag flips and the `onChange` would animate from the new value to
    /// itself.
    @State private var shownState: SessionHero
    @State private var shownSuppressed: Bool

    /// Free-form minutes, and the popover that takes them.
    ///
    /// Not stored anywhere. The panel's number is a setting (what its Start
    /// button starts next time); here it is an instruction carried out on the
    /// spot, and a page reopened holding last week's «47» would offer a choice
    /// already used up.
    @State private var showCustomTime = false
    /// The number the field is holding, in minutes. Seeded from the module's
    /// default duration when the popover opens; that default is 0
    /// («Indefinite») until somebody sets one, and while it is 0 the field opens
    /// at 00:00 with the verb disabled.
    @State private var customMinutes = 0

    /// The notice, the battery floor and `timerEndsAutomation` carry no
    /// defaults: each one's default looks like «nothing is wrong» (`.none`, `0`,
    /// the one-press Stop), so the compiler is the only reader that can catch a
    /// call site dropping them.
    init(state: SessionHero, now: Date, anyRuleOn: Bool, defaultDurationMinutes: Int,
         notice: KeepAwakeNotice, ruleHolds: Bool, timerEndsAutomation: Bool,
         appNames: [String] = [],
         batteryFloor: Int,
         timedNote: @escaping (Date) -> String,
         start: @escaping (Int) -> Void, stop: @escaping () -> Void,
         resume: @escaping () -> Void) {
        self.state = state
        self.now = now
        self.anyRuleOn = anyRuleOn
        self.defaultDurationMinutes = defaultDurationMinutes
        self.notice = notice
        self.ruleHolds = ruleHolds
        self.timerEndsAutomation = timerEndsAutomation
        self.appNames = appNames
        self.batteryFloor = batteryFloor
        self.timedNote = timedNote
        self.start = start
        self.stop = stop
        self.resume = resume
        _shownState = State(initialValue: state)
        _shownSuppressed = State(initialValue: notice != .none)
    }

    var body: some View {
        // spacing 0 + padding inside the row: a stack spacing would still
        // insert its gap above the collapsed (zero-height) row, leaving a strip
        // of air under the buttons that nothing is in.
        VStack(spacing: 0) {
            states
                // The four states' buttons only, asked once; the banner's «Resume» below stays the kit's well.
                .helmCapsuleButtons()
                .frame(maxWidth: .infinity)
                // The measurement alone, not `helmAccordion`: this block never
                // collapses. It needs to be the size of whatever it shows, so
                // the cross-fade has an animating frame for its clip.
                .helmMeasuredHeight($stateHeight)
                .frame(height: stateHeight, alignment: .top)
                // The pair, not either half: the frame is here for the edge
                // rather than for the travel, so an outgoing state a line
                // taller does not draw over what sits below.
                .clipped()
            // Under the four states rather than inside three of them:
            // `.timed` and `.idle` are the same height by design, so the cards
            // below do not move when somebody presses «15 min».
            stopNote
            // The Mac is asleep, a rule that applies is on screen saying
            // nothing, and there is a third thing to read. It ends by itself
            // when the condition drops, so there is nothing to dismiss.
            //
            // Not an `if`, but the accordion: the row always exists and its
            // height animates between 0 and its own measurement, from
            // `shownSuppressed`, which is written inside a transaction below.
            suppressionRow
                .helmAccordion(open: shownSuppressed, height: $suppressedHeight)
        }
        // Where the two values land, not where they were set: the engine
        // decides both and publishes them, and a transaction is the only thing
        // that makes either of them move.
        .onChange(of: state) { _, arrived in
            withAnimation(HelmMotion.disclosure) { shownState = arrived }
        }
        // Either notice fills the same slot, so the drawn flag is «there is
        // something to say» rather than «a rule is paused»: the battery guard
        // sets no `suppressed` of its own.
        .onChange(of: notice) { _, arrived in
            withAnimation(HelmMotion.disclosure) { shownSuppressed = arrived != .none }
        }
        // The one change on this page that nobody caused. The veto arrives
        // because a charge fell, and none of what follows moves focus or
        // changes anything a VoiceOver reader is on, so it is said.
        //
        // On the rising edge only: `onChange` fires on a change, and the guard
        // lifting is not news that needs interrupting anybody — the buttons work
        // again, which is what pressing one will say. Said with the long form,
        // because the way out is the whole point of speaking at all.
        .onChange(of: batteryStopped) { _, stopped in
            if stopped { HelmA11y.announce(KAStr.stoppedByBattery(batteryFloor)) }
        }
    }

    // MARK: - The four states

    /// One `Group`, four branches, one transition each.
    ///
    /// The transition has to sit on the branches: applied outside the switch it
    /// modifies a view that never appears or disappears, and fires never.
    @ViewBuilder private var states: some View {
        Group {
            switch shownState {
            case .idle:
                idle.transition(.opacity)
            case .timed(let end):
                timed(end).transition(.opacity)
            case .indefinite:
                indefinite.transition(.opacity)
            case .automatic(let conditions):
                automatic(conditions).transition(.opacity)
            }
        }
    }

    /// The figure's slot, in words. 40 pt light is the size the countdown gets,
    /// and an idle page that dropped to body text there made the whole screen
    /// change shape when a timer began.
    private var idle: some View {
        VStack(spacing: HelmSpace.s4) {
            Text(KAStr.heroIdle)
                .font(HelmText.heroFont)
                .foregroundStyle(HelmText.quiet)
                .helmHeroSentence()
            // Why this module is not holding the Mac, in two readings and no
            // third: «something other than Helm is keeping this Mac awake» would
            // contradict the 40 pt sentence directly above it.
            //
            // It steps aside for the banner: under the veto it is true and the
            // vaguest thing the screen knows, and the notice naming the charge
            // is the useful answer.
            //
            // Opacity, not an `if`: the condition arrives from the engine and
            // changes under the reader, and `.idle` and `.timed` are the same
            // height by design.
            Text(anyRuleOn ? KAStr.heroIdleReason : KAStr.heroNoRules)
                // `quiet`, like the other three states' captions; `faint` here
                // would differ from it by a luminance nobody can see.
                .font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
                .helmHeroSentence()
                .opacity(batteryStopped ? 0 : 1)
                .animation(HelmMotion.interface, value: batteryStopped)
                .accessibilityHidden(batteryStopped)
            HelmWrappingRow {
                presetButtons
                // Lengths first, then the one that has none: the free-form field
                // is the fourth answer to «for how long», and «Indefinite»
                // between them would read as a gap in the run.
                customButton
                startButton(KAStr.indefinite, minutes: 0)
            }
            .padding(.top, HelmSpace.s6)
        }
    }

    private func timed(_ end: Date) -> some View {
        // One label, read by the figure and by the animation that carries it.
        // Spelled twice they can disagree, and the disagreement is invisible:
        // an animation keyed on the raw interval fires on a tick that draws the
        // same digits.
        let label = TimerProgress.label(remaining: max(0, end.timeIntervalSince(now)))
        return VStack(spacing: HelmSpace.s4) {
            // The hero's step with tabular digits, because this hero is a
            // number: `HelmText.heroFigureFont` carries both, and carries them
            // for the page in Layout that draws the same figure.
            Text(label)
                .font(HelmText.heroFigureFont)
                .tracking(HelmText.heroFigureTracking)
                // The one figure in this block that is a number rather than a
                // sentence, and it takes the same treatment: a countdown does
                // not wrap, and the four states must not disagree about how the
                // slot behaves when one of them does.
                .helmHeroSentence()
                .contentTransition(.numericText(countsDown: true))
                // A content transition is an instruction for an animation, not
                // one: the `TimelineView` rebuilds this with no transaction, so
                // without this the digits cut. Keyed on the label, for the
                // reason above.
                .animation(HelmMotion.interface, value: label)
                // A figure that redraws once a second is a figure VoiceOver
                // re-speaks once a second, and it interrupts itself doing it —
                // so the page becomes unusable for as long as a timer runs.
                // `.updatesFrequently` is the trait that says «this changes on
                // its own; read it when asked, not when it moves».
                .accessibilityLabel(KAStr.a11yRemaining(label))
                .accessibilityAddTraits(.updatesFrequently)
            Text(timedNote(end))
                .font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
                .helmHeroSentence()
            HelmWrappingRow {
                // The same arithmetic the panel's «+15» uses, and for the
                // same reason: this is a `Double` that came off disk.
                extendButton(by: 15, from: end)
                extendButton(by: 60, from: end)
                customButton
                Button(KAStr.indefinite) { start(0) }
                    .controlSize(.large)
                stopButton
            }
            .padding(.top, HelmSpace.s6)
        }
    }

    /// One figure for «awake», and the reason on the line below (`KAStr.heroAwake`).
    private var indefinite: some View {
        VStack(spacing: HelmSpace.s4) {
            Text(KAStr.heroAwake)
                .font(HelmText.heroFont)
                .helmHeroSentence()
            Text(KAStr.heroUntilYouStop)
                .font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
                .helmHeroSentence()
            HelmWrappingRow {
                // A session with no deadline can be given one; without these the
                // only way to bound it is to stop it and start again.
                presetButtons
                customButton
                stopButton
            }
            .padding(.top, HelmSpace.s6)
        }
    }

    private func automatic(_ conditions: Set<ActiveCondition>) -> some View {
        VStack(spacing: HelmSpace.s4) {
            Text(KAStr.heroAwake)
                .font(HelmText.heroFont)
                .helmHeroSentence()
            Text(KAStr.conditionsLine(conditions, appNames: appNames))
                .font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
                .helmHeroSentence()
            HelmWrappingRow {
                // The same three a session with no deadline offers. One button
                // carrying whatever «Default duration» says would offer a length
                // nobody chose for this session and hide the other two.
                presetButtons
                // Zero is not a length, it is «no deadline», in the idle row's
                // word. It lets a person keep holding the Mac after the rule's
                // app quits without stopping the rule and starting again.
                customButton
                startButton(KAStr.indefinite, minutes: 0)
                stopButton
            }
            .padding(.top, HelmSpace.s6)
        }
    }

    // MARK: - The row under them

    /// A field, not three loose pieces.
    ///
    /// `HelmBanner` is the shape for a statement with one verb beside it, as
    /// the panel's permissions notice draws. Its colours are literal because
    /// the height animates, `.clipped()` gives it a layer of its own, and a
    /// hierarchical style resolves again when that layer is dropped, which
    /// reads as a blink.
    @ViewBuilder private var suppressionRow: some View {
        KeepAwakeNoticeBanner(notice: notice, batteryFloor: batteryFloor, compact: false,
                              resume: resume)
        .frame(maxWidth: .infinity)
        // Inside the measured row, not between it and the block above: the gap
        // has to be part of what collapses to zero.
        .padding(.top, HelmSpace.s5)
    }

    /// Stop does not only end a session — while a rule's trigger is true it
    /// silences the rule as well, so the Mac does not simply take itself back.
    ///
    /// Not only in the branch that draws an automatic session: `stopSession`
    /// suppresses whenever a trigger holds, whatever started the session, so a
    /// hand-started timer with the rule's app on screen pauses the rule too.
    /// One condition, and it is the engine's own.
    ///
    /// Not once the rule is suppressed: the banner then says the same thing and
    /// carries the way back. Not under a notice: under the battery veto a
    /// trigger holds with `.idle` drawn, and there is no Stop button on screen.
    /// And only while one press does both: once Stop is two presses the
    /// sentence is false on the first and redundant on the second.
    var saysWhatStopWouldDo: Bool {
        stopPress == .stopEverything && ruleHolds && notice == .none
    }

    /// What the next press of the stopping button does, from what is true right
    /// now — the same call the engine makes when the press arrives, so the word
    /// on the button and the act behind it are one decision.
    ///
    /// Recomputed on every rebuild, which the page's `TimelineView` does once a
    /// second. That is the whole of the button's memory: the second step is
    /// offered while the state that means it is true, and not a moment longer.
    ///
    /// Read from `state` and not from the drawn `shownState`, so the word
    /// belongs to the press that would land; the caption below is drawn from
    /// the live values for the same reason. The cost is a cross-fade's outgoing
    /// copy carrying the new word as it fades.
    var stopPress: StopPress {
        StopPress.next(sessionRunning: state.sessionRunning, ruleHolds: ruleHolds,
                       timerEndsAutomation: timerEndsAutomation)
    }

    private var stopNote: some View {
        Text(KAStr.heroStopSuppresses)
            .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
            .helmHeroSentence()
            // Opacity, not an `if`: the condition is the engine's and changes
            // under the reader, and a caption that left the hierarchy would
            // take the page's height with it in one frame.
            .opacity(saysWhatStopWouldDo ? 1 : 0)
            .animation(HelmMotion.interface, value: saysWhatStopWouldDo)
            .accessibilityHidden(!saysWhatStopWouldDo)
            .padding(.top, HelmSpace.s3)
    }

    // MARK: - Buttons

    /// The three lengths every state offers, written once.
    ///
    /// Computed rather than stored: the labels are `L()` lookups and a
    /// `static let` would freeze them in whatever language the app opened in.
    @ViewBuilder private var presetButtons: some View {
        startButton(KAStr.duration(15), minutes: 15)
        startButton(KAStr.oneHour, minutes: 60)
        startButton(KAStr.twoHours, minutes: 120)
    }

    /// «+15 мин», «+1 час» — adding to a deadline rather than replacing it.
    ///
    /// The arithmetic is `TimerPolicy`'s, which clamps: a remaining interval is
    /// a `Double` that came off disk, and «+1 hour» on a session somebody's
    /// plist claims has forty days left must not extend it.
    private func extendButton(by minutes: Int, from end: Date) -> some View {
        Button("+" + KAStr.duration(minutes)) {
            start(TimerPolicy.extendedMinutes(remaining: end.timeIntervalSince(now),
                                              adding: minutes))
        }
        .controlSize(.large)
    }

    /// No accented preset: every button on this row is the same button. A fill
    /// on the one matching «Default duration» would land on «Indefinite» on a
    /// fresh install, and on any other reads as the thing to press. «Default
    /// duration» in the Behaviour card names the controls that use it.
    ///
    /// Disabled while the battery guard vetoes: `recompute` reaches
    /// `releaseForBattery` before anything is held, so a session asked for then
    /// is refused at once, and a live button beside the notice invites the
    /// person to test the explanation.
    private func startButton(_ title: String, minutes: Int) -> some View {
        Button(title) { start(minutes) }
            .controlSize(.large)
            .disabled(batteryStopped)
    }

    /// One button, and its word is whichever press it is about to be.
    ///
    /// Not two buttons and an `if`: the act on the other end is one call
    /// (`KeepAwakeEngine.stopSession`), and the engine decides what that press means
    /// from the same three facts this label is spelled from. A second control
    /// would be a second decision to keep in step with the first.
    private var stopButton: some View {
        Button(KAStr.stopWord(stopPress), action: stop)
            .controlSize(.large)
    }

    /// Any duration, not one of the presets.
    ///
    /// Any length, on the page as on the panel, with the panel's strings, so
    /// the two surfaces say the same word for the same thing.
    private var customButton: some View {
        Button(KAStr.customTime) {
            customMinutes = defaultDurationMinutes
            showCustomTime = true
        }
        .controlSize(.large)
        // Disabled under the veto, as `startButton` is: otherwise it would
        // open a popover and take a number before refusing.
        .disabled(batteryStopped)
        .popover(isPresented: $showCustomTime, arrowEdge: .bottom) { customTimeEditor }
    }

    /// macOS's own timer, in the two units this module can keep.
    ///
    /// One box asking for minutes would make «two hours» a sum the person has
    /// to do. `HelmDurationField` is the Clock shape: a column per unit, the
    /// abbreviation above the figure.
    var customTimeEditor: KeepAwakeCustomDuration {
        // Zero minutes is «Indefinite», and that word is the button beside
        // «Other…». A field showing 00:00 offering to start something would
        // be this screen giving one choice two names; the prompt disables its
        // verb at 0.
        KeepAwakeCustomDuration(minutes: $customMinutes, verb: KAStr.start,
                                apply: applyCustomTime)
    }

    /// `HelmDurationField` has already clamped to the same ceiling
    /// `startSession` uses, and the prompt does not reach here with zero, so
    /// there is no second opinion about the number here.
    private func applyCustomTime() {
        showCustomTime = false
        start(customMinutes)
    }
}
