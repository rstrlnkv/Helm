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
struct DiskWidget: View {
    @ObservedObject private var vm: DiskViewModel
    private let size: PanelWidgetSize

    init(vm: ModuleViewModel, size: PanelWidgetSize) {
        self.vm = DiskViewModel.shared(vm: vm)
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
            HelmWidgetHeader(symbol: "chart.pie", tint: DiskDescriptor.tint.colour,
                             name: DkStr.moduleName, compact: size == .compact) {
                OpenTheModule()
            }
            if let main {
                HelmWidgetFigure(Bytes(main.freeBytes), DkStr.free, size)
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
            // **Every time it is shown**, not once per launch. `shared(vm:)`
            // lives as long as the app does, so `if vm.volumes.isEmpty` meant
            // the free space on this tile was the figure from the first opening
            // of the panel — for weeks, on a menu-bar app — and `CapacityBar`'s
            // red-over-90 % could never fire on a disk filling up while Helm
            // ran, which is the only way disks fill up. The panel rebuilds its
            // widgets on every opening, and this read is a `statfs`.
            await vm.loadVolumes()
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

/// The way from the tile into the module, and it is a chevron.
///
/// **What this tile answers and what it cannot.** Free space is a `statfs` — the
/// panel can have it instantly, which is why the tile exists. *What is taking
/// the space* has to be walked for, and a tile that started a walk when the
/// panel opened would be the worst thing in the app. So the tile always ends in
/// a question it is not allowed to answer, and until now it ended there with no
/// way onwards: the person closed the panel, found the Helm icon again, opened
/// Settings, and looked for Disk in the sidebar.
///
/// Quiet on purpose. `HelmText.faint` and a caption-sized glyph, in the header's
/// own trailing slot where VPN puts its dot — the tile's subject is the figure,
/// and a door that competes with it is a door in the wrong place. A chevron is
/// the one glyph that means «there is more, over there» without a word.
///
/// Named, because a control whose whole face is a glyph is invisible to anybody
/// using VoiceOver and `NamedControlsTests` scans the source for exactly this.
private struct OpenTheModule: View {
    var body: some View {
        Button {
            // The panel's own route, and the only one: `.helmOpenSettings`
            // carries a module id and the host brings that page up. A module
            // asking the shell for a window through a notification is the
            // pattern; a new `ModuleDescriptor` member for one caller is what
            // `headerAccessory` was.
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
