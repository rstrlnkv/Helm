import SwiftUI
import HelmRuntime
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

    init(state: SessionHero, now: Date, anyRuleOn: Bool, defaultDurationMinutes: Int,
         suppressed: Bool, timedNote: @escaping (Date) -> String,
         start: @escaping (Int) -> Void, stop: @escaping () -> Void,
         resume: @escaping () -> Void) {
        self.state = state
        self.now = now
        self.anyRuleOn = anyRuleOn
        self.defaultDurationMinutes = defaultDurationMinutes
        self.suppressed = suppressed
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
            Text(anyRuleOn ? KAStr.heroIdleReason : KAStr.heroNoRules)
                .font(.callout).foregroundStyle(HelmText.faint)
            HStack(spacing: 8) {
                startButton(KAStr.duration(15), minutes: 15)
                startButton(KAStr.oneHour, minutes: 60)
                startButton(KAStr.twoHours, minutes: 120)
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
            Text(timedNote(end)).font(.callout).foregroundStyle(HelmText.quiet)
            HStack(spacing: 8) {
                // The same arithmetic the panel's «+15» uses, and for the same
                // reason: this is a `Double` that came off disk.
                Button("+" + KAStr.duration(15)) {
                    start(TimerPolicy.extendedMinutes(remaining: end.timeIntervalSince(now),
                                                      adding: 15))
                }
                .controlSize(.large)
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
                .font(.callout).foregroundStyle(HelmText.quiet)
            HStack(spacing: 8) { stopButton }
                .padding(.top, 10)
        }
    }

    private func automatic(_ conditions: Set<ActiveCondition>) -> some View {
        VStack(spacing: 8) {
            Text(KAStr.heroAwake)
                .font(.system(size: 40, weight: .light))
            Text(conditions.map(KAStr.condition).sorted().joined(separator: " · "))
                .font(.callout).foregroundStyle(HelmText.quiet)
            HStack(spacing: 8) {
                // Zero is not a length, it is «no deadline» — composing «start a
                // timer for 0 min» from it made the page offer a timer of
                // nothing. The word is the one the idle row uses for the same
                // choice.
                Button(defaultDurationMinutes == 0
                       ? KAStr.indefinite : KAStr.startTimerFor(defaultDurationMinutes)) {
                    start(defaultDurationMinutes)
                }
                .controlSize(.large)
                stopButton
            }
            .padding(.top, 10)
            // Stop does not end an automatic session, it silences the rule —
            // the one thing nobody could learn from any screen. Said beside the
            // button that does it.
            Text(KAStr.heroStopSuppresses)
                .font(.caption).foregroundStyle(HelmText.faint)
        }
    }

    // MARK: - The row under them

    private var suppressionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(HelmSignal.warning)
                .accessibilityHidden(true)
            // Literal colours, both of them: this row sits inside a block whose
            // height animates, `.clipped()` gives that block a layer of its own,
            // and hierarchical styles resolve against the rendering context —
            // so they resolve again when the layer is dropped at the end, which
            // reads as a blink. The panel's ⋯ heading blinked for exactly this.
            Text(KAStr.automationPaused)
                .font(.callout).foregroundStyle(HelmText.quiet)
            Spacer(minLength: 8)
            Button(KAStr.resume, action: resume)
        }
        .padding(.horizontal, 20)
        // Inside the measured row, not between it and the block above: the gap
        // has to be part of what collapses to zero.
        .padding(.top, 10)
    }

    // MARK: - Buttons

    /// The preset the menu-bar switch and the shortcut start is the prominent
    /// one. It is the only place on any screen that says which that is.
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
        Button(KAStr.stop, action: stop)
            .controlSize(.large)
    }
}
