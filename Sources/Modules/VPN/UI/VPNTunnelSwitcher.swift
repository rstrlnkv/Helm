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
                    carriesTraffic: $0.exit.carriesTheDefaultRoute,
                    isSelected: $0.name == chosen?.name)
        }
    }
}

/// The row of segments above the columns.
///
/// **`HelmWrappingRow`, not an `HStack`**: a Mac can hold six configurations and
/// have several up, and a row that squeezes turns every name into an ellipsis at
/// the pane's width. The wrapping row gives an over-wide child a line of its own,
/// which is what the names here need.
struct VPNTunnelSwitcherRow: View {
    private let switcher: VPNTunnelSwitcher
    @Binding private var selected: String?

    init(_ switcher: VPNTunnelSwitcher, selected: Binding<String?>) {
        self.switcher = switcher
        _selected = selected
    }

    var body: some View {
        HelmWrappingRow(spacing: 8, lineSpacing: HelmSpace.s3, alignment: .leading) {
            ForEach(switcher.segments) { segment in
                Button { selected = segment.name } label: {
                    HStack(spacing: HelmSpace.s3) {
                        HelmStatusDot(active: segment.carriesTraffic)
                        // Truncated in the middle, like the rule buttons one
                        // module over: a configuration named at length in
                        // System Settings is an ordinary Mac, and the opening
                        // of the name is what tells two of them apart.
                        Text(segment.name).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(segment.isSelected ? Color.white : Color.primary)
                    }
                    .padding(.horizontal, HelmSpace.s4)
                    .frame(height: 24)
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
                    .background(RoundedRectangle(cornerRadius: HelmRadius.ctl,
                                                 style: .continuous)
                        .fill(segment.isSelected ? Color.accentColor
                                                 : HelmSurface.onPanelFill))
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
}
