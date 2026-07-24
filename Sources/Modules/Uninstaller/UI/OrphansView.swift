import SwiftUI
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
    @State private var busy = false
    @State private var confirming = false
    @State private var banner: String?

    private var selectedBytes: Int {
        groups.flatMap(\.leftovers).filter { selected.contains($0.path) }.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let banner {
                Text(banner).font(.callout).padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.15))
            }
            content
            if !groups.isEmpty { footer }
        }
    }

    @ViewBuilder private var content: some View {
        if scanning {
            HelmCenteredContent { ProgressView(); Text(UnStr.scanningOrphans).font(.caption).foregroundStyle(.secondary) }
        } else if !scanned {
            HelmCenteredContent {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 34)).foregroundStyle(.secondary)
                Text(UnStr.orphansIntro).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .frame(maxWidth: 380)
                Button(UnStr.scanOrphans) { Task { await scan() } }.buttonStyle(.borderedProminent)
            }
        } else if groups.isEmpty {
            HelmCenteredContent {
                Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(.green)
                Text(UnStr.noOrphans).foregroundStyle(.secondary)
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
                                    Text("\(UnStr.kind(item.kind)) · \(ByteFormat.string(item.sizeBytes))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    } header: {
                        HStack {
                            Text(group.bundleID).font(.callout.weight(.medium))
                            Spacer()
                            Text(ByteFormat.string(group.totalBytes)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(UnStr.rescan) { Task { await scan() } }.disabled(busy)
            Spacer()
            Text(UnStr.selectedSummary(selected.count, ByteFormat.string(selectedBytes)))
                .font(.caption).foregroundStyle(.secondary)
            Button(UnStr.moveToTrash) { confirming = true }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || busy)
        }
        .padding(10)
        .confirmationDialog(UnStr.confirmTrash(selected.count, ByteFormat.string(selectedBytes)),
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(UnStr.moveToTrash, role: .destructive) { Task { await trashSelected() } }
            Button(UnStr.cancel, role: .cancel) {}
        }
    }

    // MARK: - Actions

    private func scan() async {
        scanning = true; banner = nil
        groups = await uvm.scanOrphans()
        // Everything found is pre-selected; the user unchecks what to keep.
        selected = Set(groups.flatMap(\.leftovers).map(\.path))
        scanning = false; scanned = true
    }

    private func trashSelected() async {
        busy = true
        let result = await uvm.trashPaths(Array(selected))
        busy = false
        if let result {
            banner = UnStr.freed(ByteFormat.string(result.freedBytes))
            await scan()
        }
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding(get: { selected.contains(path) },
                set: { on in
                    if on { selected.insert(path) } else { selected.remove(path) }
                })
    }

}
