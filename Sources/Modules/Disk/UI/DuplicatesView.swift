import HelmUI
import Module_Disk_Engine
import SwiftUI

/// The second look inside the disk: the sheet that shows identical files.
///
/// One group is one piece of content. The first path in a group is the copy
/// that stays — every action here talks about the extras, so there is no way
/// to ask Helm to basket all of something. Deletion itself still goes through
/// the basket and the engine's removal scope, like everything else in Disk.
struct DuplicatesView: View {
    @ObservedObject var dvm: DiskViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 480)
        .onAppear { if dvm.duplicates == nil, !dvm.duplicatesRunning { dvm.findDuplicates() } }
        // The Close button is one way out; ⌘W on the window is another. The
        // view model outlives both, so the answer is dropped on ANY exit —
        // stale groups shown under a different folder's title were the bug.
        .onDisappear {
            if dvm.duplicatesRunning { dvm.cancelDuplicates() }
            dvm.clearDuplicates()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Titled by the feature's one name; "a second look" is the
            // subtitle's register, not a third alias.
            Text(DkStr.duplicates).font(.title3.weight(.semibold))
            Text(DkStr.duplicatesSubtitle(dvm.focus.map(dvm.displayName(for:)) ?? ""))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    @ViewBuilder private var content: some View {
        if dvm.duplicatesRunning {
            VStack(spacing: 10) {
                ProgressView()
                if let progress = dvm.duplicateProgress, progress.candidates > 0 {
                    Text(DkStr.duplicatesProgress(progress.hashed, progress.candidates))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(DkStr.duplicatesSearching)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let groups = dvm.duplicates, !groups.isEmpty {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(Array(group.paths.enumerated()), id: \.element) { index, path in
                            row(path: path, bytes: group.bytes, stays: index == 0)
                        }
                    } header: {
                        HStack {
                            Text("\(Bytes(group.bytes)) × \(group.paths.count)")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button(DkStr.duplicatesBasketRest) { dvm.basketAllButFirst(of: group) }
                                .controlSize(.small)
                        }
                    }
                }
            }
            .listStyle(.inset)
        } else {
            // Asked and clean. A cancelled search never reaches here — it
            // closes the sheet instead of claiming an answer.
            Text(DkStr.duplicatesNone)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(path: String, bytes: Int, stays: Bool) -> some View {
        HStack(spacing: 8) {
            // Decorative: the badge or the checkbox already says which is which.
            Image(systemName: stays ? "checkmark.circle" : "doc.on.doc")
                .foregroundStyle(stays ? Color.green : .secondary)
                .accessibilityHidden(true)
            // One stop for VoiceOver, not two fragments.
            VStack(alignment: .leading, spacing: 1) {
                Text((path as NSString).lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                Text((path as NSString).deletingLastPathComponent)
                    .font(.caption2).foregroundStyle(HelmText.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if stays {
                HelmBadge(DkStr.duplicatesKeep, tint: .green)
                    .help(DkStr.duplicatesKeepWhy)
            } else {
                // The title names the file so twelve checkboxes in a sheet are
                // twelve different controls to VoiceOver; labelsHidden keeps
                // the name out of the pixels and in the accessibility tree.
                // A checkbox that silently refuses to check is a control that
                // lies: out-of-scope paths are disabled and say why instead.
                Toggle("\(DkStr.duplicatesBasketRest): \((path as NSString).lastPathComponent)",
                       isOn: basketBinding(path: path, bytes: bytes))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!DiskSafety.isRemovable(path))
                    .help(DiskSafety.isRemovable(path)
                          ? DkStr.duplicatesBasketRest : DkStr.systemItem)
            }
        }
        .contextMenu {
            Button(HelmA11y.showInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    private func basketBinding(path: String, bytes: Int) -> Binding<Bool> {
        Binding(
            get: { dvm.basket.contains { $0.path == path } },
            set: { _ in
                dvm.toggleBasket(DiskEntry(name: (path as NSString).lastPathComponent,
                                           path: path, bytes: bytes, isDirectory: false,
                                           noAccess: false, children: []))
            })
    }

    private var footer: some View {
        HStack {
            if let groups = dvm.duplicates, !groups.isEmpty {
                // The basket bar lives behind this sheet; without a running
                // count the user ticks boxes on faith and finds out later.
                let picked = dvm.basket.filter { entry in
                    groups.contains { $0.paths.contains(entry.path) }
                }
                Text(DkStr.duplicatesFound(groups.count,
                                           Bytes(groups.reduce(0) { $0 + $1.wasted }))
                     + (picked.isEmpty ? "" :
                        "  ·  " + DkStr.duplicatesPicked(picked.count,
                                                         Bytes(picked.reduce(0) { $0 + $1.bytes }))))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(DkStr.duplicatesFloorNote)
                    .font(.caption).foregroundStyle(HelmText.faint)
            }
            Spacer()
            Button(DkStr.duplicatesClose) {
                if dvm.duplicatesRunning { dvm.cancelDuplicates() }
                dvm.clearDuplicates()
                onClose()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}
