import AppKit
import SwiftUI
import HelmUI
import Module_Leftovers_Engine

/// Scan, review, remove. Nothing is pre-selected: every item here is something
/// macOS loads, so each one is a deliberate choice.
public struct LeftoversSettingsPage: View {
    @StateObject private var lvm: LeftoversViewModel

    public init(vm: ModuleViewModel) {
        _lvm = StateObject(wrappedValue: LeftoversViewModel(vm: vm))
    }

    private var grouped: [(kind: StaleKind, items: [StaleItem])] {
        StaleKind.allCases.compactMap { kind in
            let items = lvm.visibleItems.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    private var selectedBytes: Int {
        lvm.items.filter { lvm.selected.contains($0.path) }.reduce(0) { $0 + $1.sizeBytes }
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            actionBar
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(lvm.items.isEmpty ? LfStr.intro : LfStr.reviewNote)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if !lvm.items.isEmpty {
                Picker("", selection: $lvm.showAll) {
                    Text(LfStr.filterLeftovers).tag(false)
                    Text(LfStr.filterAll).tag(true)
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(width: 180)
            }
            Button {
                Task { await lvm.scan() }
            } label: {
                if lvm.scanning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(LfStr.scanning)
                    }
                } else {
                    Text(lvm.scanned ? LfStr.rescan : LfStr.scan)
                }
            }
            .disabled(lvm.scanning)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        if lvm.items.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: lvm.scanned ? "checkmark.circle" : "wand.and.rays")
                    .font(.system(size: 30))
                    .foregroundStyle(lvm.scanned ? Color.green : Color.secondary)
                Text(lvm.scanned ? LfStr.nothingFound : LfStr.notScannedYet)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Spacer()
            }
            // A bounded minimum: enough to centre the message, without the
            // unbounded height that made the window grow to fill the screen.
            .frame(maxWidth: .infinity, minHeight: 260)
        } else {
            List {
                ForEach(grouped, id: \.kind) { group in
                    Section(LfStr.kindName(group.kind.rawValue)) {
                        ForEach(group.items) { item in
                            row(item)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .padding(.horizontal, 12)
        }
    }

    private func row(_ item: StaleItem) -> some View {
        HStack(spacing: 10) {
            if item.removable {
                Toggle("", isOn: Binding(
                    get: { lvm.selected.contains(item.path) },
                    set: { on in
                        if on { lvm.selected.insert(item.path) } else { lvm.selected.remove(item.path) }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            } else {
                // Keeps rows aligned where there is nothing to tick.
                Color.clear.frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.identifier)
                        .lineLimit(1)
                        .foregroundStyle(item.removable ? .primary : .secondary)
                    statusBadge(item.status)
                    if item.runAtLoad {
                        Text(LfStr.runsAtLogin)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.22)))
                    }
                }
                Text(item.path)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if let target = item.missingTarget {
                    Text(LfStr.missingTarget(target))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func statusBadge(_ status: ItemStatus) -> some View {
        let (text, color): (String, Color) = switch status {
        case .orphaned: (LfStr.statusOrphaned, .orange)
        case .inUse: (LfStr.statusInUse, .green)
        case .protectedItem: (LfStr.statusProtected, .secondary)
        }
        return Text(text)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.20)))
            .foregroundStyle(color)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button(LfStr.selectAll) {
                lvm.selected = Set(lvm.items.filter(\.removable).map(\.path))
            }
            .disabled(lvm.leftoverCount == 0)
            Button(LfStr.deselectAll) { lvm.selected.removeAll() }
                .disabled(lvm.selected.isEmpty)
            if !lvm.items.isEmpty {
                Text(LfStr.foundCount(lvm.leftoverCount,
                                      ByteCountFormatter.string(fromByteCount: Int64(selectedBytes),
                                                                countStyle: .file)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let banner = lvm.banner {
                Text(banner).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Button(LfStr.removeSelected) { Task { await lvm.removeSelected() } }
                .buttonStyle(.borderedProminent)
                .disabled(lvm.selected.isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}
