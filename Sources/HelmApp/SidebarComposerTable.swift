import AppKit
import SwiftUI
import HelmUI

/// The sidebar's arrangement as an `NSTableView`, so the drag is the system's
/// own: a lift, an insertion indicator between any two rows, and a drop that
/// animates — across section boundaries, which SwiftUI's `.onMove` cannot do
/// because it is scoped to one `ForEach`.
///
/// The rows are SwiftUI inside `NSHostingView`, so the plate, the switch and
/// the type are the same ones every other Helm row uses rather than a second
/// set built in AppKit that would drift from them.
///
/// **What this view does not decide.** Where a drop lands is
/// `SidebarLayout.applyingDrag(of:toFlatIndex:)`, which is a value with tests.
/// Everything here is which row was picked up and which index the indicator
/// sat at.
@MainActor
struct SidebarComposerTable: NSViewRepresentable {
    let layout: SidebarLayout
    let host: ModuleHost
    /// At rest this is a list of what is in the sidebar; in edit it is the
    /// thing you rearrange. The difference is not decoration — **the drag is
    /// off at rest.** A row that lifts under the pointer when nothing said it
    /// could is how an arrangement gets changed by somebody who meant to
    /// scroll, and there is no undo here.
    let editing: Bool
    /// Reported outward because a table inside a `Form` must not scroll: the
    /// page already scrolls, and a second scroll view inside it is a trap for
    /// the pointer. The height is measured after each reload rather than
    /// guessed from a row count — the old order list guessed, and at larger
    /// system text it clipped its last rows.
    @Binding var height: CGFloat
    let apply: (SidebarLayout) -> Void
    /// Renaming asks the block above to present the dialog. A sheet raised from
    /// inside an `NSHostingView` in a table row has no reliable presenter — the
    /// row is torn down and rebuilt by the table whenever it reloads.
    let rename: (SidebarLayout.Section) -> Void

    /// Rows carry this rather than a plain string, so a drag from some other
    /// table cannot be read as one of ours.
    static let rowType = NSPasteboard.PasteboardType("com.helm.sidebar-row")

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        // `.plain`, not `.inset`: the card this sits in already supplies the
        // inset, and `.inset` would add a second one that no other row in the
        // form has.
        table.style = .plain
        table.backgroundColor = .clear
        table.usesAutomaticRowHeights = true
        table.selectionHighlightStyle = .none
        // No gap between rows. A settings list separates rows with a hairline,
        // not with air, and the hairline is drawn by the row so it can start
        // past the plate the way every other Helm list does.
        table.intercellSpacing = NSSize(width: 0, height: 0)
        // A heading that sticks to the top while its modules scroll under it is
        // for a list long enough to scroll. This one is sized to fit.
        table.floatsGroupRows = false
        table.addTableColumn(NSTableColumn(identifier: .init("row")))
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.registerForDraggedTypes([Self.rowType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        // The page scrolls; this must not. Anything taller than the reported
        // height would be clipped rather than scrolled, which is why the height
        // is measured and reported instead.
        scroll.verticalScrollElasticity = .none
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(layout: layout, host: host, editing: editing,
                                   apply: apply, rename: rename)
        context.coordinator.table?.reloadData()
        context.coordinator.reportHeight { height = $0 }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: NSTableView?
        private var layout = SidebarLayout(sections: [])
        private var host: ModuleHost?
        private var apply: ((SidebarLayout) -> Void)?
        private var rename: ((SidebarLayout.Section) -> Void)?
        private var rows: [SidebarLayout.Row] = []
        private var editing = false

        func update(layout: SidebarLayout, host: ModuleHost, editing: Bool,
                    apply: @escaping (SidebarLayout) -> Void,
                    rename: @escaping (SidebarLayout.Section) -> Void) {
            self.layout = layout
            self.host = host
            self.editing = editing
            self.apply = apply
            self.rename = rename
            // An empty section is a heading with a place to drop something
            // under it, which is a thing only edit mode has. At rest it would
            // be a heading naming nothing — so it is not drawn at all, the way
            // the sidebar itself does not draw it.
            self.rows = editing ? layout.flattened : layout.flattened.filter { row in
                guard case .section(let id) = row else { return true }
                return !(layout.sections.first { $0.id == id }?.modules.isEmpty ?? true)
            }
        }

        /// Measured after layout rather than computed from a row count: rows are
        /// SwiftUI and grow with the system text size.
        func reportHeight(_ report: @escaping (CGFloat) -> Void) {
            guard let table else { return }
            DispatchQueue.main.async {
                table.layoutSubtreeIfNeeded()
                let total = (0..<table.numberOfRows).reduce(CGFloat(0)) { sum, row in
                    sum + table.rect(ofRow: row).height
                }
                report(max(total, 1))
            }
        }

        // MARK: - Rows

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            guard rows.indices.contains(row) else { return false }
            if case .section = rows[row] { return true }
            return false
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                       row: Int) -> NSView? {
            guard rows.indices.contains(row), let host, let apply, let rename else { return nil }
            let content = SidebarComposerRow(row: rows[row], layout: layout,
                                             host: host, editing: editing,
                                             apply: apply, rename: rename)
            let hosting = NSHostingView(rootView: AnyView(content))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            let cell = NSView()
            cell.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: cell.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
            ])
            return cell
        }

        // MARK: - Dragging

        func tableView(_ tableView: NSTableView,
                       pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            // Refused at the source rather than at the drop: a row that lifts
            // and then refuses to land has already told the person they could
            // rearrange this, and taken it back after they tried.
            guard editing, rows.indices.contains(row) else { return nil }
            let item = NSPasteboardItem()
            item.setString(rows[row].id, forType: SidebarComposerTable.rowType)
            return item
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                       proposedRow row: Int,
                       proposedDropOperation operation: NSTableView.DropOperation)
        -> NSDragOperation {
            // Only between rows, never onto one. Dropping "on" a module has no
            // meaning here — a module does not contain anything — and a drop
            // the table accepts but cannot act on is worse than one it refuses.
            if operation == .on {
                tableView.setDropRow(row, dropOperation: .above)
            }
            return .move
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                       row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard let id = info.draggingPasteboard.string(forType: SidebarComposerTable.rowType),
                  let dragged = rows.first(where: { $0.id == id }),
                  let apply else { return false }
            apply(layout.applyingDrag(of: dragged, toFlatIndex: row))
            return true
        }
    }
}

/// One line of the composer: a section's heading with its menu, or a module
/// with its switch.
///
/// **The card belongs to the section, and the rows draw it.** The redesign puts
/// each section on its own card (`shell.html`, `.section > .card`), which reads
/// as one table of many if you let AppKit host a table per section — and then a
/// module dragged from one card to another is a drag between two table views,
/// which is a different mechanism with different failure modes. Instead there
/// is still exactly one table: the first module of a section rounds the top
/// corners, the last rounds the bottom, and the heading above them draws no
/// card at all. The drag never learns that the card exists.
@MainActor
private struct SidebarComposerRow: View {
    let row: SidebarLayout.Row
    let layout: SidebarLayout
    let host: ModuleHost
    let editing: Bool
    let apply: (SidebarLayout) -> Void
    let rename: (SidebarLayout.Section) -> Void

    /// The gap between one section's card and the next heading. It is the
    /// heading's own top padding rather than table spacing, because
    /// `intercellSpacing` would put it between *every* pair of rows.
    private let sectionGap: CGFloat = 10

    var body: some View {
        switch row {
        case .section(let id):
            if let section = layout.sections.first(where: { $0.id == id }) {
                header(section)
            }
        case .module(let id, let sectionID):
            if let descriptor = ModuleRegistry.all.first(where: { $0.idRaw == id }) {
                module(descriptor, in: sectionID)
            }
        }
    }

    // MARK: - A section's heading

    private func header(_ section: SidebarLayout.Section) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                // Uppercase at 10 pt with the redesign's own tracking. Left at
                // `HelmText.quiet` and *not* at the mockup's extra `opacity:.75`
                // — 0.64 measures 4.56:1 and 0.48 would not come near it, and
                // small uppercase type needs more contrast than body, not less.
                Text(AppStr.sectionTitle(section).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(HelmText.quiet)
                if editing, section.seed == nil {
                    HelmBadge(AppStr.yourSection)
                }
                Spacer(minLength: 6)
                if editing { menu(section) }
            }
            .padding(.horizontal, 4)

            // A section somebody just made is empty by definition, and an empty
            // section drawn as nothing is a heading followed by a heading with
            // no target between them. The card is still here; it just says so.
            if editing, section.modules.isEmpty {
                Text(AppStr.dragModuleHere)
                    .font(.system(size: 13))
                    .foregroundStyle(HelmText.faint)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(card(top: true, bottom: true))
            }
        }
        .padding(.top, sectionGap)
        .padding(.bottom, section.modules.isEmpty ? 0 : 5)
        .contentShape(Rectangle())
    }

    private func menu(_ section: SidebarLayout.Section) -> some View {
        Menu {
            Button(AppStr.renameSection) { rename(section) }
            if section.seed != nil, section.name != nil {
                Button(AppStr.useDefaultSectionName) {
                    apply(layout.renaming(section.id, to: nil))
                }
            }
            Button(AppStr.removeSection, role: .destructive) {
                apply(layout.removingSection(section.id))
            }
            // Offered and refused rather than hidden: the last section holds
            // every module, and an absent item explains nothing.
            .disabled(layout.sections.count == 1)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel(HelmA11y.moreActions)
    }

    // MARK: - A module

    private func module(_ descriptor: any ModuleDescriptor, in sectionID: String) -> some View {
        let first = isFirstInSection(sectionID)
        return HStack(spacing: 10) {
            // Nine rows that can be dragged, and until now nothing said so. The
            // grip is the redesign's answer and it is also the only one that
            // works before the pointer is already on the row — and it appears
            // exactly when the drag does, so the two never disagree.
            if editing {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HelmText.faint)
                    .accessibilityHidden(true)
            }
            HelmIconPlate(symbol: descriptor.moduleMetadata.sfSymbol,
                          tint: descriptor.moduleTint.colour, size: 22,
                          active: host.isEnabled(descriptor))
            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor.moduleMetadata.name)
                    .font(.system(size: 13))
                // The second line is what makes the list long, so it is the
                // first thing to go: at rest this is a list of what is in the
                // sidebar, and the person reading it already knows. It stays
                // as the tooltip either way.
                if editing {
                    Text(descriptor.moduleMetadata.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(HelmText.quiet)
                        .lineLimit(1)
                }
            }
            .help(descriptor.moduleMetadata.summary)
            Spacer(minLength: 8)
            Toggle(descriptor.moduleMetadata.name, isOn: Binding(
                get: { host.isEnabled(descriptor) },
                set: { host.setEnabled(descriptor, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, editing ? 6 : 4)
        .frame(minHeight: 30)
        // Dimmed in place rather than sunk: sinking costs the position the
        // person chose, and they find out only when they switch it back on.
        .opacity(host.isEnabled(descriptor) ? 1 : 0.55)
        .background(card(top: first, bottom: isLastInSection(sectionID)))
        // Full bleed and half a point, which is the redesign's rule and also
        // the one the system follows: measured across three System Settings
        // lists, a separator is inset 10/10 from the *card* and never dodges
        // the icon. Here the card's own edge supplies that inset.
        .overlay(alignment: .top) {
            if !first {
                Rectangle().fill(HelmSurface.hairline).frame(height: 0.5)
            }
        }
    }

    /// The section's card, rounded only where the section actually ends.
    private func card(top: Bool, bottom: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: top ? HelmSurface.cardRadius : 0,
            bottomLeadingRadius: bottom ? HelmSurface.cardRadius : 0,
            bottomTrailingRadius: bottom ? HelmSurface.cardRadius : 0,
            topTrailingRadius: top ? HelmSurface.cardRadius : 0,
            style: .continuous
        )
        .fill(HelmSurface.cardFill)
    }

    private func isFirstInSection(_ sectionID: String) -> Bool {
        guard case .module(let id, _) = row,
              let section = layout.sections.first(where: { $0.id == sectionID })
        else { return true }
        return section.modules.first == id
    }

    private func isLastInSection(_ sectionID: String) -> Bool {
        guard case .module(let id, _) = row,
              let section = layout.sections.first(where: { $0.id == sectionID })
        else { return true }
        return section.modules.last == id
    }
}
