// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// **A wait whose length somebody measured, drawn as the clock it is — and
/// which stops claiming anything the moment the clock runs out.**
///
/// The shape of the problem it was written for: a button starts a run that
/// takes about twenty seconds, and the port that does the work reports two
/// things and only two — it started, and it stopped. There is no stage, no
/// percentage and no byte counter on the wire, and there is no honest way to
/// invent one on the screen. What there *is* is a clock: the page knows when it
/// pressed, and somebody has measured how long the thing usually takes. So this
/// draws the clock and says so, rather than drawing a progress bar and implying
/// a measurement nobody took.
///
/// **The whole design is in `Claim`, and it has three cases because there are
/// three honest things to say.** `within` is «the wait is this far through its
/// usual length», which is true of the clock and claims nothing about the work.
/// `overrun` is «this has already taken longer than usual», and it is the case
/// that makes the other one honest: a bar that fills to the end and then sits
/// there is a lie with a deadline, and the way not to tell it is to have
/// somewhere to go when the deadline passes. `unknown` is the case nobody
/// remembers to write — the page arrived while the run was already going and
/// never saw it start, so there is no elapsed time to be a fraction of.
///
/// Both of the other two collapse to **the indeterminate spinner this replaced**,
/// which is the safest fallback there is: it is exactly what the app drew
/// before, it is what macOS draws for work of unknown length everywhere else,
/// and it is drawn at the same size in the same slot, so nothing around it
/// moves when the handover happens.
///
/// **No `Animation` token, and that is deliberate.** A token is a curve, and a
/// curve is a claim about how something *feels* moving; this is not moving, it
/// is being redrawn, and what it is redrawn from is the clock. Driving it with
/// `withAnimation(.linear(duration: expected))` would be a fifteen-to-twenty
/// second transaction whose `@State` has to survive every rebuild of a page the
/// engine republishes dozens of times behind one connect, and whose value could
/// then disagree with the truth. A `TimelineView` cannot disagree with the
/// truth: the fraction is a pure function of `context.date`. That is the same
/// finding the About bezel wrote down — ARCHITECTURE.md § Motion, «there is no
/// token for turning forever, and that is the finding».
///
/// **Reduce Motion is answered by the schedule, not by a shorter animation.**
/// `tick(reduceMotion:)` puts a one-second floor under the redraws, so the arc
/// steps once a second instead of gliding at display rate — the same treatment
/// Keep Awake's countdown gets, where the digits cut rather than roll. It is
/// deliberately *not* «draw the spinner instead»: the person who has asked the
/// system for stillness is the one who would lose the only thing on this screen
/// that says how long the wait has left to run, and they would lose it to a
/// control that is spinning continuously anyway. Fifteen redraws of a 16 pt arc
/// over twenty seconds is less motion than the indicator it replaces, and it
/// still answers the question.
public struct HelmExpectedWait: View {

    /// **What may honestly be said about a wait, given a clock and nothing
    /// else.**
    ///
    /// A value rather than a `Double` with sentinels, because the three states
    /// are drawn by three different things and a fraction cannot carry «nobody
    /// saw this start». It is `public` and pure so the rule can be asserted —
    /// a decision made of arguments can be tested, a decision made inside a
    /// `body` can only be described.
    public enum Claim: Equatable {
        /// Nobody saw the wait begin, so there is no elapsed time and no
        /// fraction. Draws the indeterminate control.
        case unknown
        /// This far through the *expected* length. Strictly below 1: at the
        /// expected length the claim is withdrawn rather than parked, which is
        /// what stops this ever sitting at the end of its own track.
        case within(Double)
        /// Longer than expected. Draws the indeterminate control, which is the
        /// motion saying «I no longer know», in the only vocabulary the app has
        /// for it.
        case overrun

        /// The whole honesty of this component, as one function.
        ///
        /// Every refusal falls to `unknown`, which is the safe direction: it
        /// draws what the app drew before this existed. A clock that went
        /// backwards under the run — an NTP step, a laptop resuming — is one of
        /// them, because a negative elapsed time is not a small fraction, it is
        /// evidence that the stamp cannot be trusted.
        public static func at(_ now: Date, started: Date?,
                              expected: TimeInterval) -> Claim {
            guard let started, expected > 0 else { return .unknown }
            let elapsed = now.timeIntervalSince(started)
            guard elapsed >= 0 else { return .unknown }
            guard elapsed < expected else { return .overrun }
            return .within(elapsed / expected)
        }
    }

    /// How often the arc may be redrawn, in seconds — `nil` meaning «whenever
    /// the display can».
    ///
    /// An argument rather than a read of `NSWorkspace`, for the reason
    /// `HelmMotion.spins(requested:reduceMotion:)` is: a check that consults the
    /// machine only proves the machine it ran on was set the way the test
    /// assumed.
    public static func tick(reduceMotion: Bool) -> Double? {
        reduceMotion ? 1 : nil
    }

    /// The arc's width. Two points is the weight macOS draws a small
    /// determinate indicator at, and it is the weight of the spinner this
    /// stands in for.
    private static let stroke: CGFloat = 2

    private let started: Date?
    private let expected: TimeInterval
    private let diameter: CGFloat

    /// `started` is **optional on purpose and there is no default**: the caller
    /// has to have an answer to «did you see this begin», because `nil` is a
    /// real state of the screen rather than a value that was not to hand.
    ///
    /// `diameter` defaults to the size AppKit draws a small circular indicator
    /// at, so dropping this in beside a label leaves the row exactly the width
    /// it was — and both faces take the same frame, so the handover at overrun
    /// moves nothing either.
    public init(started: Date?, expected: TimeInterval, diameter: CGFloat = 16) {
        self.started = started
        self.expected = expected
        self.diameter = diameter
    }

    public var body: some View {
        // Paused when there is nothing to count: an unknown start draws one
        // still spinner and has no reason to wake the display for the rest of
        // the run.
        TimelineView(.animation(minimumInterval: Self.tick(reduceMotion: HelmMotion.reduceMotion),
                                paused: started == nil)) { context in
            face(Claim.at(context.date, started: started, expected: expected))
        }
        .frame(width: diameter, height: diameter)
        // The word beside it already says a measurement is running, and a
        // figure that changes on its own is a figure VoiceOver re-speaks while
        // it changes — the lesson Keep Awake's countdown carries. This is
        // decoration on a labelled row, so it is silent.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func face(_ claim: Claim) -> some View {
        switch claim {
        case .within(let fraction):
            ring(fraction)
        case .unknown, .overrun:
            // Not a variant of the ring, and not a bespoke spin. AppKit's own
            // indeterminate indicator is what this app already drew here, what
            // macOS draws for work of unknown length, and — the part that
            // matters for a fallback — the one control on the screen that
            // nothing in this file can get wrong.
            ProgressView().controlSize(.small)
        }
    }

    private func ring(_ fraction: Double) -> some View {
        ZStack {
            // The track. A literal opacity rather than `HelmText.separator`,
            // which is ink for a mark that carries meaning and measures far too
            // dark for a groove; `Color.primary` tracks light and dark by
            // itself.
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: Self.stroke)
            // The arc, in the ink of the word standing next to it, so the pair
            // reads as one statement rather than as a control and a caption.
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(HelmText.quiet,
                        style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round))
                // From the top, the way every clock face and every determinate
                // indicator macOS draws starts.
                .rotationEffect(.degrees(-90))
        }
        // A stroke is centred on its path, so half of it falls outside the
        // circle's own frame and is clipped by the row.
        .padding(Self.stroke / 2)
    }
}
