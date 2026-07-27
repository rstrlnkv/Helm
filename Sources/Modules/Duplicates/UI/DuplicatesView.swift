import AppKit
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import SwiftUI

/// The result list: one section per piece of content.
///
/// The first path in a group is the copy that stays, and every action here
/// talks about the extras — there is deliberately no way to ask Helm to bin
/// all of something. Deletion goes through the basket and the engine's removal
/// scope, which has the last word.
struct DuplicatesView: View {
    @ObservedObject var dvm: DuplicatesViewModel

    var body: some View {
        List {
            ForEach(dvm.groups) { group in
                Section {
                    ForEach(Array(group.paths.enumerated()), id: \.element) { index, path in
                        row(path: path, bytes: group.bytes, stays: index == 0)
                    }
                } header: {
                    HStack {
                        Text("\(Bytes(group.bytes)) × \(group.paths.count)")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button(DupStr.basketExtras) { dvm.basketExtras(of: group) }
                            .controlSize(.small)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func row(path: String, bytes: Int, stays: Bool) -> some View {
        HStack(spacing: 8) {
            // Decorative: the badge or the checkbox already says which is which.
            Image(systemName: stays ? "checkmark.circle" : "doc.on.doc")
                .foregroundStyle(stays ? Color.green : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text((path as NSString).lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                Text(Redact.path((path as NSString).deletingLastPathComponent))
                    .font(.caption2).foregroundStyle(HelmText.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if stays {
                HelmBadge(DupStr.keep, tint: .green)
                    .help(DupStr.keepWhy)
            } else {
                // The title names the file, so a dozen checkboxes are a dozen
                // different controls to VoiceOver; labelsHidden keeps it out of
                // the pixels. A checkbox that silently refuses to check is a
                // control that lies, so out-of-scope paths are disabled and say
                // why instead.
                Toggle("\(DupStr.basketExtras): \((path as NSString).lastPathComponent)",
                       isOn: basketBinding(path))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!UserFileScope.isRemovable(path))
                    .help(UserFileScope.isRemovable(path) ? DupStr.basketExtras
                                                           : DupStr.systemItem)
            }
        }
        .contextMenu {
            Button(DupStr.reveal) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    private func basketBinding(_ path: String) -> Binding<Bool> {
        Binding(get: { dvm.isBasketed(path) }, set: { _ in dvm.toggleBasket(path) })
    }
}
