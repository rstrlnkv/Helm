// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// **A wait whose length somebody measured, drawn as the clock it is — and
/// which stops claiming anything the moment the clock runs out.**
///
/// For a run whose port reports only that it started and that it stopped, with
/// no stage or percentage to show: the page knows when it pressed and how long
/// the thing usually takes, so this draws that clock rather than a progress bar
/// implying a measurement nobody took.
///
/// `Claim` holds the design. `within` says how far the wait is through its usual
/// length, true of the clock and silent about the work. `overrun` says it has
/// taken longer than usual, so the arc never sits full at the end of its track.
/// `unknown` is a page that never saw the run start. The last two draw the
/// system's indeterminate spinner at the same size in the same slot, so nothing
/// moves at the handover.
///
/// No `Animation` token: this is redrawn from the clock, not moved. A long
/// linear transaction would need its `@State` to survive every rebuild of a
/// republishing page and could disagree with the truth; a `TimelineView`
/// cannot, since the fraction is a pure function of `context.date`
/// (Architecture/DesignSystem.md § Motion).
///
/// Under Reduce Motion the schedule steps once a second instead of gliding,
/// as Keep Awake's countdown does. Not the spinner instead: that would take the
/// only sign of how long is left from the person who asked for stillness, for
/// a control that spins anyway.
public struct HelmExpectedWait: View {
    @Environment(\.helmTraits) private var traits


    /// What may honestly be said about a wait, given a clock and nothing else:
    /// a value, because a fraction cannot carry «nobody saw this start».
    private enum Claim {
        /// Nobody saw the wait begin, so there is no elapsed time and no
        /// fraction. Draws the indeterminate control.
        case unknown
        /// This far through the *expected* length, strictly below 1: at the
        /// expected length the claim is withdrawn rather than parked.
        case within(Double)
        /// Longer than expected: the indeterminate control says «I no longer
        /// know».
        case overrun

        /// Every refusal falls to `unknown`, the safe direction. A clock that
        /// went backwards under the run (an NTP step, a laptop resuming) is one:
        /// a negative elapsed time means the stamp cannot be trusted.
        static func at(_ now: Date, started: Date?,
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
    private static func tick(reduceMotion: Bool) -> Double? {
        reduceMotion ? 1 : nil
    }

    /// The arc's width: the weight macOS draws a small determinate indicator
    /// at, and the weight of the spinner it stands in for.
    private static let stroke: CGFloat = 2

    private let started: Date?
    private let expected: TimeInterval
    private let diameter: CGFloat

    /// `started` is optional with no default: the caller must answer «did you
    /// see this begin», because `nil` is a real state of the screen.
    ///
    /// `diameter` defaults to AppKit's small circular indicator, and both faces
    /// take the same frame, so neither the row nor the handover moves.
    public init(started: Date?, expected: TimeInterval, diameter: CGFloat = 16) {
        self.started = started
        self.expected = expected
        self.diameter = diameter
    }

    public var body: some View {
        // Paused when there is nothing to count: an unknown start draws one
        // still spinner and has no reason to wake the display.
        TimelineView(.animation(minimumInterval: Self.tick(reduceMotion: traits.reducedMotion),
                                paused: started == nil)) { context in
            face(Claim.at(context.date, started: started, expected: expected))
        }
        .frame(width: diameter, height: diameter)
        // The word beside it already says a measurement is running, and a
        // figure that changes on its own is re-spoken by VoiceOver as it
        // changes, so this decoration is silent.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func face(_ claim: Claim) -> some View {
        switch claim {
        case .within(let fraction):
            ring(fraction)
        case .unknown, .overrun:
            // AppKit's own indeterminate indicator: what macOS draws for work of
            // unknown length, and the one control here nothing can get wrong.
            ProgressView().controlSize(.small)
        }
    }

    private func ring(_ fraction: Double) -> some View {
        ZStack {
            // The track: a literal opacity, since `HelmText.separator` is ink
            // for a mark and far too dark for a groove.
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
