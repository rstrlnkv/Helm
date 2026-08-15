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
                // Asked once per group, not once per row: answering it runs the
                // ladder over the group's copies, and the header, the button
                // beside it and every row want the same answer.
                let grounds = dvm.grounds(of: group)
                Section {
                    ForEach(Array(group.paths.enumerated()), id: \.element) { index, path in
                        row(in: group, path: path, stays: index == 0,
                            chosen: grounds == .byHand)
                            .tag(path)
                    }
                } header: {
                    header(group, grounds)
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
                            .font(HelmText.rowDetail)
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
        HelmReveal.inFinder(path)
    }

    private func preview(_ path: String?) {
        if previewPath != nil {
            previewPath = nil
        } else if let url = DuplicatePreview.target(selection: path, in: dvm.groups) {
            previewPath = url.path
        }
    }

    /// The group's own line: what it is, why this copy stays, and the two things
    /// that can be done to the whole group.
    private func header(_ group: DuplicateGroup, _ grounds: KeepGrounds?) -> some View {
        HStack {
            Text("\(Bytes(group.bytes)) × \(group.paths.count)")
                .font(HelmText.groupLabel)
            // What the group is worth, not only what it is: «21 MB × 2» invites
            // multiplying, and for a clone pair the product is space the disk
            // will not give back. `wasted` is the clone-aware fold every other
            // figure on the page already uses, and the tail is the total line's
            // own sentence, so the two cannot drift apart. It yields with the
            // reason — the buttons stay pinned.
            Text(DupStr.onceEmptied(Bytes(group.wasted)))
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.faint)
                .lineLimit(1)
            // Why, in the header rather than in a tooltip on the badge: a
            // tooltip needs a pointer to rest on a pill, and the one that was
            // there said «the copy that was there first» about every group in
            // every language, which the policy made plainly untrue.
            if let grounds {
                Text(DupStr.keptBecause(grounds))
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.faint)
                    .lineLimit(1)
            }
            Spacer()
            // Only where there is something to put back. A control that undoes
            // a choice nobody made is a control that has to explain itself.
            //
            // Both buttons pinned: unpinned, the first thing a narrow pane
            // compressed was «Restore the recommendation»'s own words, while
            // the reason above sat whole — the reason is the part with
            // `lineLimit(1)`, so the reason is the part that yields.
            // `TheGroupHeaderKeepsItsButtonsTests` holds the arithmetic.
            if grounds == .byHand {
                Button(DupStr.restoreRecommendation) { dvm.restoreRecommendation(for: group) }
                    .controlSize(.small)
                    .fixedSize()
            }
            Button(DupStr.markGroupExtras) { dvm.basketExtras(of: group) }
                .controlSize(.small)
                .fixedSize()
        }
    }

    private func row(in group: DuplicateGroup, path: String, stays: Bool,
                     chosen: Bool) -> some View {
        let keep = { dvm.keep(path, in: group) }
        return HStack(spacing: 8) {
            // The way into choosing this copy, and on the row it is about. The
            // checkmark is not a control: that copy already stays, and a button
            // that does nothing when pressed is a control that lies. On the
            // extras it is the same act the context menu and the accessibility
            // action below carry, which is why all three read one string.
            if stays {
                Image(systemName: "checkmark.circle")
                    // The token, not SwiftUI's green: that one measures 2.22:1
                    // in light mode against `HelmSignal.success`'s 4.58:1.
                    .foregroundStyle(HelmSignal.success)
                    .accessibilityHidden(true)
            } else {
                KeepThisCopyButton(keep: keep)
            }
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                Text((path as NSString).lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                Text(Redact.path((path as NSString).deletingLastPathComponent))
                    .font(.caption2).foregroundStyle(HelmText.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if stays {
                // Two pills and not one word swapped: «stays» is what the row
                // means and «your choice» is who decided it, and a badge that
                // said only the second would leave the survivor of a chosen
                // group as the one row on the page that never says it stays.
                if chosen {
                    HelmBadge(DupStr.yourChoice)
                }
                HelmBadge(DupStr.keep, tint: HelmSignal.success)
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
            if !stays {
                Button(DupStr.keepThisCopy) { keep() }
            }
            Button(DupStr.quickLook) { preview(path) }
            Button(DupStr.reveal) { reveal(path) }
        }
        // The same actions where VoiceOver can reach them, since the menu
        // above needs a right-click.
        .accessibilityActions {
            if !stays {
                Button(DupStr.keepThisCopy) { keep() }
            }
            Button(DupStr.quickLook) { preview(path) }
            Button(DupStr.reveal) { reveal(path) }
        }
    }

    private func basketBinding(_ path: String) -> Binding<Bool> {
        Binding(get: { dvm.isBasketed(path) }, set: { _ in dvm.toggleBasket(path) })
    }
}

/// The circle that chooses this copy as the one to keep.
///
/// **A pixel from the status glyph beside it.** The copy that already stays wears
/// a green `checkmark.circle`; an empty grey `circle` is what marks the ones that
/// do not — and at rest the second reads as a second status icon rather than a
/// button. On hover it fills with the same green the outcome wears, so the
/// pointer previews «press and this becomes the kept one» and the control reads
/// as pressable. Its own view for the `@State` a hover needs, which a row-drawing
/// method cannot hold.
private struct KeepThisCopyButton: View {
    let keep: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: keep) {
            Image(systemName: hovering ? "circle.fill" : "circle")
                .foregroundStyle(hovering ? HelmSignal.success : HelmText.quiet)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(DupStr.keepThisCopy)
        .accessibilityLabel(DupStr.keepThisCopy)
    }
}
