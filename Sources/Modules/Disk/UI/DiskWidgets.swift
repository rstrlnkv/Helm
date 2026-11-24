import SwiftUI
import HelmUI
import Module_Disk_Engine

/// The disk in the panel: how much room is left, out of how much there is.
///
/// **This one costs a volume-attributes read, not a scan.** What is taking up
/// the space has to be walked for, and the panel must never start a walk.
/// Capacity and free space the filesystem answers at once.
struct DiskWidget: View {
    @ObservedObject private var vm: DiskViewModel
    private let size: PanelWidgetSize

    init(model: DiskViewModel, size: PanelWidgetSize) {
        self.vm = model
        self.size = size
    }

    /// The boot volume, which is the one «the disk» means. Falling back to the
    /// first rather than to nothing: a Mac booted from an external disk still
    /// has one volume it runs on, and it is the one at the top of the list.
    private var main: VolumeInfo? {
        vm.volumes.first { $0.path == "/" } ?? vm.volumes.first
    }

    var body: some View {
        HelmWidgetBody {
            HelmWidgetHeader(symbol: DiskDescriptor.metadata.sfSymbol, tint: DiskDescriptor.tint.colour,
                             name: DkStr.moduleName, compact: size == .compact) {
                OpenTheModule()
            }
            if let main {
                HelmWidgetFigure(Bytes(main.freeBytes), DkStr.free, size)
                if size != .compact {
                    CapacityBar(volume: main, height: 5, warnsWhenFull: true)
                    HelmWidgetRow(main.name, DkStr.usedOfTotal(main))
                }
                if size == .tall {
                    // Why that number is that number: every volume the Mac has,
                    // because the free space somebody is looking for is often
                    // on the other one.
                    ForEach(vm.volumes.filter { $0.path != main.path }) { volume in
                        HelmWidgetRow(volume.name,
                                      DkStr.freeAmount(volume.freeBytes))
                    }
                }
            } else {
                // Before the first answer comes back, not «0 free».
                HelmWidgetUnmeasured("…")
            }
        }
        .task {
            // **Every time it is shown**, not once per launch: the model lives as
            // long as the module does, and a disk can fill up while Helm runs.
            // The read is a volume-attributes read.
            await vm.appear()
        }
    }
}

/// Used against total, on the module's page and on its tile.
///
/// `warnsWhenFull` turns the used part red past 90 %: 10 % free is where macOS
/// itself starts warning. The tile asks for it; the page's volume cards do not.
struct CapacityBar: View {
    let volume: VolumeInfo
    let height: CGFloat
    var warnsWhenFull = false

    var body: some View {
        GeometryReader { proxy in
            let ratio = volume.totalBytes > 0
                ? Double(volume.usedBytes) / Double(volume.totalBytes) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(DiskPalette.capacityTrack)
                Capsule()
                    .fill(warnsWhenFull && ratio > 0.9 ? HelmSignal.danger : DiskPalette.capacityUsed)
                    .frame(width: proxy.size.width * ratio)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The way from the tile into the module, and it is a chevron.
///
/// The tile answers how much is free; *what is taking the space* has to be
/// walked for, which the panel never starts. This is the way onwards to the
/// page that can answer it.
///
/// Quiet on purpose. `HelmText.faint` and a caption-sized glyph, in the header's
/// own trailing slot where VPN puts its dot: the tile's subject is the figure.
/// Named, because a control whose whole face is a glyph is invisible to VoiceOver.
private struct OpenTheModule: View {
    var body: some View {
        Button {
            // The panel's own route, and the only one: `.helmOpenSettings`
            // carries a module id and the host brings that page up.
            NotificationCenter.default.post(name: .helmOpenSettings,
                                            object: DiskDescriptor.id.rawValue)
        } label: {
            Image(systemName: "chevron.right")
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.faint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DkStr.openTheModule)
    }
}
