import SwiftUI
import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

extension OrphanGroup: Identifiable { public var id: String { bundleID } }

/// Leftovers whose owning app is no longer installed: scan, review, trash.
struct OrphansView: View {
    let uvm: UninstallerViewModel

    /// The view model's, not the page's: a sidebar click unmounts this view, and
    /// the scan stays with the module.
    @ObservedObject var model: OrphansModel
    @State private var confirming = false

    init(uvm: UninstallerViewModel) {
        self.uvm = uvm
        model = uvm.orphans
    }

    var body: some View {
        VStack(spacing: 0) {
            if let report = removalReport {
                report
                    .helmPageStrip()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            content
            // Always present, like every bottom bar in Helm, so a scan does not
            // move the screen. The buttons are disabled when there is nothing to act on.
            Divider()
            watchRow
            Divider()
            footer
        }
    }

    /// What the last removal had to say, or nil while this page has said nothing;
    /// built where the Trash window builds its own (`UninstallerRemovalReport`).
    private var removalReport: HelmRemovalOutcome? {
        .uninstaller(model.banner, removed: model.removedCount, failures: model.failures)
    }

    @ViewBuilder private var content: some View {
        if model.scanning {
            HelmBusyState(HelmWord.searching)
        } else if !model.scanned {
            // The module's own tint, not a colour per state: orange or green would
            // read as a warning or a success on a screen that is only waiting
            // (`ModuleTint.swift`).
            HelmEmptyState(symbol: "clock.arrow.circlepath", tint: UninstallerDescriptor.tint.colour,
                           message: UnStr.orphansIntro) {
                Button(UnStr.scanOrphans) { Task { await model.scan() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if model.groups.isEmpty {
            HelmEmptyState(symbol: "checkmark.circle", tint: UninstallerDescriptor.tint.colour,
                           message: HelmWord.noLeftoversFound) {
                // Not prominent: looking again for something that was not there
                // is available, not recommended.
                Button(HelmWord.scanAgain) { Task { await model.scan() } }
            }
        } else {
            List {
                ForEach(model.groups) { group in
                    Section {
                        ForEach(group.leftovers, id: \.path) { item in
                            Toggle(isOn: model.binding(for: item.path)) {
                                VStack(alignment: .leading, spacing: HelmSpace.s1) {
                                    Text(item.path).font(HelmText.rowDetail).lineLimit(1).truncationMode(.middle)
                                    Text(UnStr.kindAndSize(item.kind, Bytes(item.sizeBytes)))
                                        .font(HelmText.smallPrint).foregroundStyle(HelmText.quiet)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, HelmSpace.s1)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        HStack {
                            Text(group.bundleID).font(HelmText.sectionHeading)
                                // A heading over this bundle's leftovers. The
                                // trait is a set, so repeating `Section`'s costs nothing.
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Text(Bytes(group.totalBytes)).helmFigure().foregroundStyle(HelmText.quiet)
                        }
                    }
                }
            }
            .helmStripedList(rowPitch: HelmSpace.s8)
        }
    }

    /// The switch that decides whether Helm speaks up on its own.
    ///
    /// On this tab because the tab answers "what did a removed app leave behind",
    /// the question the window asks at the moment of removal.
    ///
    /// Off by default: a window that appears unasked needs the person's say-so.
    private var watchRow: some View {
        HStack(alignment: .center, spacing: HelmSpace.s6) {
            // Label above its explanation, switch hard right, the macOS order.
            // One HStack, not a labelled Toggle: a wrapped label would push the
            // switch into the middle of the row.
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                Text(UnStr.watchTrash).font(HelmText.rowTitle)
                HelmSettingsNote(UnStr.watchTrashNote)
            }
            Spacer(minLength: 0)
            // The switch's position comes from the engine, the only thing that
            // knows whether it is doing anything.
            Toggle("", isOn: Binding(get: { uvm.trashWatch.isOn },
                                     set: { on in Task { await uvm.setWatchingTrash(on) } }))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(UnStr.watchTrash)
        }
        .helmPageStrip()
        .task { await uvm.refreshTrashWatch() }
    }

    private var footer: some View {
        HStack {
            Button(HelmWord.scanAgain) { Task { await model.scan() } }.disabled(model.busy)
            Button(model.allSelected ? HelmWord.clearSelection : HelmWord.selectAll) { model.toggleAll() }
            .disabled(model.busy)
            Spacer()
            Text(UnStr.selectedSummary(model.selected.count, Bytes(model.selectedBytes)))
                .helmQuietDetail()
            Button(HelmWord.moveToTrash) { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.selected.isEmpty || model.busy)
        }
        .helmPageStrip()
        .confirmationDialog(UnStr.confirmTrash(model.selected.count, Bytes(model.selectedBytes)),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(HelmWord.moveToTrash, role: .destructive) { Task { await model.trashSelected() } }
            Button(HelmWord.cancel, role: .cancel) {}
        }
    }
}
