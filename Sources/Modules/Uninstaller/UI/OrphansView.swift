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
            // Always present, like every other bottom bar in Helm: showing it
            // only after a scan moved the whole screen by its height and took
            // the hairline with it. The buttons are already disabled when there
            // is nothing to act on.
            Divider()
            watchRow
            Divider()
            footer
        }
    }

    /// What the last removal had to say, or nil while this page has said
    /// nothing — built where the Trash window builds its own, because the two
    /// report the same three states.
    private var removalReport: HelmRemovalOutcome? {
        .uninstaller(model.banner, removed: model.removedCount, failures: model.failures)
    }

    @ViewBuilder private var content: some View {
        if model.scanning {
            HelmBusyState(UnStr.scanningOrphans)
        } else if !model.scanned {
            // The module's own tint, not a colour chosen per state: orange and
            // green here read as a warning and a success on a screen that is
            // only waiting to be asked. A colour shared by several modules
            // would not say which page this is (`ModuleTint.swift`).
            HelmEmptyState(symbol: "clock.arrow.circlepath", tint: UninstallerDescriptor.tint.colour,
                           message: UnStr.orphansIntro) {
                Button(UnStr.scanOrphans) { Task { await model.scan() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if model.groups.isEmpty {
            HelmEmptyState(symbol: "checkmark.circle", tint: UninstallerDescriptor.tint.colour,
                           message: UnStr.noOrphans) {
                // Not prominent: looking again for something that was not there
                // is available, not recommended.
                Button(UnStr.rescan) { Task { await model.scan() } }
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
                                // A heading over this bundle's leftovers.
                                // `Section(header:)` may say so as well; the
                                // trait is a set, so saying it twice costs
                                // nothing and saying it never costs the rotor.
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
    /// It sits on this tab because this tab is already the answer to "what did an
    /// app I removed leave behind" — the window asks the same question at the
    /// moment of removal, when the bundle is still there to be identified. On the
    /// Apps tab it would hang over a list it has nothing to do with.
    ///
    /// Off by default: a window that appears unasked is not something to hand
    /// somebody without their say-so.
    private var watchRow: some View {
        HStack(alignment: .center, spacing: HelmSpace.s6) {
            // Label above its own explanation, switch hard right — the macOS
            // order, and the one every other settings row in Helm keeps. Written
            // as one HStack rather than a Toggle with a label because a label
            // that wraps to two lines pushed the switch into the middle of the
            // row, between the sentence and its own footnote.
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                Text(UnStr.watchTrash).font(HelmText.rowTitle)
                Text(UnStr.watchTrashNote)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            // The switch's position comes from the engine, which is also the only
            // thing that knows whether it is doing anything — this view kept a
            // `@State` of its own, and the page kept a second one for its
            // permission note.
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
            Button(UnStr.rescan) { Task { await model.scan() } }.disabled(model.busy)
            Button(model.allSelected ? UnStr.selectNone : UnStr.selectAll) { model.toggleAll() }
            .disabled(model.busy)
            Spacer()
            Text(UnStr.selectedSummary(model.selected.count, Bytes(model.selectedBytes)))
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            Button(UnStr.moveToTrash) { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.selected.isEmpty || model.busy)
        }
        .helmPageStrip()
        .confirmationDialog(UnStr.confirmTrash(model.selected.count, Bytes(model.selectedBytes)),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(UnStr.moveToTrash, role: .destructive) { Task { await model.trashSelected() } }
            Button(UnStr.cancel, role: .cancel) {}
        }
    }
}
