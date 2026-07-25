import AppKit
import SwiftUI
import HelmUI
import Module_Disk_Engine

/// Ring + breadcrumbs + the focused folder's contents. Lives while a scan is
/// still feeding data (`live`) and after it settles.
struct DiskResultView: View {
    @ObservedObject var dvm: DiskViewModel
    @Binding var hovered: String?

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbBar(dvm: dvm)
            Divider()
            HStack(spacing: 0) {
                RingView(segments: dvm.segments,
                         focusName: dvm.focus?.name ?? "",
                         focusBytes: dvm.focus?.bytes ?? 0,
                         growing: dvm.live,
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

    // MARK: - List

    private var childList: some View {
        List {
            ForEach(dvm.focus?.children ?? []) { child in
                ChildRow(child: child,
                         fraction: fraction(of: child),
                         hovered: $hovered,
                         basketed: dvm.isBasketed(child),
                         onToggleBasket: { dvm.toggleBasket(child) },
                         onDrill: { dvm.drill(into: child.path) })
            }
        }
        .listStyle(.inset)
    }

    private func fraction(of child: DiskEntry) -> Double {
        guard let total = dvm.focus?.bytes, total > 0 else { return 0 }
        return Double(child.bytes) / Double(total)
    }
}

// MARK: - Breadcrumbs

/// Back button first — the centre-click gesture is invisible, this is not.
/// Deep paths collapse their middle into a menu so the bar never squeezes the
/// current folder out.
private struct BreadcrumbBar: View {
    @ObservedObject var dvm: DiskViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                dvm.back()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(dvm.focusPath.count <= 1)
            .help(DkStr.back)

            crumbs

            Spacer(minLength: 12)

            if dvm.live {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    if let tick = dvm.tick {
                        Text(DkStr.liveCount(tick.files))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Button(DkStr.cancel) { dvm.cancel() }
                        .controlSize(.small)
                }
            } else if let result = dvm.result {
                Text(DkStr.scannedIn(result.filesScanned,
                                     String(format: "%.1fs", result.seconds)))
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Button(DkStr.newScan) { dvm.newScan() }
                .controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }

    @ViewBuilder private var crumbs: some View {
        let path = dvm.focusPath
        if path.count <= 4 {
            ForEach(Array(path.enumerated()), id: \.element.path) { index, entry in
                crumb(entry, index: index, isLast: index == path.count - 1)
            }
        } else {
            // Root, a menu holding the hidden middle, and the last two levels.
            crumb(path[0], index: 0, isLast: false)
            chevron
            Menu {
                ForEach(Array(path.enumerated().dropFirst().dropLast(2)),
                        id: \.element.path) { index, entry in
                    Button(entry.name) { dvm.jump(to: index) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            ForEach(Array(path.enumerated().suffix(2)), id: \.element.path) { index, entry in
                crumb(entry, index: index, isLast: index == path.count - 1)
            }
        }
    }

    @ViewBuilder private func crumb(_ entry: DiskEntry, index: Int, isLast: Bool) -> some View {
        if index > 0 { chevron }
        if isLast {
            // The current folder is a fact, not a control.
            Text(entry.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 180)
        } else {
            Button {
                dvm.jump(to: index)
            } label: {
                Text(entry.name)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 140)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.compact.right")
            .font(.system(size: 11))
            .foregroundStyle(.quaternary)
    }
}

// MARK: - Row

/// A row mirrors its wedge: same swatch, and a background bar whose width is
/// the item's share of the focused folder — the list reads as a bar chart.
private struct ChildRow: View {
    let child: DiskEntry
    let fraction: Double
    @Binding var hovered: String?
    let basketed: Bool
    let onToggleBasket: () -> Void
    let onDrill: () -> Void

    private var removable: Bool { DiskSafety.isRemovable(child.path) }
    private var isHovered: Bool { hovered == child.path }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(child.isDirectory ? DiskPalette.base(for: child.path)
                                        : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(child.name == "…" ? DkStr.otherItems : child.name)
                    .lineLimit(1).truncationMode(.middle)
                if child.noAccess {
                    Text(DkStr.noAccess).font(.caption2).foregroundStyle(.orange)
                } else if !removable {
                    Text(DkStr.systemItem).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(child.bytes), countStyle: .file))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            if removable {
                Button(action: onToggleBasket) {
                    Image(systemName: basketed ? "checkmark.circle.fill" : "plus.circle")
                        .foregroundStyle(basketed ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help(DkStr.addToBasket)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DiskPalette.base(for: child.path).opacity(0.16))
                    }
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DiskPalette.base(for: child.path).opacity(0.10))
                        .frame(width: max(proxy.size.width * fraction, 2))
                }
            }
        )
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? child.path : nil }
        .onTapGesture(count: 2) { onDrill() }
        .contextMenu {
            Button(DkStr.reveal) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: child.path)])
            }
        }
        .listRowSeparator(.hidden)
    }
}
