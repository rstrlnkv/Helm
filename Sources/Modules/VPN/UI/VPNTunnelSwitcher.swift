// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmUI
import Module_VPN_Engine

/// **Which of the tunnels that are up the card is about, as one value.**
///
/// The strip has always been about one tunnel; what it lacked was a way to say
/// which, so a Mac with two up drew one of them and offered no way to reach the
/// other. Separate from the view for the reason `VPNTunnelStrip` records — every
/// rule here is about *content*, and none of it can be read back off a rendering
/// — and separate from `VPNTunnelStrip` because a card with one tunnel has a
/// strip and no switcher at all.
struct VPNTunnelSwitcher {

    /// One tunnel's segment.
    struct Segment: Identifiable {
        /// The configuration's name, which is also what the person reads. Two
        /// configurations may share a display name and the tool's own answers
        /// are then about whichever macOS picks — the ambiguity is recorded at
        /// `VPNEngine.readInterfaces` and this inherits it rather than inventing
        /// a second identity for the same thing.
        var id: String { name }
        let name: String
        /// **Whether this segment is one of several.**
        ///
        /// The accent fill is a *selection* mark, and a selection of one carries
        /// no information: measured off the render, the lone pill was the same
        /// 24 pt box at the same left edge with the same corner as «Measure
        /// speed» 93 pt below it — two identical rectangles, one of which does
        /// something. So a single segment keeps its dot and its name and loses
        /// the fill, and the row still does the job its own comment claims: it
        /// names the tunnel the figures are about and marks whether that tunnel
        /// carries the traffic.
        let isOneOfSeveral: Bool
        /// Whether the traffic leaves through this one.
        ///
        /// **Not «is it connected».** Every tunnel in this row is up by
        /// construction — the engine lists only connected ones — so a mark
        /// meaning connected would be the same mark on every segment, which is
        /// decoration wearing the clothes of information. What varies is the
        /// route, and the route is also what decides whether the card below has
        /// a button to press.
        let carriesTraffic: Bool
        let isSelected: Bool
    }

    /// The row, **drawn for one tunnel as well as for four**.
    ///
    /// It was hidden below two, on the reasoning that a control offering one
    /// choice is noise. True of a control and false of this one, which is why
    /// the reasoning was wrong: hidden at one tunnel — the ordinary Mac — the
    /// row was invisible to everybody who had never had two up at once, so the
    /// switching was reported as missing rather than as unnecessary. A single
    /// segment is a label that happens to be pressable: it names the tunnel
    /// every figure below is about, and it marks whether that one carries the
    /// traffic, which is the fact the dot is for and is not decoration at any
    /// count.
    let segments: [Segment]
    /// The tunnel the card draws — the one picked while it is still up, and
    /// otherwise the first, which is the one carrying the traffic.
    let chosen: VPNTunnelState?

    init(_ tunnels: [VPNTunnelState], selected: String?) {
        let chosen = VPNTunnelChoice.chosen(selected, among: tunnels)
        self.chosen = chosen
        // Against the tunnel the card is actually drawing, never against the
        // name the page is holding: a selection whose tunnel has dropped falls
        // back, and a row lighting the stale name would light a segment that is
        // not there while the card drew a different tunnel.
        segments = tunnels.map {
            Segment(name: $0.name,
                    isOneOfSeveral: tunnels.count > 1,
                    carriesTraffic: $0.exit.carriesTheDefaultRoute,
                    isSelected: $0.name == chosen?.name)
        }
    }
}

/// The segments, as capsules in the hero's row of verbs.
///
/// **No wrapping row of its own any more.** It had one, and it now sits inside
/// the hero's — a wrapping row inside a wrapping row lays its children out
/// against the wrong width and then centres the wrong thing. The segments are
/// contributed to the row around them; that row does the wrapping, and a Mac
/// with six tunnels up still gets an over-wide name on a line of its own.
///
/// **Capsules at 30 pt, which is `KeepAwakeHero`'s verb.** They were 24 pt
/// rounded rectangles at `HelmRadius.ctl` — the same box as a row control — and
/// the hero's shape is the one that page draws: a centred row of capsules under
/// a 40 pt sentence.
struct VPNTunnelSwitcherRow: View {
    private let switcher: VPNTunnelSwitcher
    @Binding private var selected: String?

    init(_ switcher: VPNTunnelSwitcher, selected: Binding<String?>) {
        self.switcher = switcher
        _selected = selected
    }

    var body: some View {
        ForEach(switcher.segments) { segment in
                Button { selected = segment.name } label: {
                    HStack(spacing: HelmSpace.s3) {
                        // **The dot goes white on the filled segment.**
                        // Measured off the render, `HelmSignal.success` on the
                        // accent is 1.11:1 in light and 2.06:1 in dark, against
                        // this house's 3:1 floor for a mark that carries
                        // meaning — the two colours were each solved against the
                        // *page* and never against each other. White on that
                        // fill measures 4.07:1. Off the fill the green stands as
                        // it did: 6.95:1 dark, 3.88:1 light on `onPanelFill`.
                        if segment.isSelected, segment.isOneOfSeveral {
                            Circle()
                                .fill(segment.carriesTraffic ? Color.white
                                                            : Color.white.opacity(0.45))
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                        } else {
                            HelmStatusDot(active: segment.carriesTraffic)
                        }
                        // Truncated in the middle, like the rule buttons one
                        // module over: a configuration named at length in
                        // System Settings is an ordinary Mac, and the opening
                        // of the name is what tells two of them apart.
                        Text(segment.name).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(segment.isSelected && segment.isOneOfSeveral
                                             ? Color.white : Color.primary)
                    }
                    .padding(.horizontal, HelmSpace.s6)
                    .frame(height: 30)
                    // **The chosen one is filled by a shape this view draws,
                    // not by `.tint` on a `.bordered` button.** Photographed
                    // offscreen at two and at five tunnels, the tinted control
                    // came out identical to its neighbours: AppKit draws that
                    // fill in a material `cacheDisplay` does not composite, so
                    // the one mark that says which tunnel the card is about
                    // could not be checked in a rendering — and a mark nobody
                    // can photograph is a mark nobody can guard. A SwiftUI
                    // shape composites, so the selection is now visible to the
                    // same still that checks everything else on this page.
                    .background(Capsule(style: .continuous)
                        .fill(segment.isSelected && segment.isOneOfSeveral
                              ? Color.accentColor : HelmSurface.onPanelFill))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The dot is hidden from VoiceOver (`HelmStatusDot`), so what it
                // marks is said in words here — and the same sentence the
                // headline uses, because it is the same fact.
                .accessibilityLabel(segment.name)
                .accessibilityValue(segment.carriesTraffic ? VPNStr.trafficThroughTunnel : "")
            .accessibilityAddTraits(segment.isSelected ? [.isSelected] : [])
        }
    }
}
