import SwiftUI
import HelmUI
import Module_VPN_Engine

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
                             name: VPNDescriptor.metadata.name) {
                if up > 0 {
                    Circle().fill(HelmSignal.success).frame(width: 6, height: 6)
                }
            }
            if vm.connections.isEmpty {
                HelmWidgetUnmeasured(VPNStr.noVPNs)
            } else {
                HelmWidgetFigure("\(up)/\(vm.connections.count)", VPNStr.connections)
            }
        }
    }
}

/// VPN at 2×N: the control, and every connection it could be talking about.
///
/// The 2×1 tile answers for one — the default, or the one that is up. The
/// height is for the case that makes somebody open the panel at all: which of
/// the four is connected, and it is not the one they expected.
public struct VPNTallWidget: View {
    @ObservedObject private var vm: VPNViewModel

    public init(vm: VPNViewModel) { self.vm = vm }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VPNPanelTile(vm: vm)
            if !vm.connections.isEmpty {
                HelmWidgetBody {
                    ForEach(vm.connections) { connection in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(connection.status.isUp ? HelmSignal.success : HelmText.faint)
                                .frame(width: 6, height: 6)
                            HelmWidgetRow(connection.name, connection.kind)
                        }
                    }
                }
            }
        }
    }
}
