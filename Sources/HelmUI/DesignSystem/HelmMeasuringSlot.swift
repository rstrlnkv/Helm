// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// **The card whose figure is being replaced, while it is being replaced.**
///
/// Two things happen to a card under a running measurement, and they answer two
/// different questions.
///
/// **The figure steps back.** A card showing «343 ↓ 358 ↑» while a new reading
/// is being taken is presenting the old answer as the current one, unmarked.
/// So for exactly as long as a newer one is on its way, the figure drops from
/// full-strength ink to `HelmText.quiet` — the ink its own label is in. It is
/// still perfectly readable, which is the point: this is not a fade to nothing,
/// it is a demotion. The stale figure stops out-ranking the word above it and
/// rejoins the quiet register until it is either replaced or confirmed. When
/// the run ends the ink comes back, and whatever number is there then — the new
/// one, or the old one if the tool refused — arrives into a card brightening.
///
/// **It is a colour, and never `.opacity`.** Animating opacity puts the subtree
/// in an offscreen layer, and dropping that layer at the end makes hierarchical
/// colours jump — the "Automation" heading's defect, ARCHITECTURE.md § Motion.
/// Interpolating a literal `Color.primary.opacity(k)` moves the ink without
/// creating a layer at all, which is also why the value here is spelled as a
/// literal rather than as `.secondary`.
///
/// And it reaches **only the figure** by construction rather than by aim: the
/// card's label and note set their own `foregroundStyle`, so a style applied
/// from outside is overridden on both and inherited by the one `Text` that does
/// not set one. The label «Скорость» is not a stale claim and does not move.
///
/// **The edge sweeps.** A short segment travelling round the card's own border,
/// continuously, for as long as the run lasts. This is the half that answers the
/// state where there is no figure at all — a dash and a unit, nothing to
/// demote — because what it draws is the *slot*: it outlines exactly where the
/// answer is going to land.
///
/// **The lap is deliberately far shorter than the measurement, and that is the
/// whole honesty of it.** Nine or ten laps go by in one run. A segment that took
/// the length of the measurement to get round would be a progress bar bent into
/// a rectangle, which is precisely the claim there is no evidence for — the tool
/// runs down and up in parallel (`dl_phase_start == ul_phase_start`, measured)
/// and reports nothing at all until it exits. A short lap reads «running»; a
/// long one reads «this far along». Nothing here is a fraction of anything.
///
/// It is on the edge rather than over the surface for two reasons. A person
/// waiting on this measurement is looking at the button they pressed, forty
/// points above; an edge is peripheral, which is what an ambient signal should
/// be. And macOS itself says «something is live here» with an edge — the
/// screen-sharing border, the recording indicator — where a shimmer across a
/// surface is a web idiom on a surface that does not do that.
///
/// **Reduce Motion, and the schedule trick does not save this one.** A segment
/// stepping round a border once a second would arrive in eight great leaps,
/// which is more alarming than the glide, not less — so unlike
/// `HelmExpectedWait`, the answer here is not a coarser clock. The border is
/// drawn **whole and still**: the same statement — this card is the one being
/// worked on, this is where the answer lands — with no travel in it. The
/// demotion still happens, and `HelmMotion.disclosure` collapses it to a cut on
/// its own. Nothing is lost except the movement, which is the thing that was
/// asked to go.
public extension View {
    /// `measuring` is the engine's own fact — a run is in flight for this
    /// tunnel — and `false` is completely inert: no border, full ink, and a
    /// paused schedule that wakes nothing.
    func helmMeasuringSlot(_ measuring: Bool,
                           lap: Double = HelmMeasuringSlot.lap) -> some View {
        modifier(HelmMeasuringSlot(measuring: measuring, lap: lap))
    }
}

public struct HelmMeasuringSlot: ViewModifier {

    /// How long the segment takes to get round, in seconds.
    ///
    /// 2,4 — chosen by rendering it, not by arithmetic. At 1 s it reads as
    /// agitation, which is the wrong thing to say about a wait somebody was
    /// told would take twenty seconds; past about 4 s the eye starts to follow
    /// it round and ask where it is going, which is the reading this must not
    /// invite. Nine laps in a measurement is a cycle nobody can mistake for a
    /// journey.
    public nonisolated static let lap: Double = 2.4

    /// How much of the border is lit at once, as a fraction of the perimeter.
    /// A sixth is long enough to read as a moving *thing* rather than a
    /// travelling dot, and short enough that the card is never nearly outlined.
    public nonisolated static let segment: Double = 0.17

    /// **Where the lit segment is, as two spans of the border's own
    /// parametrisation.**
    ///
    /// Two, because a segment crossing the origin is not expressible as one
    /// `trim(from:to:)` — and they are always both returned rather than being
    /// chosen between, so there is no branch and therefore no frame on which the
    /// shape's identity changes. Off the wrap, the second is empty.
    public struct Sweep: Equatable {
        public let first: ClosedRange<Double>
        public let second: ClosedRange<Double>

        /// The head runs from 0 to 1 once per `lap`, taken off absolute time so
        /// it is a pure function of the clock with no state to fall out of step
        /// with — the same property that makes `HelmExpectedWait` measurable
        /// offscreen, and for the same reason.
        public static func at(_ now: Date, lap: Double,
                              segment: Double = HelmMeasuringSlot.segment) -> Sweep {
            guard lap > 0, segment > 0 else { return Sweep(first: 0...0, second: 0...0) }
            let length = Swift.min(segment, 1)
            // Folded twice on purpose. `truncatingRemainder` keeps the sign
            // of its *dividend*, and the interval is negative on any Mac whose
            // clock has reset — a dead battery boots at the Unix epoch, which
            // is well before 2001. One fold leaves the head in `-1..<0` and
            // hands `trim(from:to:)` a span it is not defined on; adding a
            // whole lap and folding again puts it in `0..<1` for every clock,
            // which is the parametrisation the border is drawn in.
            let turn = (now.timeIntervalSinceReferenceDate / lap)
                .truncatingRemainder(dividingBy: 1)
            let head = (turn + 1).truncatingRemainder(dividingBy: 1)
            let tail = head + length
            return Sweep(first: head...Swift.min(tail, 1),
                         second: 0...Swift.max(tail - 1, 0))
        }

        /// What is actually lit, which must be `segment` however the wrap
        /// falls — the property a test can hold the arithmetic to.
        public var lit: Double {
            (first.upperBound - first.lowerBound) + (second.upperBound - second.lowerBound)
        }
    }

    /// The figure's ink, as arguments — the shape `HelmMotion.spins` set, so
    /// the rule can be asserted rather than described.
    ///
    /// `HelmText.quiet` rather than something quieter still: it is a token whose
    /// contrast has been measured against every surface this app draws
    /// (4,92:1 light, 6,06:1 dark), and a stale figure must stay *readable* —
    /// somebody's last measurement is the only speed reading they have while a
    /// new one is being taken.
    public static func ink(measuring: Bool) -> Color {
        measuring ? HelmText.quiet : .primary
    }

    let measuring: Bool
    let lap: Double

    /// What is **drawn**, against what has arrived. Seeded from the incoming
    /// value rather than from a constant, so a card built while a run is
    /// already going does not play the demotion it missed — the law the hero's
    /// own `shown` obeys, one file over.
    @State private var shown: Bool

    init(measuring: Bool, lap: Double) {
        self.measuring = measuring
        self.lap = lap
        _shown = State(initialValue: measuring)
    }

    public func body(content: Content) -> some View {
        // **No branch around `content`, ever.** An `if` inside a `ViewModifier`
        // is SwiftUI being told the two sides are different views, and after
        // that no transaction on the outside can interpolate between them
        // (ARCHITECTURE.md § Motion, law 1). Both halves below are a value
        // handed to one unchanging tree.
        content
            .foregroundStyle(Self.ink(measuring: shown))
            .overlay(border)
            // Where the value **lands**. `.animation(_:value:)` on the outside
            // was measured doing nothing for this shape twice in this codebase;
            // a transaction at the point of the write is what carries it.
            .onChange(of: measuring) { _, arrived in
                withAnimation(HelmMotion.disclosure) { shown = arrived }
            }
    }

    private var border: some View {
        TimelineView(.animation(paused: !shown)) { context in
            let sweep = Sweep.at(context.date, lap: lap)
            ZStack {
                // Reduce Motion takes the whole border at once and stands
                // still. Read fresh inside the body, so turning the setting on
                // stops this without a relaunch.
                if HelmMotion.reduceMotion {
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

    /// **Not the module tint.** A coloured edge would be carrying colour and
    /// nothing else, which is the exact charge that took the tick and the
    /// warning triangle off this page's verdict. `Color.primary` is the ink
    /// every other mark on the card is made of and it tracks light and dark by
    /// itself; at 0,38 it reads clearly against the well without becoming a
    /// second border system on a page that has one card shape.
    private static let lit = Color.primary.opacity(0.38)
    private static let weight: CGFloat = 1.5
    private static let cap = StrokeStyle(lineWidth: weight, lineCap: .round)
}
