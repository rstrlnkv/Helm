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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(DkStr.duplicatesTitle).font(.title3.weight(.semibold))
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
            Image(systemName: stays ? "checkmark.circle" : "doc.on.doc")
                .foregroundStyle(stays ? Color.green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text((path as NSString).lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                Text((path as NSString).deletingLastPathComponent)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if stays {
                HelmBadge(DkStr.duplicatesKeep, tint: .green)
            } else {
                Toggle("", isOn: basketBinding(path: path, bytes: bytes))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help(DkStr.duplicatesBasketRest)
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
                Text(DkStr.duplicatesFound(groups.count,
                                           Bytes(groups.reduce(0) { $0 + $1.wasted })))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(DkStr.duplicatesFloorNote)
                    .font(.caption).foregroundStyle(.tertiary)
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
