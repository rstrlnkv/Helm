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

    /// What sits at the right of the verdict line — the offer, or the run that
    /// is already going.
    ///
    /// One value, because the two are exclusive and a pair of optionals can be
    /// both or neither: a button drawn beside its own spinner is a second
    /// fifteen seconds of somebody's traffic one press away.
    enum Action: Equatable {
        case offer(String)
        case running(String)
    }

    /// Which reading a tile holds — the identity `ForEach` needs, and what a
    /// test asks about instead of matching a translated label.
    enum Reading: String { case uptime, down, up, speed }

    struct Tile: Identifiable {
        var id: Reading { kind }
        let kind: Reading
        let label: String
        let value: String
        /// The line under the figure, for the tile that has one.
        let note: String?
    }

    /// **The one dash in the strip, and it is the exception that proves the
    /// rule.** An absent reading is an absent tile everywhere else, because a
    /// dash there is a measurement of nothing; the speed tile stands empty
    /// because its emptiness is actionable — there is no passive way to read a
    /// link's throughput, and the button under it is the whole point.
    static let noReading = "—"

    /// Which tunnel the four readings are about — the strip reads only the
    /// connection carrying the default route, not every card on the grid.
    let title: String
    let tiles: [Tile]
    let verdict: String
    let mark: Mark
    let action: Action

    init(_ state: VPNTunnelState, now: Date = Date(), measuring: Bool = false) {
        title = VPNStr.thisTunnel(state.name)
        let facts = VPNTunnelFacts(since: state.since, bytesIn: state.bytesIn,
                                   bytesOut: state.bytesOut, speed: state.speed, now: now)
        var tiles: [Tile] = []
        // Each of the three is drawn only if it was actually read. Nil here is
        // never zero: nobody saw the tunnel come up, or the kernel had no
        // counters for its interface.
        if let uptime = facts.uptime {
            tiles.append(Tile(kind: .uptime, label: VPNStr.tileUptime,
                              value: HelmDates.span(uptime), note: nil))
        }
        if let bytesIn = facts.bytesIn {
            tiles.append(Tile(kind: .down, label: VPNStr.tileDown,
                              value: Bytes(Int(clamping: bytesIn)), note: nil))
        }
        if let bytesOut = facts.bytesOut {
            tiles.append(Tile(kind: .up, label: VPNStr.tileUp,
                              value: Bytes(Int(clamping: bytesOut)), note: nil))
        }
        tiles.append(Self.speedTile(facts, now: now))
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

        if measuring {
            action = .running(VPNStr.measuring)
        } else {
            // «Measure again» rather than «Measure speed» once a figure sits in
            // the tile: the press replaces a stale number, it does not produce
            // the first one.
            action = .offer(facts.speed == nil ? VPNStr.measureSpeed : VPNStr.measureAgain)
        }
    }

    /// The fourth tile: a figure once one has been asked for, and before that
    /// the offer with its price on it.
    ///
    /// The age is drawn exactly when `VPNTunnelFacts.speedIsStale` says the
    /// figure can no longer stand as the link's speed now — which is that
    /// property's own doc comment, and this is its only reader. Written the
    /// other way round (an age under every reading) the property would be a
    /// promise with nothing keeping it.
    private static func speedTile(_ facts: VPNTunnelFacts, now: Date) -> Tile {
        guard let speed = facts.speed else {
            return Tile(kind: .speed, label: VPNStr.tileSpeed,
                        value: noReading, note: VPNStr.speedNotYet)
        }
        return Tile(kind: .speed, label: VPNStr.tileSpeed,
                    value: "\(Decimal(speed.down)) ↓  \(Decimal(speed.up)) ↑",
                    note: facts.speedIsStale
                        ? VPNStr.speedMeasured(HelmDates.relative(speed.at, to: now))
                        : nil)
    }
}

/// **What the tunnel carrying the default route is doing, right now.**
///
/// The one thing this page can say that a card cannot. A card knows its own
/// configuration is connected; only the page knows which tunnel the traffic is
/// actually leaving through, how long it has been that way, and what it has
/// carried — so the strip is per page and names its tunnel in the heading
/// rather than being drawn four times over.
///
/// No card of its own: on the settings page this is a row of a grouped `Form`,
/// and the section card the form draws *is* the card. The tiles are wells
/// inside it (`HelmSurface.wellFill`), which is what a recessed area in a card
/// is for — a `helmCard()` here would be a card inside a card.
struct VPNTunnelSection: View {
    private let strip: VPNTunnelStrip
    private let measure: () -> Void

    init(_ state: VPNTunnelState, now: Date = Date(), measuring: Bool = false,
         measure: @escaping () -> Void) {
        self.strip = VPNTunnelStrip(state, now: now, measuring: measuring)
        self.measure = measure
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            Text(strip.title)
                .font(HelmText.sectionHeading)
            HStack(alignment: .top, spacing: HelmSpace.s4) {
                ForEach(strip.tiles) { tile(_: $0) }
            }
            // The row takes the height of its tallest tile and no more. Without
            // it the `maxHeight` each tile carries — which is what makes the
            // four wells one height — reads as «fill whatever you are given»,
            // and a container taller than the strip stretches every well to
            // meet it. Photographed at 190 pt: 100 pt of empty well under the
            // figures.
            .fixedSize(horizontal: false, vertical: true)
            verdictLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ tile: VPNTunnelStrip.Tile) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s1) {
            Text(tile.label)
                // 10, the scale's bottom step: a caption over a figure.
                .font(.system(size: 10))
                .foregroundStyle(HelmText.faint)
            Text(tile.value)
                .helmMetricFigure()
            if let note = tile.note {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(HelmText.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HelmSpace.s4)
        // Equal wells whatever is in them: the speed tile carries a third line
        // for most of its life and the three beside it never do.
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                .fill(HelmSurface.wellFill)
        )
    }

    private var verdictLine: some View {
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
                Button(word, action: measure)
            case .running(let word):
                HStack(spacing: HelmSpace.s3) {
                    ProgressView().controlSize(.small)
                    Text(word)
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.quiet)
                }
            }
        }
    }
}
