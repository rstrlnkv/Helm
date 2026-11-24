// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmUI
import Module_VPN_Engine

/// **Which of the tunnels that are up the card is about, as one value.**
///
/// A Mac with two tunnels up must be able to reach either. Separate from the
/// view for the reason `VPNTunnelStrip` gives, and from `VPNTunnelStrip`
/// because a hero with one tunnel may draw a strip and no segment at all.
struct VPNTunnelSwitcher {

    /// One tunnel's segment.
    struct Segment: Identifiable {
        /// The configuration's name, which is also what the person reads. Two
        /// configurations may share a display name; this inherits the ambiguity
        /// recorded at `VPNEngine.readInterfaces` rather than inventing a second
        /// identity.
        var id: String { name }
        let name: String
        /// **Whether this segment is one of several.**
        ///
        /// The accent fill is a *selection* mark, and a selection of one
        /// carries no information. A single segment (`drawn(beside:)`) keeps its
        /// dot and name on the plain well.
        let isOneOfSeveral: Bool
        /// Whether the traffic leaves through this one.
        ///
        /// **Not «is it connected»**: the engine lists only connected tunnels,
        /// so that mark would be the same on every segment. The route is what
        /// varies, and it decides whether the row has a button.
        let carriesTraffic: Bool
        let isSelected: Bool
    }

    /// Every tunnel that is up, in the engine's order. **What the row draws is
    /// `drawn(beside:)`**; building a view from this draws a selection of one.
    let segments: [Segment]
    /// The tunnel the hero draws: the one picked while it is still up,
    /// otherwise the first, the one carrying the traffic.
    let chosen: VPNTunnelState?

    init(_ tunnels: [VPNTunnelState], selected: String?) {
        let chosen = VPNTunnelChoice.chosen(selected, among: tunnels)
        self.chosen = chosen
        // Against the tunnel the hero is drawing, never the name the page
        // holds: a selection whose tunnel has dropped falls back, and the row
        // must light the same tunnel the hero draws.
        segments = tunnels.map {
            Segment(name: $0.name,
                    isOneOfSeveral: tunnels.count > 1,
                    carriesTraffic: $0.exit.carriesTheDefaultRoute,
                    isSelected: $0.name == chosen?.name)
        }
    }

    /// **What the hero's row of verbs actually draws**, which at one tunnel
    /// depends on what stands beside it.
    ///
    /// A lone segment selects between one thing, and the first tile's note
    /// already names the tunnel, so a lone pill would carry only the look of a
    /// control.
    ///
    /// **It is dropped only where a button stands beside it.** `.notOffered`
    /// leaves no control, and dropping the pill would leave the gap over a
    /// sentence with no row above it, in the state where the tunnel most needs
    /// naming. The switch is exhaustive so a fourth action is a decision about
    /// this row.
    func drawn(beside action: VPNTunnelStrip.Action) -> [Segment] {
        guard segments.count == 1 else { return segments }
        switch action {
        case .offer, .running: return []
        case .notOffered: return segments
        }
    }
}

/// The segments, as capsules in the hero's row of verbs.
///
/// **No wrapping row of its own.** It sits inside the hero's: a wrapping row
/// inside a wrapping row lays out against the wrong width.
///
/// **Capsules at the hero's verb height (`VPNTunnelHero.verbHeight`)**, so the
/// segments and the measure button share a top.
///
/// **Handed the segments, never the switcher**: the only way to get segments
/// here is through `VPNTunnelSwitcher.drawn(beside:)`, so no view can draw a
/// selection of one.
struct VPNTunnelSwitcherRow: View {
    private let segments: [VPNTunnelSwitcher.Segment]
    @Binding private var selected: String?

    init(_ segments: [VPNTunnelSwitcher.Segment], selected: Binding<String?>) {
        self.segments = segments
        _selected = selected
    }

    var body: some View {
        ForEach(segments) { segment in
                Button { selected = segment.name } label: {
                    HStack(spacing: HelmSpace.s3) {
                        // **The dot goes white on the filled segment.**
                        // `HelmSignal.success` falls under the 3:1 floor for a
                        // meaningful mark on the accent fill in both
                        // appearances; white clears it. Off the fill the green
                        // stands on `HelmSurface.wellFill`.
                        if segment.isSelected, segment.isOneOfSeveral {
                            Circle()
                                .fill(segment.carriesTraffic ? Color.white
                                                            : Color.white.opacity(0.45))
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                        } else {
                            HelmStatusDot(active: segment.carriesTraffic)
                        }
                        // Truncated in the middle: the opening of a long name is
                        // what tells two configurations apart.
                        Text(segment.name).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(segment.isSelected && segment.isOneOfSeveral
                                             ? Color.white : Color.primary)
                    }
                    .padding(.horizontal, HelmSpace.s6)
                    .frame(height: VPNTunnelHero.verbHeight)
                    // **The chosen one is filled by a shape this view draws,
                    // not by `.tint` on a `.bordered` button**: AppKit draws
                    // that fill in a material `cacheDisplay` does not
                    // composite, so a still could not check the selection.
                    .background(Capsule(style: .continuous)
                        .fill(segment.isSelected && segment.isOneOfSeveral
                              ? Color.accentColor : HelmSurface.wellFill))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The dot is hidden from VoiceOver (`HelmStatusDot`), so what it
                // marks is said in words, the headline's own sentence.
                .accessibilityLabel(segment.name)
                .accessibilityValue(segment.carriesTraffic ? VPNStr.trafficThroughTunnel : "")
            .accessibilityAddTraits(segment.isSelected ? [.isSelected] : [])
        }
    }
}
