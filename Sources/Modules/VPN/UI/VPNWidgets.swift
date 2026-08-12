import SwiftUI
import HelmUI

/// VPN at 1×1: how many are up, out of how many there are.
///
/// Not the default connection's name and a switch — that is the 2×1 tile, and
/// it needs a button. What fits in a square is the count, and the count is what
/// somebody is checking when they glance at the panel: nothing up when
/// something should be is the whole question.
struct VPNCompactWidget: View {
    @ObservedObject private var vm: VPNViewModel

    init(vm: VPNViewModel) { self.vm = vm }

    /// **`isConnected`, not `isUp`.** This is the number `isConnected`'s own doc
    /// comment was written about: `isUp` includes `.connecting`, so the figure
    /// counted a tunnel that had not come up and the dot beside it went green for
    /// it — the smallest surface in the app, saying the Mac is protected while a
    /// handshake is still out. The tile next door drew its dot the same way.
    private var up: Int { vm.connections.filter { $0.status.isConnected }.count }

    var body: some View {
        HelmWidgetBody {
            HelmWidgetHeader(symbol: "lock.shield", tint: VPNDescriptor.tint.colour,
                             name: VPNDescriptor.metadata.name,
                             active: up > 0, compact: true) {
                if up > 0 {
                    Circle().fill(HelmSignal.success).frame(width: 6, height: 6)
                }
            }
            if vm.connections.isEmpty {
                HelmWidgetUnmeasured(VPNStr.noVPNs)
            } else {
                HelmWidgetFigure("\(up)/\(vm.connections.count)", VPNStr.connections, .compact)
            }
        }
    }
}
