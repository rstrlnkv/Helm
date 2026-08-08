import SwiftUI
import HelmUI

/// VPN at 1×1: how many are up, out of how many there are.
///
/// Not the default connection's name and a switch — that is the 2×1 tile, and
/// it needs a button. What fits in a square is the count, and the count is what
/// somebody is checking when they glance at the panel: nothing up when
/// something should be is the whole question.
public struct VPNCompactWidget: View {
    @ObservedObject private var vm: VPNViewModel

    public init(vm: VPNViewModel) { self.vm = vm }

    private var up: Int { vm.connections.filter { $0.status.isUp }.count }

    public var body: some View {
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
