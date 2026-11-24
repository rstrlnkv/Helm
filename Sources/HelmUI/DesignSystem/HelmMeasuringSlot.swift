// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// **The card whose figure is being replaced, while it is being replaced.**
///
/// The figure steps back: for as long as a newer reading is on its way, it
/// drops from full ink to `HelmText.quiet`, the ink of its own label, so the
/// old answer is not presented as the current one. It stays readable; when the
/// run ends the ink comes back, over the new figure or the old one if the tool
/// refused.
///
/// It is a colour, never `.opacity`: animating opacity puts the subtree in an
/// offscreen layer, and dropping that layer makes hierarchical colours jump
/// (Architecture/DesignSystem.md § Motion). It reaches only the figure because
/// the card's label and note set their own `foregroundStyle`.
///
/// The edge sweeps: a short segment travels round the card's border for as
/// long as the run lasts, outlining the slot where the answer will land, which
/// also covers a card with no figure yet. The lap is far shorter than the
/// measurement on purpose: the tool reports nothing until it exits, so a lap as
/// long as the run would be a progress bar with no evidence behind it. A short
/// lap says «running», not «this far along». It is on the edge because an edge
/// is peripheral, as an ambient signal should be, and it is how macOS itself
/// marks something live.
///
/// Under Reduce Motion the border is drawn whole and still: a segment stepping
/// round once a second would leap, which is worse than the glide. The demotion
/// still happens, cut by `HelmMotion.disclosure`.
extension View {
    /// `measuring` is the engine's own fact — a run is in flight for this
    /// tunnel — and `false` is completely inert: no border, full ink, and a
    /// paused schedule that wakes nothing.
    public func helmMeasuringSlot(_ measuring: Bool) -> some View {
        modifier(HelmMeasuringSlot(measuring: measuring, lap: HelmMeasuringSlot.lap))
    }
}

struct HelmMeasuringSlot: ViewModifier {
    @Environment(\.helmTraits) private var traits


    /// How long the segment takes to get round, in seconds, chosen by
    /// rendering it: at 1 s it reads as agitation, and past about 4 s the eye
    /// follows it and asks where it is going.
    nonisolated static let lap: Double = 2.4

    /// How much of the border is lit at once, as a fraction of the perimeter.
    /// A sixth is long enough to read as a moving *thing* rather than a
    /// travelling dot, and short enough that the card is never nearly outlined.
    nonisolated static let segment: Double = 0.17

    /// Where the lit segment is, as two spans of the border's parametrisation:
    /// a segment crossing the origin is not one `trim(from:to:)`. Both are
    /// always returned, so there is no branch and the shape's identity never
    /// changes. Off the wrap, the second is empty.
    struct Sweep: Equatable {
        let first: ClosedRange<Double>
        let second: ClosedRange<Double>

        /// The head runs from 0 to 1 once per `lap`, taken off absolute time, so
        /// it is a pure function of the clock with no state to fall out of step.
        static func at(_ now: Date, lap: Double) -> Sweep {
            guard lap > 0 else { return Sweep(first: 0...0, second: 0...0) }
            let length = HelmMeasuringSlot.segment
            // Folded twice: `truncatingRemainder` keeps the dividend's sign, and
            // the interval is negative on a Mac whose clock reset to the Unix
            // epoch. One fold leaves the head in `-1..<0`, where `trim` is not
            // defined; a second puts it in `0..<1` for every clock.
            let turn = (now.timeIntervalSinceReferenceDate / lap)
                .truncatingRemainder(dividingBy: 1)
            let head = (turn + 1).truncatingRemainder(dividingBy: 1)
            let tail = head + length
            return Sweep(first: head...Swift.min(tail, 1),
                         second: 0...Swift.max(tail - 1, 0))
        }
    }

    /// The figure's ink, as arguments, the shape `HelmMotion.spins` set.
    /// `HelmText.quiet` and nothing quieter: a stale figure must stay readable,
    /// because it is the only reading the person has while a new one is taken.
    private static func ink(measuring: Bool) -> Color {
        measuring ? HelmText.quiet : .primary
    }

    let measuring: Bool
    let lap: Double

    /// What is drawn, against what has arrived. Seeded from the incoming value,
    /// so a card built while a run is already going does not play the demotion
    /// it missed.
    @State private var shown: Bool

    init(measuring: Bool, lap: Double) {
        self.measuring = measuring
        self.lap = lap
        _shown = State(initialValue: measuring)
    }

    func body(content: Content) -> some View {
        // No branch around `content`: an `if` inside a `ViewModifier` makes two
        // views, and no outside transaction can interpolate between them
        // (Architecture/DesignSystem.md § Motion).
        content
            .foregroundStyle(Self.ink(measuring: shown))
            .overlay(border)
            // Animated where the value lands: `.animation(_:value:)` on the
            // outside does not carry this shape.
            .onChange(of: measuring) { _, arrived in
                withAnimation(HelmMotion.disclosure) { shown = arrived }
            }
    }

    private var border: some View {
        TimelineView(.animation(paused: !shown)) { context in
            let sweep = Sweep.at(context.date, lap: lap)
            ZStack {
                // Reduce Motion takes the whole border at once and stands
                // still. Read from the environment (`helmTraits`); that a change
                // reaches this view without a relaunch is intended and untried.
                if traits.reducedMotion {
                    edge.trim(from: 0, to: 1).stroke(Self.lit, lineWidth: Self.weight)
                } else {
                    edge.trim(from: sweep.first.lowerBound, to: sweep.first.upperBound)
                        .stroke(Self.lit, style: Self.cap)
                    edge.trim(from: sweep.second.lowerBound, to: sweep.second.upperBound)
                        .stroke(Self.lit, style: Self.cap)
                }
            }
        }
        // The border belongs to the run, not to the card, so it goes when the
        // run does — inside the same transaction the ink moves in, because the
        // two are one statement.
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// The card's own outline. `HelmRadius.card` and `.continuous` because this
    /// is drawn on the shape `VPNTunnelHero.column` fills, and a border half a
    /// point off its own card is the kind of thing that reads as blur.
    private var edge: some Shape {
        RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
    }

    /// Not the module tint: a coloured edge would carry meaning by colour
    /// alone. `Color.primary` is the ink of every other mark on the card and
    /// tracks light and dark; at 0.38 it reads against the well without becoming
    /// a second border system.
    private static let lit = Color.primary.opacity(0.38)
    private static let weight: CGFloat = 1.5
    private static let cap = StrokeStyle(lineWidth: weight, lineCap: .round)
}
