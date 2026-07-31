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
    /// The row the keyboard is on. A List with no selection has no focusable
    /// rows at all: arrow keys did nothing, and the row that stays — an image,
    /// a name and a badge, no control anywhere — could not be reached at all.
    @State private var selection: String?
    /// The copy being previewed in the sheet, nil when it is closed.
    /// A String rather than a URL because the selection is one, and
    /// `DuplicatePreview.target` is what turns it into a file to show.
    @State private var previewPath: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(dvm.groups) { group in
                Section {
                    ForEach(Array(group.paths.enumerated()), id: \.element) { index, path in
                        row(path: path, stays: index == 0)
                            .tag(path)
                    }
                } header: {
                    HStack {
                        Text("\(Bytes(group.bytes)) × \(group.paths.count)")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button(DupStr.markGroupExtras) { dvm.basketExtras(of: group) }
                            .controlSize(.small)
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            // Zero-size and invisible: a button still owns its shortcut, and
            // the rows already carry the visible affordances in their context
            // menus. A context menu needs a right-click, which Full Keyboard
            // Access without VoiceOver cannot produce.
            ZStack {
                Button("") { reveal(selection) }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(selection == nil)
                Button("") { preview(selection) }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(selection == nil)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        // A copy that has just been trashed must not keep the keyboard pointing
        // at nothing.
        .onChange(of: dvm.groups) { _, groups in
            selection = DuplicateSelection.surviving(selection, in: groups)
            if DuplicatePreview.target(selection: previewPath, in: groups) == nil {
                previewPath = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { previewPath != nil },
            set: { if !$0 { previewPath = nil } })) {
            if let path = previewPath {
                VStack(spacing: 0) {
                    QuickLookSheet(url: URL(fileURLWithPath: path))
                        .frame(minWidth: 640, minHeight: 420)
                    Divider()
                    HStack {
                        Text((path as NSString).lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(HelmText.quiet)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(DupStr.close) { previewPath = nil }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(12)
                }
            }
        }
    }

    private func reveal(_ path: String?) {
        guard let path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func preview(_ path: String?) {
        if previewPath != nil {
            previewPath = nil
        } else if let url = DuplicatePreview.target(selection: path, in: dvm.groups) {
            previewPath = url.path
        }
    }

    private func row(path: String, stays: Bool) -> some View {
        HStack(spacing: 8) {
            // Decorative: the badge or the checkbox already says which is which.
            Image(systemName: stays ? "checkmark.circle" : "doc.on.doc")
                // The token, not SwiftUI's green: that one measures 2.22:1 in
                // light mode against `HelmSignal.success`'s 4.58:1.
                .foregroundStyle(stays ? HelmSignal.success : HelmText.quiet)
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
                HelmBadge(DupStr.keep, tint: HelmSignal.success)
                    .help(DupStr.keepWhy)
            } else {
                // The title names the file, so a dozen checkboxes are a dozen
                // different controls to VoiceOver; labelsHidden keeps it out of
                // the pixels. A checkbox that silently refuses to check is a
                // control that lies, so out-of-scope paths are disabled and say
                // why instead.
                Toggle("\(DupStr.markRow): \((path as NSString).lastPathComponent)",
                       isOn: basketBinding(path))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(!UserFileScope.isRemovable(path))
                    .help(UserFileScope.isRemovable(path) ? DupStr.markRow
                                                           : DupStr.systemItem)
            }
        }
        .contextMenu {
            Button(DupStr.quickLook) { preview(path) }
            Button(DupStr.reveal) { reveal(path) }
        }
        // The same actions where VoiceOver can reach them, since the menu
        // above needs a right-click.
        .accessibilityActions {
            Button(DupStr.quickLook) { preview(path) }
            Button(DupStr.reveal) { reveal(path) }
        }
    }

    private func basketBinding(_ path: String) -> Binding<Bool> {
        Binding(get: { dvm.isBasketed(path) }, set: { _ in dvm.toggleBasket(path) })
    }
}
