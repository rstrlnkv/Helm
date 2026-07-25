import AppKit
import SwiftUI
import HelmUI
import Module_Disk_Engine

/// Three states in one page: pick something to scan, watch it scan, then read
/// the ring. The basket bar is always the last thing above the window edge, so
/// removal is one deliberate step away from browsing.
public struct DiskSettingsPage: View {
    @StateObject private var dvm: DiskViewModel
    @State private var hovered: String?
    @State private var confirming = false

    public init(vm: ModuleViewModel) {
        _dvm = StateObject(wrappedValue: DiskViewModel(vm: vm))
    }

    public var body: some View {
        VStack(spacing: 0) {
            switch dvm.phase {
            case .start: startState
            case .scanning: scanningState
            case .result: resultState
            }
            if !dvm.basket.isEmpty || dvm.banner != nil {
                Divider()
                basketBar
            }
        }
        .task {
            await dvm.loadVolumes()
        }
        .task {
            await dvm.observeProgress()
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

    // MARK: - Scanning

    private var scanningState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(DkStr.scanning).font(.headline)
            if let tick = dvm.tick {
                VStack(spacing: 4) {
                    Text("\(tick.files) · " + formatted(tick.bytes))
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                    Text(tick.path)
                        .font(.caption).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 420)
                }
            }
            Button(DkStr.cancel) { dvm.cancel() }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Result

    private var resultState: some View {
        VStack(spacing: 0) {
            breadcrumbs
            Divider()
            HStack(spacing: 0) {
                RingView(segments: segments,
                         focusName: dvm.focus?.name ?? "",
                         focusBytes: dvm.focus?.bytes ?? 0,
                         hovered: $hovered,
                         onSelect: { segment in dvm.drill(into: segment.path) },
                         onBack: { dvm.back() })
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 380)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(14)
                Divider()
                childList
            }
        }
    }

    private var segments: [RingSegment] {
        guard let focus = dvm.focus else { return [] }
        // Free space belongs to the volume, so it is only drawn at the root.
        let free = dvm.focusPath.count == 1 ? (dvm.result?.freeBytes ?? 0) : 0
        return RingLayout.layout(focus: node(from: focus), depthLevels: 3, freeBytes: free)
    }

    /// The UI works on the transported snapshot; RingLayout wants the engine's
    /// node type, so the focused subtree is rebuilt for it.
    private func node(from entry: DiskEntry) -> DiskNode {
        DiskNode(name: entry.name, path: entry.path, bytes: entry.bytes,
                 isDirectory: entry.isDirectory,
                 children: entry.children.map(node(from:)))
    }

    private var breadcrumbs: some View {
        HStack(spacing: 6) {
            ForEach(Array(dvm.focusPath.enumerated()), id: \.element.path) { index, entry in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Button(entry.name) { dvm.jump(to: index) }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == dvm.focusPath.count - 1 ? .primary : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let result = dvm.result {
                Text(DkStr.scannedIn(result.filesScanned,
                                     String(format: "%.1fs", result.seconds)))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Button(DkStr.newScan) { Task { await dvm.loadVolumes() }; dvm.cancel() }
                .controlSize(.small)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var childList: some View {
        List {
            ForEach(dvm.focus?.children ?? []) { child in
                childRow(child)
            }
        }
        .listStyle(.inset)
    }

    private func childRow(_ child: DiskEntry) -> some View {
        let removable = DiskSafety.isRemovable(child.path)
        return HStack(spacing: 8) {
            Image(systemName: child.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(hovered == child.path ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(child.name).lineLimit(1).truncationMode(.middle)
                if child.noAccess {
                    Text(DkStr.noAccess).font(.caption2).foregroundStyle(.orange)
                } else if !removable {
                    Text(DkStr.systemItem).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(formatted(child.bytes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            if removable {
                Button {
                    dvm.toggleBasket(child)
                } label: {
                    Image(systemName: dvm.isBasketed(child) ? "checkmark.circle.fill" : "plus.circle")
                        .foregroundStyle(dvm.isBasketed(child) ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help(DkStr.addToBasket)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? child.path : nil }
        .onTapGesture(count: 2) { dvm.drill(into: child.path) }
        .contextMenu {
            Button(DkStr.reveal) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: child.path)])
            }
        }
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
