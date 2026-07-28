import SwiftUI
import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

extension OrphanGroup: Identifiable { public var id: String { bundleID } }

/// Leftovers whose owning app is no longer installed: scan, review, trash.
struct OrphansView: View {
    let uvm: UninstallerViewModel

    @State private var groups: [OrphanGroup] = []
    @State private var scanned = false
    @State private var scanning = false
    @State private var selected: Set<String> = []
    @State private var failures: [TrashFailureInfo] = []
    @State private var removedCount = 0
    @State private var busy = false
    @State private var confirming = false
    @State private var banner: String?

    private var selectedBytes: Int {
        groups.flatMap(\.leftovers).filter { selected.contains($0.path) }.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let banner {
                // A green bar over a refusal is the app congratulating itself
                // for work macOS did not let it do.
                HelmRemovalOutcome(succeededText: banner,
                                   removed: removedCount,
                                   failures: failures.map {
                                       HelmRemovalFailure(path: $0.path,
                                                          reason: UnStr.failureReason($0.reason))
                                   },
                                   needsFullDiskAccess: failures.contains {
                                       $0.reason == TrashFailure.Reason.needsFullDiskAccess.rawValue
                                   })
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            content
            // Always present, like every other bottom bar in Helm: showing it
            // only after a scan moved the whole screen by its height and took
            // the hairline with it. The buttons are already disabled when there
            // is nothing to act on.
            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if scanning {
            HelmBusyState(UnStr.scanningOrphans)
        } else if !scanned {
            HelmEmptyState(symbol: "clock.arrow.circlepath", tint: .orange,
                           message: UnStr.orphansIntro) {
                Button(UnStr.scanOrphans) { Task { await scan() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if groups.isEmpty {
            HelmEmptyState(symbol: "checkmark.circle", tint: .green, message: UnStr.noOrphans) {
                // Not prominent: looking again for something that was not there
                // is available, not recommended.
                Button(UnStr.rescan) { Task { await scan() } }
            }
        } else {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.leftovers, id: \.path) { item in
                            Toggle(isOn: binding(for: item.path)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.path).font(.caption).lineLimit(1).truncationMode(.middle)
                                    Text("\(UnStr.kind(item.kind)) · \(Bytes(item.sizeBytes))")
                                        .font(.caption2).foregroundStyle(HelmText.quiet)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, 2)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        HStack {
                            Text(group.bundleID).font(.callout.weight(.medium))
                            Spacer()
                            Text(Bytes(group.totalBytes)).font(.caption).foregroundStyle(HelmText.quiet)
                        }
                    }
                }
            }
            .listStyle(.inset)
            }
    }

    private var allPaths: [String] { groups.flatMap(\.leftovers).map(\.path) }
    private var allSelected: Bool { selected.count == allPaths.count && !allPaths.isEmpty }

    private var footer: some View {
        HStack {
            Button(UnStr.rescan) { Task { await scan() } }.disabled(busy)
            // One toggle covers both: "select all" flips to "deselect all" when
            // everything is already checked (default after a scan).
            Button(allSelected ? UnStr.selectNone : UnStr.selectAll) {
                selected = allSelected ? [] : Set(allPaths)
            }
            .disabled(busy)
            Spacer()
            Text(UnStr.selectedSummary(selected.count, Bytes(selectedBytes)))
                .font(.caption).foregroundStyle(HelmText.quiet)
            Button(UnStr.moveToTrash) { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || busy)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .confirmationDialog(UnStr.confirmTrash(selected.count, Bytes(selectedBytes)),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(UnStr.moveToTrash, role: .destructive) { Task { await trashSelected() } }
            Button(UnStr.cancel, role: .cancel) {}
        }
    }

    // MARK: - Actions

    private func scan() async {
        scanning = true; banner = nil
        groups = await uvm.scanOrphans()
        // Nothing is pre-selected. A ticked list of 251 items is a button that
        // deletes whatever the scan got wrong, and this scan was wrong: apps
        // one folder down in /Applications read as uninstalled.
        selected = []
        scanning = false; scanned = true
    }

    private func trashSelected() async {
        busy = true
        let result = await uvm.trashPaths(Array(selected))
        busy = false
        guard let result else { return }
        // The rescan first. Its own first statement is `banner = nil`, and it
        // runs synchronously up to its own await — so an outcome set before it
        // was wiped inside the same main-actor turn and SwiftUI never drew a
        // frame in between. This screen has been reporting nothing at all,
        // including refusals somebody could have acted on.
        await scan()
        failures = result.failures
        removedCount = result.trashed.count
        banner = UnStr.freed(Bytes(result.freedBytes))
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding(get: { selected.contains(path) },
                set: { on in
                    if on { selected.insert(path) } else { selected.remove(path) }
                })
    }

}
