import SwiftUI
import HelmUI
import Module_Disk_Engine

/// The disk in the panel: how much room is left, out of how much there is.
///
/// **This one costs a `statfs`, not a scan.** Everything else the Disk module
/// knows — what is taking up the space — has to be walked for, and a widget
/// that started a walk when the panel opened would be the worst thing in the
/// app. Capacity and free space are a question the filesystem answers
/// immediately, they are the two numbers somebody opens a disk tool to see
/// first, and until now the only way to see them in Helm was to open its page.
public struct DiskWidget: View {
    @ObservedObject private var vm: DiskViewModel
    private let size: PanelWidgetSize

    public init(vm: ModuleViewModel, size: PanelWidgetSize) {
        self.vm = DiskViewModel.shared(vm: vm)
        self.size = size
    }

    /// The boot volume, which is the one «the disk» means. Falling back to the
    /// first rather than to nothing: a Mac booted from an external disk still
    /// has one volume it runs on, and it is the one at the top of the list.
    private var main: VolumeInfo? {
        vm.volumes.first { $0.path == "/" } ?? vm.volumes.first
    }

    public var body: some View {
        HelmWidgetBody {
            HelmWidgetHeader(symbol: "chart.pie", tint: DiskDescriptor.tint.colour,
                             name: DkStr.moduleName)
            if let main {
                HelmWidgetFigure(Bytes(main.freeBytes), DkStr.free, small: size == .compact)
                if size != .compact {
                    CapacityBar(volume: main)
                    HelmWidgetRow(main.name, Bytes(main.usedBytes) + " / " + Bytes(main.totalBytes))
                }
                if size == .tall {
                    // Why that number is that number: every volume the Mac has,
                    // because the free space somebody is looking for is often
                    // on the other one.
                    ForEach(vm.volumes.filter { $0.path != main.path }) { volume in
                        HelmWidgetRow(volume.name,
                                      Bytes(volume.freeBytes) + " " + DkStr.free)
                    }
                }
            } else {
                // Before the first answer comes back, not «0 free».
                HelmWidgetUnmeasured("…")
            }
        }
        .task {
            // Asked once, and only if nobody has asked yet: `shared(vm:)` means
            // the page and the widget are looking at the same list.
            if vm.volumes.isEmpty { await vm.loadVolumes() }
        }
    }
}

/// Used against total. The same drawing the module's own page uses, at the
/// height a widget can spare.
private struct CapacityBar: View {
    let volume: VolumeInfo

    var body: some View {
        GeometryReader { proxy in
            let ratio = volume.totalBytes > 0
                ? Double(volume.usedBytes) / Double(volume.totalBytes) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                // Red when what is left stops being a comfort. 10% is where
                // macOS itself starts warning, and a bar that stays calm to
                // the last byte is a bar nobody reads.
                Capsule()
                    .fill(ratio > 0.9 ? HelmSignal.danger : Color.accentColor.opacity(0.75))
                    .frame(width: proxy.size.width * ratio)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}
