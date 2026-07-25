import AppKit
import SwiftUI
import HelmUI
import Module_Disk_Engine

/// Pick something to scan, watch the ring grow, read it, and empty the basket.
/// Result rendering lives in DiskResultView; this page owns the states and
/// the basket bar.
public struct DiskSettingsPage: View {
    @ObservedObject private var dvm: DiskViewModel
    @State private var hovered: String?
    @State private var confirming = false

    public init(vm: ModuleViewModel) {
        dvm = DiskViewModel.shared(vm: vm)
    }

    public var body: some View {
        VStack(spacing: 0) {
            switch dvm.phase {
            case .start: startState
            case .scanning: scanningState
            case .result: DiskResultView(dvm: dvm, hovered: $hovered)
            }
            if !dvm.basket.isEmpty || dvm.banner != nil {
                Divider()
                basketBar
            }
        }
        .task {
            dvm.expireIfStale()
            await dvm.loadVolumes()
        }
        .animation(HelmMotion.interface, value: dvm.phase)
        .confirmationDialog(DkStr.confirmTrash(dvm.basket.count, formatted(dvm.basketBytes)),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(DkStr.moveToTrash, role: .destructive) {
                Task { await dvm.emptyBasket() }
            }
            Button(DkStr.cancel, role: .cancel) {}
        }
    }

    // MARK: - Start

    private var startState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(DkStr.startHint)
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(dvm.volumes) { volume in
                    volumeCard(volume)
                }
                Button {
                    chooseFolder()
                } label: {
                    Label(DkStr.scanFolder, systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(20)
        }
    }

    private func volumeCard(_ volume: VolumeInfo) -> some View {
        Button {
            Task { await dvm.scan(path: volume.path) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.secondary)
                    Text(volume.name).font(.headline)
                    Spacer()
                    Text(formatted(volume.usedBytes) + " / " + formatted(volume.totalBytes))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    let ratio = volume.totalBytes > 0
                        ? Double(volume.usedBytes) / Double(volume.totalBytes) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.10))
                        Capsule().fill(Color.accentColor.opacity(0.75))
                            .frame(width: proxy.size.width * ratio)
                    }
                }
                .frame(height: 6)
                Text(formatted(volume.freeBytes) + " " + DkStr.free)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .helmCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scanning (only until the first partial snapshot arrives)

    private var scanningState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(DkStr.scanning).font(.headline)
            Button(DkStr.cancel) { dvm.cancel() }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Basket

    private var basketBar: some View {
        HStack(spacing: 10) {
            if dvm.basket.isEmpty {
                Text(dvm.banner ?? DkStr.emptyBasket)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(DkStr.basket): \(dvm.basket.count) · " + formatted(dvm.basketBytes))
                    .font(.system(size: 12, design: .monospaced))
                Spacer()
                Button(DkStr.moveToTrash) { confirming = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func formatted(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await dvm.scan(path: url.path) }
    }
}
