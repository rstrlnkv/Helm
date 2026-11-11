import SwiftUI
import HelmUI

/// VPN at 1×1: how many are up, out of how many there are.
///
/// Not every connection with its switch — that is the 2×1 tile, and it needs
/// a row each. What fits in a square is the count, and the count is what
/// somebody is checking when they glance at the panel: nothing up when
/// something should be is the whole question.
struct VPNCompactWidget: View {
    @ObservedObject private var vm: VPNViewModel

    init(vm: VPNViewModel) { self.vm = vm }

    /// **`isConnected`, not `isUp`.** `isUp` includes `.connecting`, and a figure
    /// or dot that counted it would say the Mac is protected while a handshake is
    /// still out.
    var up: Int { vm.connections.filter { $0.status.isConnected }.count }

    var body: some View {
        HelmWidgetBody {
            HelmWidgetHeader(symbol: "lock.shield", tint: VPNDescriptor.tint.colour,
                             name: VPNDescriptor.metadata.name,
                             active: up > 0, compact: true) {
                if up > 0 {
                    HelmStatusDot(active: true, size: .widget)
                }
            }
            if vm.connections.isEmpty {
                HelmWidgetUnmeasured(VPNStr.noVPNs())
            } else {
                HelmWidgetFigure("\(up)/\(vm.connections.count)", VPNStr.connections(), .compact)
            }
        }
    }
}
