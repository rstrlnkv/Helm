import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Leftovers_Engine

/// Scan, review, remove. Nothing is pre-selected: every item here is something
/// macOS loads, so each one is a deliberate choice.
public struct LeftoversSettingsPage: View {
    @StateObject private var lvm: LeftoversViewModel
    @State private var diskAccess: PermissionState = .granted
    @State private var pendingDeletion: StaleItem?

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
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess, text: LfStr.removalNeedsAccess)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                Divider()
            }
            content
            Divider()
            actionBar
        }
        .task { diskAccess = PermissionCheck.currentFullDiskAccess() }
        .confirmationDialog(pendingDeletion.map { LfStr.confirmDeleteInUse($0.identifier) } ?? "",
                            isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible) {
            Button(LfStr.removeSelected, role: .destructive) {
                if let item = pendingDeletion { Task { await lvm.remove(item) } }
                pendingDeletion = nil
            }
            Button(LfStr.cancelAction, role: .cancel) { pendingDeletion = nil }
        }
        .animation(HelmMotion.interface, value: lvm.items.count)
        .animation(HelmMotion.interface, value: lvm.showAll)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(lvm.items.isEmpty ? LfStr.intro : LfStr.reviewNote)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if !lvm.items.isEmpty {
                Menu {
                    ForEach(StaleKind.allCases, id: \.self) { kind in
                        Toggle(LfStr.kindName(kind.rawValue), isOn: Binding(
                            get: { !lvm.hiddenKinds.contains(kind) },
                            set: { on in
                                if on { lvm.hiddenKinds.remove(kind) } else { lvm.hiddenKinds.insert(kind) }
                            }))
                    }
                } label: {
                    Label(LfStr.filter, systemImage: "line.3.horizontal.decrease")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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
            .transition(.opacity)
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
                    if item.disabled {
                        Text(LfStr.statusDisabled)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.22)))
                    } else {
                        statusBadge(item.status)
                    }
                    if item.runAtLoad {
                        Text(LfStr.runsAtLogin)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.22)))
                    }
                }
                if item.kind != .systemExtension {
                    Text(item.path)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                if let target = item.missingTarget {
                    Text(LfStr.missingTarget(target))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if item.actions.contains(.turnOff) {
                // Not everything here is rubbish to delete — most of it is
                // working software the user may simply want quiet.
                Button(item.disabled ? LfStr.enable : LfStr.disable) {
                    Task { await lvm.setDisabled(!item.disabled, item: item) }
                }
                .controlSize(.small)
            }
            if item.actions.contains(.systemSettings) {
                // Not a file: macOS removes an extension with its app, and SIP
                // stops anyone else from uninstalling it.
                Button(LfStr.manageExtensions) { PermissionCheck.openExtensionSettings() }
                    .controlSize(.small)
            } else {
                Text(Bytes(item.sizeBytes))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Menu {
                    Button(LfStr.reveal) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                    }
                    if item.actions.contains(.delete) {
                        Button(LfStr.deleteItem, role: .destructive) {
                            if LeftoverActions.needsConfirmation(item) {
                                pendingDeletion = item
                            } else {
                                Task { await lvm.remove(item) }
                            }
                        }
                    } else {
                        // Say why rather than hide it: the row looks broken
                        // otherwise, and the reason is not the user's fault.
                        Text(LfStr.needsAdmin)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
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
                                      Bytes(selectedBytes)))
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
