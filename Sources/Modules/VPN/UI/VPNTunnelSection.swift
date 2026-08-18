// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmUI
import Module_VPN_Engine

/// **What the strip draws, as one value.**
///
/// Separate from the view because every rule worth guarding here is a rule
/// about *content* — which tiles exist, what each says, which sentence the
/// verdict is — and none of it can be read back off a rendering: an
/// `NSHostingView`'s accessibility tree is empty outside a real client, and
/// SwiftUI draws its own type rather than through `NSTextField`. A view whose
/// content is a value is a view whose content has a test
/// (`TheStripDrawsOnlyWhatIsKnownTests`); a view that decides in its `body` has
/// prose instead.
struct VPNTunnelStrip {

    /// What the verdict line wears beside its sentence. Three, not a boolean:
    /// a check that could not be made must never be dressed as the bad answer
    /// (`VPNExitVerdict`).
    ///
    /// The glyph and the colour hang off the case rather than off two switches
    /// in the view, so a fourth answer is one place to fill in and a build
    /// error until it is.
    enum Mark: Equatable {
        case success, warning, neutral

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .neutral: "questionmark.circle"
            }
        }

        var tint: Color {
            switch self {
            case .success: HelmSignal.success
            case .warning: HelmSignal.warning
            // Quiet, never `danger`: a probe that failed is not bad news.
            case .neutral: HelmText.quiet
            }
        }
    }

    /// What sits at the right of the verdict line — the offer, the run that is
    /// already going, or the sentence that stands where neither belongs.
    ///
    /// One value, because the three are exclusive and a set of optionals can be
    /// several at once or none: a button drawn beside its own spinner is a
    /// second fifteen seconds of somebody's traffic one press away, and a button
    /// drawn beside the sentence explaining why there is no button is worse.
    enum Action: Equatable {
        case offer(String)
        case running(String)
        /// A tunnel that is not carrying the default route. The sentence, not a
        /// disabled button: nothing about *this* card can enable it, and a
        /// control that never becomes pressable is a control that has to be
        /// explained anyway.
        case notOffered(String)
    }

    /// Which reading a tile holds — the identity `ForEach` needs, and what a
    /// test asks about instead of matching a translated label.
    enum Reading: String { case uptime, down, up, speed }

    struct Tile: Identifiable {
        var id: Reading { kind }
        let kind: Reading
        let label: String
        let value: String
        /// The line under the figure. **Not optional, and that is the row's
        /// shape.** Three of the four columns had none, so the figures sat over
        /// nothing while the fourth carried a line — which was invisible while
        /// each column had a well behind it and is the whole structure now that
        /// they do not. A column with nothing to say under its figure is a
        /// column that has not been designed.
        let note: String
    }

    /// **The one dash in the strip, and it is the exception that proves the
    /// rule.** An absent reading is an absent tile everywhere else, because a
    /// dash there is a measurement of nothing; the speed tile stands empty
    /// because its emptiness is actionable — there is no passive way to read a
    /// link's throughput, and the button under it is the whole point.
    static let noReading = "—"

    let tiles: [Tile]
    let verdict: String
    let mark: Mark
    let action: Action

    /// **`measuring` defaults to the state's own answer, not to false.**
    ///
    /// The state already carries whether a run is in flight — it is the engine's
    /// fact, on the wire for exactly that reason — and the parameter is the page
    /// putting the press in front of it during the moment the command is
    /// crossing the queue (`VPNViewModel.measuring`). Defaulted to `false` the
    /// two disagreed by construction: `VPNTunnelStrip(state)` drew the button
    /// over a running measurement, which is why every test here had to pass
    /// `measuring:` by hand to see the state the state was already in.
    init(_ state: VPNTunnelState, now: Date = Date(), measuring: Bool? = nil) {
        let measuring = measuring ?? state.measuring
        let facts = VPNTunnelFacts(since: state.since, bytesIn: state.bytesIn,
                                   bytesOut: state.bytesOut, speed: state.speed, now: now)
        var tiles: [Tile] = []
        // Each of the three is drawn only if it was actually read. Nil here is
        // never zero: nobody saw the tunnel come up, or the kernel had no
        // counters for its interface.
        if let uptime = facts.uptime {
            tiles.append(Tile(kind: .uptime, label: VPNStr.tileUptime,
                              value: HelmDates.span(uptime),
                              note: VPNStr.tunnelAndInterface(state.name, state.interface)))
        }
        if let bytesIn = facts.bytesIn {
            tiles.append(Tile(kind: .down, label: VPNStr.tileDown,
                              value: Bytes(Int(clamping: bytesIn)), note: VPNStr.bytesSince))
        }
        if let bytesOut = facts.bytesOut {
            tiles.append(Tile(kind: .up, label: VPNStr.tileUp,
                              value: Bytes(Int(clamping: bytesOut)), note: VPNStr.bytesSince))
        }
        tiles.append(Self.speedTile(facts, now: now,
                                    offered: state.exit.carriesTheDefaultRoute))
        self.tiles = tiles

        switch state.exit {
        case .throughTunnel(let countryCode):
            // The place is named out of `Locale` in Helm's own language, and
            // the sentence loses its dash rather than its end when the code is
            // absent or is not a region.
            if let named = countryCode.flatMap(VPNStr.country) {
                verdict = VPNStr.trafficThroughTunnel(country: named)
            } else {
                verdict = VPNStr.trafficThroughTunnel
            }
            mark = .success
        case .besideTunnel:
            verdict = VPNStr.trafficBesideTunnel
            mark = .warning
        case .unknown:
            verdict = VPNStr.trafficUnknown
            mark = .neutral
        }

        // **The offer belongs to the tunnel holding the default route, and to
        // no other.** One predicate, read here and by the engine that refuses
        // the same command (`VPNExitVerdict.carriesTheDefaultRoute`) — the view
        // is not the only thing that can send one, and a rule spelled twice is
        // a rule two targets can disagree about.
        if measuring {
            action = .running(VPNStr.measuring)
        } else if state.exit.carriesTheDefaultRoute {
            // «Measure again» rather than «Measure speed» once a figure sits in
            // the tile: the press replaces a stale number, it does not produce
            // the first one.
            action = .offer(facts.speed == nil ? VPNStr.measureSpeed : VPNStr.measureAgain)
        } else {
            action = .notOffered(VPNStr.speedIsTheRoutedTunnels)
        }
    }

    /// The fourth column: a figure once one has been asked for, and before that
    /// the offer with its price on it.
    ///
    /// The note always opens with the unit, because this column's value is two
    /// numbers and cannot carry one the way a byte figure does — and what
    /// follows the unit is the one thing worth qualifying it with. The age is
    /// there exactly when `VPNTunnelFacts.speedIsStale` says the figure can no
    /// longer stand as the link's speed now, which is that property's own doc
    /// comment and this is its only reader; a fresh reading keeps the unit
    /// alone. Written the other way round (an age under every reading) the
    /// property would be a promise with nothing keeping it.
    private static func speedTile(_ facts: VPNTunnelFacts, now: Date,
                                  offered: Bool) -> Tile {
        guard let speed = facts.speed else {
            // `speedNotYet` is the **button's price tag** — fifteen seconds and
            // some traffic — so it is quoted only where there is a button to
            // pay it. On a tunnel that is not carrying the route the note is the
            // unit alone, and the sentence on the verdict line says why.
            return Tile(kind: .speed, label: VPNStr.tileSpeed, value: noReading,
                        note: VPNStr.speedNote(offered ? VPNStr.speedNotYet : nil))
        }
        return Tile(kind: .speed, label: VPNStr.tileSpeed,
                    // `Count`, not `Decimal`: the figure is a whole number of
                    // megabits and wants the language's digit grouping. Written
                    // `Decimal(speed.down)` it did not even reach `HelmUI` —
                    // that member takes a `Double` and `down` is an `Int`, so the
                    // call bound to `Foundation.Decimal.init(_: Int)` and drew its
                    // locale-independent description: «10000» for a 10 Gbit link.
                    value: "\(Count(speed.down)) ↓  \(Count(speed.up)) ↑",
                    note: VPNStr.speedNote(facts.speedIsStale
                        ? HelmDates.relative(speed.at, to: now) : nil))
    }
}

/// **What the tunnel carrying the default route is doing, right now.**
///
/// The one thing this page can say that a card cannot. A card knows its own
/// configuration is connected; only the page knows which tunnel the traffic is
/// actually leaving through, how long it has been that way, and what it has
/// carried — so the strip is per page and reads one tunnel rather than being
/// drawn four times over.
///
/// **No card of its own, and no heading either.** On the settings page this is
/// a row of a grouped `Form`, and the section card the form draws *is* the
/// card; the heading belongs to that section's header, which sits outside it
/// (`VPNTunnelStrip.heading`).
///
/// **And no wells.** The four columns were recessed fills
/// (`HelmSurface.wellFill`), which drew four boxes where the page wanted one
/// row of four readings — a card of cards. They are separated by whitespace
/// now, and what makes them read as one row is that every column has the same
/// three lines. Hairline rules between them were drawn and rejected by
/// looking: at 40 pt they begin at the label and end inside the note, so they
/// read as fragments rather than as structure. The horizontal `Divider()`
/// below stays, because that one separates two different kinds of thing.
struct VPNTunnelSection: View {
    private let tunnels: [VPNTunnelState]
    @Binding private var selected: String?
    private let now: Date
    /// The name of the tunnel a run is in flight for, or nil. A name rather
    /// than a flag, so a spinner turns over the tunnel being measured and not
    /// over whichever one the switcher happens to be showing.
    private let measuring: String?
    private let measure: (String) -> Void

    init(_ tunnels: [VPNTunnelState], selected: Binding<String?>, now: Date = Date(),
         measuring: String? = nil, measure: @escaping (String) -> Void) {
        self.tunnels = tunnels
        _selected = selected
        self.now = now
        self.measuring = measuring
        self.measure = measure
    }

    var body: some View {
        // Resolved here rather than in `init`, because the choice depends on a
        // binding: the page holds the selection and the engine rewrites the
        // list under it, and a value computed once at construction would be the
        // answer to a question asked before either could move.
        let switcher = VPNTunnelSwitcher(tunnels, selected: selected)
        return Group {
            if let chosen = switcher.chosen {
                card(switcher, chosen)
            }
        }
    }

    private func card(_ switcher: VPNTunnelSwitcher, _ chosen: VPNTunnelState) -> some View {
        let strip = VPNTunnelStrip(chosen, now: now, measuring: measuring == chosen.name)
        return VStack(alignment: .leading, spacing: HelmSpace.s5) {
            // Above the columns and inside the card: the segments say which
            // tunnel every figure below is about, so they read as that row's
            // heading rather than as a control belonging to the page.
            if !switcher.segments.isEmpty {
                VPNTunnelSwitcherRow(switcher, selected: $selected)
            }
            HStack(alignment: .top, spacing: HelmSpace.s4) {
                ForEach(strip.tiles) { column(_: $0) }
            }
            // The row takes the height of its tallest column and no more.
            // Without it a container taller than the strip stretches it: the
            // wells this replaced were photographed at 190 pt with 100 pt of
            // empty fill under the figures.
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            verdictLine(strip, chosen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One reading: what it is, the figure, and the line that qualifies it.
    ///
    /// `maxWidth: .infinity` on each is what makes the four equal, and the only
    /// thing that does now that there is no fill to see the edges of.
    private func column(_ tile: VPNTunnelStrip.Tile) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            Text(tile.label)
                // 10, the scale's bottom step: a caption over a figure.
                .font(.system(size: 10))
                .foregroundStyle(HelmText.quiet)
                .lineLimit(1)
            Text(tile.value)
                .helmMetricFigure()
            Text(tile.note)
                .font(.system(size: 10))
                .foregroundStyle(HelmText.faint)
                // Wrapping rather than truncating: a note that loses its tail
                // loses the interface out of «incy · utun8», and a tunnel named
                // at length in System Settings is an ordinary Mac. The columns
                // are top-aligned, so a second line lengthens one column
                // without moving a figure beside it.
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func verdictLine(_ strip: VPNTunnelStrip,
                             _ chosen: VPNTunnelState) -> some View {
        HStack(spacing: HelmSpace.s3) {
            Image(systemName: strip.mark.symbol)
                .foregroundStyle(strip.mark.tint)
                // Decoration: the sentence beside it says the same thing, and a
                // screen reader that read both would say it twice.
                .accessibilityHidden(true)
            Text(strip.verdict)
                .font(HelmText.rowTitle)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: HelmSpace.s5)
            switch strip.action {
            case .offer(let word):
                Button(word) { measure(chosen.name) }
            case .running(let word):
                HStack(spacing: HelmSpace.s3) {
                    ProgressView().controlSize(.small)
                    Text(word)
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.quiet)
                }
            case .notOffered(let sentence):
                Text(sentence)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    // Wrapping, and trailing-aligned where the button was: it
                    // is a sentence rather than a word, and at the narrow pane
                    // it takes two lines beside a verdict that takes two of
                    // its own.
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
