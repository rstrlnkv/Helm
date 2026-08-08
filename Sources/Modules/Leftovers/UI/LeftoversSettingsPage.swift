import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Leftovers_Engine

/// Scan, review, remove. Nothing is pre-selected: every item here is something
/// macOS loads, so each one is a deliberate choice.
public struct LeftoversSettingsPage: View {
    /// Observed, never owned: Settings tears this page down on every sidebar
    /// visit, and a `@StateObject` here took the scan and every checkbox with
    /// it. Nothing in this list is pre-ticked — each tick is a decision about a
    /// file macOS loads, and one sidebar click asked for all of them again.
    @ObservedObject private var lvm: LeftoversViewModel
    @State private var diskAccess: PermissionState = .granted
    @State private var confirmingBatch = false
    @State private var pendingDeletion: StaleItem?

    public init(vm: ModuleViewModel) {
        lvm = LeftoversViewModel.shared(vm: vm)
    }

    /// What the row's menu may call this. An ellipsis is a promise that another
    /// step follows; for a leftover none does, and the click deleted. Where no
    /// dialog follows the row says exactly what the bar below it says, because
    /// it is the same act.
    static func deleteLabel(for item: StaleItem) -> String {
        LeftoverActions.needsConfirmation(item) ? LfStr.deleteItem : LfStr.removeSelected
    }

    private var grouped: [(kind: StaleKind, items: [StaleItem])] {
        StaleKind.allCases.compactMap { kind in
            let items = lvm.visibleItems.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess, text: LfStr.removalNeedsAccess)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                Divider()
            }
            // The safety line, where the thing it is about is: over the list,
            // in the page's own copy rather than in its chrome. It says nothing
            // is ticked by default *because macOS loads these*, which is the
            // one sentence on this screen a person must not miss.
            if !lvm.items.isEmpty {
                Text(LfStr.reviewNote)
                    .font(.caption).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 10)
            }
            content
            Divider()
            actionBar
        }
        .helmOnAppActive { diskAccess = PermissionCheck.currentFullDiskAccess() }
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
        // **Controls, and no prose.** The sentence used to live here, beside
        // the scan button — a quiet caption at one end of a strip and a button
        // at the other, which is exactly the shape of the permission note
        // underneath it. Two bars of the same weight, stacked, read as one
        // thing said twice. Every other list screen puts controls here and
        // nothing else; this one does now too.
        HStack(spacing: 10) {
            Spacer(minLength: 8)
            if !lvm.items.isEmpty {
                // What the scan found, beside the control that filters it. It
                // used to sit in the bar at the bottom joined to the size of the
                // selection, where the two read as one measurement.
                Text(LfStr.foundLine(lvm.leftoverCount))
                    .font(.caption).foregroundStyle(HelmText.quiet)
                    .lineLimit(1).fixedSize()
                Menu {
                    ForEach(StaleKind.allCases, id: \.self) { kind in
                        Toggle(LfStr.kindName(kind), isOn: Binding(
                            get: { !lvm.hiddenKinds.contains(kind) },
                            set: { on in
                                if on { lvm.hiddenKinds.remove(kind) } else { lvm.hiddenKinds.insert(kind) }
                                lvm.dropHiddenSelections()
                            }))
                    }
                } label: {
                    Label(LfStr.filter, systemImage: "line.3.horizontal.decrease")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Picker(HelmA11y.whatToShow, selection: $lvm.showAll) {
                    Text(LfStr.filterLeftovers).tag(false)
                    Text(LfStr.filterAll).tag(true)
                }
                .pickerStyle(.segmented).labelsHidden()
                // Narrowing the list drops the ticks it hides, the way the kind
                // filter and a fresh scan already do. Without this the segmented
                // control was the one way a selection could outlive its row.
                .onChange(of: lvm.showAll) { _, _ in lvm.dropHiddenSelections() }
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
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
    }

    @ViewBuilder private var content: some View {
        if lvm.items.isEmpty {
            // Before the first scan the page has nothing to show and room to
            // explain itself, so the sentence that was in the toolbar is here,
            // under the call to action it belongs to.
            HelmEmptyState(symbol: lvm.scanned ? "checkmark.circle" : "wand.and.rays",
                           tint: ModuleCategory.utilities.tint,
                           message: lvm.scanned ? LfStr.nothingFound : LfStr.notScannedYet,
                           note: lvm.scanned ? nil : LfStr.intro)
            // A bounded minimum: enough to centre the message, without the
            // unbounded height that made the window grow to fill the screen.
            .frame(maxWidth: .infinity, minHeight: 260)
        } else {
            List {
                ForEach(grouped, id: \.kind) { group in
                    Section(LfStr.kindName(group.kind)) {
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
                Toggle(item.identifier, isOn: Binding(
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
                        // Not SwiftUI's `.secondary`: it measures 3.95:1 here,
                        // under the 4.5:1 body floor `HelmText.quiet` (4.62:1)
                        // exists to hold. A row nobody may delete is still a row
                        // somebody has to read.
                        .foregroundStyle(item.removable ? Color.primary : HelmText.quiet)
                    if item.disabled {
                        HelmBadge(LfStr.statusDisabled)
                    } else {
                        statusBadge(item.status)
                    }
                    if item.runAtLoad {
                        HelmBadge(LfStr.runsAtLogin, tint: .orange)
                    }
                }
                if item.kind != .systemExtension {
                    Text(item.path)
                        .font(.caption).foregroundStyle(HelmText.quiet)
                        .lineLimit(1).truncationMode(.middle)
                }
                if let target = item.missingTarget {
                    Text(LfStr.missingTarget(target))
                        .font(.caption2).foregroundStyle(HelmText.faint)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            // A name, up to two badges, a path and a note about a missing
            // target: five stops per row on a list that holds dozens, and the
            // name arrives without the badge that qualifies it. One element,
            // read in the order it is drawn — the checkbox and the buttons stay
            // their own, being things to operate rather than to read.
            .accessibilityElement(children: .combine)
            Spacer()
            if item.canToggle {
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
                    .font(.caption).foregroundStyle(HelmText.quiet).monospacedDigit()
                Menu {
                    Button(LfStr.reveal) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                    }
                    if item.actions.contains(.delete) {
                        Button(Self.deleteLabel(for: item), role: .destructive) {
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
                .accessibilityLabel("\(HelmA11y.moreActions), \(item.identifier)")
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
        return HelmBadge(text, tint: color)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button(LfStr.selectAll) {
                lvm.selected = lvm.selectablePaths
            }
            .disabled(lvm.leftoverCount == 0)
            Button(LfStr.deselectAll) { lvm.selected.removeAll() }
                .disabled(lvm.selected.isEmpty || lvm.busy)
            if !lvm.items.isEmpty {
                Text(LfStr.selectedLine(lvm.selectedCount, Bytes(lvm.selectedBytes)))
                    .font(.caption).foregroundStyle(HelmText.quiet)
            }
            Spacer()
            if let banner = lvm.banner {
                // The outcome, not a slogan: what stayed behind is named.
                HelmRemovalOutcome(
                    succeededText: banner,
                    removed: lvm.removedCount,
                    failures: lvm.failures.map {
                        HelmRemovalFailure(path: $0.path,
                                           reason: LfStr.failureReason($0.message))
                    },
                    needsFullDiskAccess: diskAccess == .denied)
                    .frame(maxWidth: 420, alignment: .leading)
            }
            Button(LfStr.removeSelected) { confirmingBatch = true }
                .buttonStyle(.borderedProminent)
                .disabled(lvm.selected.isEmpty || lvm.busy)
                .confirmationDialog(LfStr.confirmSelected(lvm.selected.count,
                                                          Bytes(lvm.selectedBytes)),
                                    isPresented: $confirmingBatch, titleVisibility: .visible) {
                    Button(LfStr.removeSelected, role: .destructive) {
                        Task { await lvm.removeSelected() }
                    }
                    Button(LfStr.cancelAction, role: .cancel) { }
                }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}
