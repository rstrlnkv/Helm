import SwiftUI
import HelmUI
import Module_KeepAwake_Engine

/// The top of the Keep Awake page: what is happening, and the verbs for it.
///
/// A view of its own rather than two members of the settings page, because the
/// only way to review motion is to measure it, and a `private var` on a page
/// that needs a transport, a store and a running engine cannot be hosted in a
/// window and photographed. `HeroMotionProbe` mounts this exact type; nothing
/// stands in for it.
///
/// **Why a cross-fade and not a reveal.** The house rule is that reveals grow —
/// a measured height and `.clipped()`, never a fade — and it does not apply
/// here, because nothing is being revealed. The four states are different
/// views, not one view in four shapes: there is no shared figure to interpolate
/// between a sentence and a countdown, and no row that was always there and is
/// now visible. Growing would play the old block closing and the new one
/// opening — two beats for a one-beat change, and the whole settings form under
/// it moving twice. `KeepAwakePanelTile` reached the same conclusion for its
/// two rows; at 40 pt the conclusion does not change. (How the tile *spells* it
/// is a different matter, and the table below is about that.)
///
/// **What does change at 40 pt is the second half.** The tile's swap sits
/// inside a card that is already ramping its own height, so nothing else was
/// needed there. This block has the entire settings form beneath it and nothing
/// was moving it: `.timed` and `.idle` happen to be the same height, but
/// `.indefinite` is a line shorter and `.automatic` a caption taller, and a
/// fade that snaps the page by 20 pt underneath somebody's eyes is the fade
/// being blamed for a jump it did not cause. So the states are cross-faded
/// *and* the block's measured height is animated, both on one curve — two
/// systems need one curve, not one duration. Measured off a 60 fps recording of
/// the real window: starting a timer fades over 20 frames (2.767 s → 3.100 s),
/// and the first card of the form below travels 21 pt across 14 distinct
/// positions in the same 300 ms. Stopping one: 13 positions in 333 ms.
///
/// The clip is not decoration. With the measured frame and `.clipped()`, ink
/// past the block's new edge is 78707 at the first sample and **0** at every
/// one after; without them it is 77427, 13025, 1438 — the outgoing caption goes
/// on drawing over the form for three more frames. `.clipped()` on its own does
/// not do it: a departing view is not inside the bounds a bare clip is taken
/// from, so the clip needs a frame that is animating.
///
/// **Where the transaction comes from, and why it is not `.animation`.** The
/// state does not change because a button was pressed; it changes when the
/// engine says so, over the wire, in a published value, so there is no call
/// site to wrap in `withAnimation`. The obvious answer is
/// `.animation(HelmMotion.disclosure, value: state)` on the block — and it does
/// nothing. Measured in an offscreen window, ink mass in the figure band, 20 ms
/// apart, on this exact shape (a `Group`, two branches, `.transition(.opacity)`
/// on each):
///
/// | how the swap is made | distinct values in 400 ms |
/// |---|---|
/// | `.animation(_:value:)` on the group | **1** |
/// | `.animation(_:value:)`, group also clipped to a fixed height | **1** |
/// | the branch written inside `withAnimation` | **11** |
/// | the same, clipped | **11** |
///
/// The instrument was proved on the same run: a plain `.opacity` on a view that
/// *stays* ramps over 8 samples under `.animation(_:value:)` and arrives in one
/// step with the animation nil. So the modifier is not dead — it carries a
/// property of a view that persists, and it carries neither a structural change
/// (an insert or a remove, which is what a transition is) nor a layout one.
/// This is the same shape of finding as the law about `onGeometryChange`, and
/// the same remedy: the value that arrives from outside lands in this view's
/// own state, *inside* a transaction, and everything drawn reads that.
///
/// The same measurement says a frame height is no better off: a plain grey
/// block, nothing measured about it, gave `[160, 160, 160 …]` under
/// `.animation(HelmMotion.disclosure, value:)` — one step, twenty samples — and
/// `[3, 24, 53, 83, 110, 129, 143, 151, 155, 158, 159, 160 …]` with the same
/// boolean written inside `withAnimation`. Which is why the suppression row
/// below keeps its own drawn flag too.
struct KeepAwakeHero: View {
    let state: SessionHero
    /// The tick the figure is drawn from. Taken from the page's `TimelineView`
    /// rather than read off the clock inside the body, so the countdown is a
    /// function of the tick: a body re-run for any other reason (a window
    /// resize, the suppression row arriving) then redraws the same digits
    /// instead of a new second nobody asked for, which would fire the numeric
    /// transition at a random moment.
    let now: Date
    let anyRuleOn: Bool
    let defaultDurationMinutes: Int
    let suppressed: Bool
    /// A rule's trigger is true right now, whatever state the figure is in.
    /// The engine's own word for it, because that is the exact condition under
    /// which Stop silences the rule as well as ending the session — see
    /// `KeepAwakeEngine.ruleHolds`.
    let ruleHolds: Bool
    let timedNote: (Date) -> String
    let start: (Int) -> Void
    let stop: () -> Void
    let resume: () -> Void

    /// Natural height of whichever state is showing, so the block can ramp
    /// between two of them instead of snapping. Written inside the transaction
    /// where it lands, never at the change that caused it — `onGeometryChange`
    /// hands its value over *outside* the running transaction, and a height
    /// written there is a jump however many animations surround the button.
    @State private var stateHeight: CGFloat = 0
    /// The same measurement for the suppression row, which grows and shrinks on
    /// the engine's say-so rather than on a press.
    @State private var suppressedHeight: CGFloat = 0

    /// What is *drawn*, as against what is true. Everything below reads these
    /// and nothing draws from the properties directly.
    ///
    /// Seeded from the incoming values rather than from a constant, because the
    /// first value is not a change: a page opened while a timer is already
    /// running must show the countdown, not play `.idle` swapping into it. A
    /// `State` initial value is used once per identity, and this view's
    /// identity is stable — the page's `TimelineView` builds it afresh every
    /// second and the seed is ignored every time but the first.
    ///
    /// The other spelling — an optional falling back to the property — was
    /// tried and is a check that cannot fail: while nothing has arrived the
    /// fallback *is* the live value, so the row drew itself the instant the
    /// flag flipped and the `onChange` that followed animated from the new
    /// value to itself. Measured: `[300, 300, 300 …]`, twenty samples of a row
    /// that was supposed to be growing.
    @State private var shownState: SessionHero
    @State private var shownSuppressed: Bool

    /// Free-form minutes, and the popover that takes them.
    ///
    /// Not stored anywhere. The panel remembers its custom duration because the
    /// panel's number *is* a setting — it is what its switch starts next time.
    /// Here the number is an instruction carried out on the spot, and a page
    /// that reopened holding somebody's «47» from last week would be offering a
    /// choice they had already used up.
    @State private var showCustomTime = false
    /// The number the field is holding, in minutes. Seeded from the module's
    /// own default duration when the popover opens, so the field starts on
    /// something meaningful rather than on zero — Clock does the same.
    @State private var customMinutes = 0

    init(state: SessionHero, now: Date, anyRuleOn: Bool, defaultDurationMinutes: Int,
         suppressed: Bool, ruleHolds: Bool,
         timedNote: @escaping (Date) -> String,
         start: @escaping (Int) -> Void, stop: @escaping () -> Void,
         resume: @escaping () -> Void) {
        self.state = state
        self.now = now
        self.anyRuleOn = anyRuleOn
        self.defaultDurationMinutes = defaultDurationMinutes
        self.suppressed = suppressed
        self.ruleHolds = ruleHolds
        self.timedNote = timedNote
        self.start = start
        self.stop = stop
        self.resume = resume
        _shownState = State(initialValue: state)
        _shownSuppressed = State(initialValue: suppressed)
    }

    var body: some View {
        // spacing 0 + padding inside the row: a stack spacing would still
        // insert its gap above the collapsed (zero-height) row, leaving a strip
        // of air under the buttons that nothing is in.
        VStack(spacing: 0) {
            states
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    guard height > 0, stateHeight != height else { return }
                    // The first measurement is not a change. Animating it plays
                    // the hero collapsing from whatever the unmeasured layout
                    // happened to be, on the first frame of the page.
                    if stateHeight == 0 { stateHeight = height }
                    else { withAnimation(HelmMotion.disclosure) { stateHeight = height } }
                }
                .frame(height: stateHeight > 0 ? stateHeight : nil, alignment: .top)
                // The pair, not either half. The outgoing state is a line
                // taller than the one arriving, and without an animating frame
                // for the clip to be taken from it goes on drawing past the
                // block's edge, over the form — measured at the top of this
                // file. The height would ramp without this frame (the swap's
                // own transaction carries the layout), so it is here for the
                // edge rather than for the travel.
                .clipped()
            // Under the four states rather than inside three of them.
            //
            // Written into each branch, it made `.timed` a line taller than
            // `.idle` — and those two are the same height *by design*, so that
            // the form below does not move when somebody presses «15 min».
            // `HeroMotionProbe` caught it at three distinct heights where one
            // is the whole point. Out here the caption belongs to the block,
            // not to a state, so every state stays the height it was.
            stopNote
            // The Mac is asleep, a rule that applies is on screen saying
            // nothing, and there is a third thing to read. It ends by itself
            // when the condition drops, so there is nothing to dismiss.
            //
            // Not an `if`: removing rows from the hierarchy takes the page's
            // height with them in one frame, and the row keeps drawing over
            // whatever is below while it goes. The canonical accordion instead
            // — the row always exists, its natural height is measured, and the
            // height animates between 0 and that number.
            suppressionRow
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                    if height > 0 { suppressedHeight = height }
                }
                .frame(height: shownSuppressed ? suppressedHeight : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(shownSuppressed)
                // Clipped is not hidden: VoiceOver read the row while it was
                // collapsed to nothing.
                .accessibilityHidden(!shownSuppressed)
        }
        // Where the two values land, not where they were set: the engine
        // decides both and publishes them, and a transaction is the only thing
        // that makes either of them move.
        .onChange(of: state) { _, arrived in
            withAnimation(HelmMotion.disclosure) { shownState = arrived }
        }
        .onChange(of: suppressed) { _, silenced in
            withAnimation(HelmMotion.disclosure) { shownSuppressed = silenced }
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
        VStack(spacing: 8) {
            Text(KAStr.heroIdle)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(HelmText.quiet)
            // Why *this module* is not holding the Mac. It used to have a
            // third branch — «something other than Helm is keeping this Mac
            // awake» — which contradicted the 40 pt sentence directly above it
            // (see the note on `heroIdle`).
            Text(anyRuleOn ? KAStr.heroIdleReason : KAStr.heroNoRules)
                .font(.system(size: 13)).foregroundStyle(HelmText.faint)
            HelmWrappingRow {
                startButton(KAStr.duration(15), minutes: 15)
                startButton(KAStr.oneHour, minutes: 60)
                startButton(KAStr.twoHours, minutes: 120)
                // Lengths first, then the one that has none. Every button up to
                // here answers «for how long», and the free-form field is the
                // fourth answer to that question rather than a fifth kind of
                // thing — «Indefinite» between them read as a gap in the run.
                customButton
                startButton(KAStr.indefinite, minutes: 0)
            }
            .padding(.top, 10)
        }
    }

    private func timed(_ end: Date) -> some View {
        // One label, read by the figure and by the animation that carries it.
        // Spelled twice they can disagree, and the disagreement is invisible:
        // an animation keyed on the raw interval fires on a tick that draws the
        // same digits.
        let label = TimerProgress.label(remaining: max(0, end.timeIntervalSince(now)))
        return VStack(spacing: 8) {
            // Monospaced, so the figure does not jitter as the digits change
            // width — it is redrawn once a second for hours.
            Text(label)
                .font(.system(size: 40, weight: .light, design: .monospaced))
                .tracking(-2)
                .contentTransition(.numericText(countsDown: true))
                // The half that was missing. A content transition is not an
                // animation, it is an instruction for one: `.numericText` says
                // *how* to interpolate a change that is already being animated,
                // and this `Text` sits in a `TimelineView` that rebuilds it
                // every second with no transaction anywhere near it — so the
                // digits cut. Keyed on the label rather than on the interval,
                // for the reason above.
                .animation(HelmMotion.interface, value: label)
                // A figure that redraws once a second is a figure VoiceOver
                // re-speaks once a second, and it interrupts itself doing it —
                // so the page becomes unusable for as long as a timer runs.
                // `.updatesFrequently` is the trait that says «this changes on
                // its own; read it when asked, not when it moves».
                .accessibilityLabel(KAStr.a11yRemaining(label))
                .accessibilityAddTraits(.updatesFrequently)
            Text(timedNote(end)).font(.system(size: 13)).foregroundStyle(HelmText.quiet)
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
            .padding(.top, 10)
        }
    }

    /// One figure for «awake», and the reason on the line below.
    ///
    /// There were two sentences here — «Awake until you stop it» and «A rule is
    /// holding the Mac» — and they were not parallel: one named a deadline, the
    /// other described the machinery, and the reader parsed a new construction
    /// for each state of one screen. The figure answers a single question — is
    /// this Mac going to sleep — and everything about *why* sits under it, which
    /// is what the countdown state already did.
    private var indefinite: some View {
        VStack(spacing: 8) {
            Text(KAStr.heroAwake)
                .font(.system(size: 40, weight: .light))
            Text(KAStr.heroUntilYouStop)
                .font(.system(size: 13)).foregroundStyle(HelmText.quiet)
            HelmWrappingRow {
                // A session with no deadline can be given one, and until now
                // the only way to bound it was to stop it and start again.
                startButton(KAStr.duration(15), minutes: 15)
                startButton(KAStr.oneHour, minutes: 60)
                startButton(KAStr.twoHours, minutes: 120)
                customButton
                stopButton
            }
            .padding(.top, 10)
        }
    }

    private func automatic(_ conditions: Set<ActiveCondition>) -> some View {
        VStack(spacing: 8) {
            Text(KAStr.heroAwake)
                .font(.system(size: 40, weight: .light))
            Text(conditions.map(KAStr.condition).sorted().joined(separator: " · "))
                .font(.system(size: 13)).foregroundStyle(HelmText.quiet)
            HelmWrappingRow {
                // The same three a session with no deadline offers. It used
                // to be one button carrying whatever «Default duration» said,
                // which meant the page offered a length nobody had chosen for
                // this session and hid the other two.
                startButton(KAStr.duration(15), minutes: 15)
                startButton(KAStr.oneHour, minutes: 60)
                startButton(KAStr.twoHours, minutes: 120)
                // Zero is not a length, it is «no deadline» — composing «start
                // a timer for 0 min» from it made the page offer a timer of
                // nothing. The word is the one the idle row uses for the same
                // choice. A rule can hold this Mac for an hour or for a day,
                // and until now the only way to say «and keep holding it after
                // the app quits» was to stop the rule and start again by hand.
                customButton
                startButton(KAStr.indefinite, minutes: 0)
                stopButton
            }
            .padding(.top, 10)
        }
    }

    // MARK: - The row under them

    /// A field, not three loose pieces.
    ///
    /// It was a bare `HStack` — a mark, some quiet text, a button — floating
    /// under a centred 40 pt figure with nothing to say the three belonged
    /// together. `HelmBanner` is the shape v3 gives a statement with one verb
    /// beside it, and the same one the panel's permissions notice already
    /// draws. Its colours are literal for the reason this block needs: the
    /// height animates, `.clipped()` gives it a layer of its own, and a
    /// hierarchical style resolves again when that layer is dropped — which
    /// reads as a blink.
    private var suppressionRow: some View {
        HelmBanner(KAStr.automationPaused, symbol: "pause.circle.fill", fillsWidth: false) {
            Button(KAStr.resume, action: resume)
        }
        .frame(maxWidth: .infinity)
        // Inside the measured row, not between it and the block above: the gap
        // has to be part of what collapses to zero.
        .padding(.top, 12)
    }

    /// Stop does not only end a session — while a rule's trigger is true it
    /// silences the rule as well, so the Mac does not simply take itself back.
    ///
    /// This used to be written once, in the branch that draws an automatic
    /// session, on the reasoning that a rule is what that branch is about. But
    /// the *engine* asks a different question: `stopSession` suppresses whenever
    /// a trigger holds, whatever started the session. A hand-started timer
    /// running while the rule's app is also on screen draws the countdown, and
    /// Stop there paused the rule with no screen anywhere mentioning it. One
    /// condition now, and it is the engine's own.
    /// A rule could be paused by pressing Stop, and has not been already.
    ///
    /// The second half is not pedantry. Photographed: with the rule suppressed,
    /// the caption «Stop pauses the rule until it applies again» sat directly
    /// above the banner «Paused until the rule applies again» — the same
    /// sentence twice, one of them in the future tense about something that had
    /// already happened. The banner is the one that belongs there, because it
    /// carries the way back.
    private var saysWhatStopWouldDo: Bool { ruleHolds && !suppressed }

    private var stopNote: some View {
        Text(KAStr.heroStopSuppresses)
            .font(.system(size: 11)).foregroundStyle(HelmText.faint)
            // Opacity, not an `if`. The condition is the engine's and changes
            // under the reader — an app quits, a charger comes out — and a
            // caption that removed itself from the hierarchy would take the
            // page's height with it in one frame, which is the accordion
            // defect the suppression row below was rewritten to avoid.
            .opacity(saysWhatStopWouldDo ? 1 : 0)
            .animation(HelmMotion.interface, value: saysWhatStopWouldDo)
            .accessibilityHidden(!saysWhatStopWouldDo)
            .padding(.top, 6)
    }

    // MARK: - Buttons

    /// The preset the menu-bar switch and the shortcut start is the prominent
    /// one. It is the only place on any screen that says which that is.
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

    @ViewBuilder private func startButton(_ title: String, minutes: Int) -> some View {
        // `.borderedProminent`, not `.tint` on a plain button: a tint colours a
        // button's *label* and leaves the fill alone, so all four presets came
        // out identical and the one the switch actually starts was a claim
        // nothing on screen backed up.
        // Zero is «Indefinite», and it is never the accented button however
        // the default duration is set. The accent says «this is what the
        // panel's switch starts», and on a fresh install that is zero — so the
        // one choice on the row that never ends was the one the page drew the
        // eye to. A default of «Indefinite» simply leaves the row unaccented.
        if minutes > 0, minutes == defaultDurationMinutes {
            Button(title) { start(minutes) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        } else {
            Button(title) { start(minutes) }
                .controlSize(.large)
        }
    }

    private var stopButton: some View {
        Button(KAStr.stop, action: stop)
            .controlSize(.large)
    }

    /// Any duration, not one of the presets.
    ///
    /// The panel has had this since the first version and the page never did,
    /// so «keep this Mac awake for the length of this build» meant either
    /// rounding to two hours or opening the panel — and the page is the screen
    /// somebody is already looking at when they think it. Same strings as the
    /// panel's entry, so the two surfaces say the same word for the same thing.
    private var customButton: some View {
        Button(KAStr.customTime) {
            customMinutes = defaultDurationMinutes
            showCustomTime = true
        }
        .controlSize(.large)
        .popover(isPresented: $showCustomTime, arrowEdge: .bottom) { customTimeEditor }
    }

    /// macOS's own timer, in the two units this module can keep.
    ///
    /// It was one box asking for minutes, which made «two hours» a sum the
    /// person had to do — and a box holding `120` reads the same as one holding
    /// `12`. `HelmDurationField` is the Clock shape: a column per unit, the
    /// abbreviation above the figure.
    private var customTimeEditor: some View {
        VStack(spacing: 14) {
            Text(KAStr.customTimeTitle)
                .font(.system(size: 13, weight: .semibold))
            HelmDurationField(minutes: $customMinutes,
                              ceiling: TimerPolicy.longestSessionMinutes,
                              hourLabel: KAStr.hoursUnitShort,
                              minuteLabel: KAStr.minutesUnitShort)
            Button(KAStr.start, action: applyCustomTime)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                // Zero minutes is «Indefinite», and that word is a button of
                // its own two rows up. A field showing 00:00 offering to start
                // something would be this screen giving one choice two names.
                .disabled(customMinutes == 0)
        }
        .padding(18)
        .frame(width: 230)
    }

    /// `HelmDurationField` has already clamped to the same ceiling
    /// `startSession` uses, so there is no second opinion about the number
    /// here — only the refusal to read zero as a duration.
    private func applyCustomTime() {
        showCustomTime = false
        guard customMinutes > 0 else { return }
        start(customMinutes)
    }
}
