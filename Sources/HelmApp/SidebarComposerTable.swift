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
        context.coordinator.update(layout: layout, host: host, apply: apply, rename: rename)
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

        func update(layout: SidebarLayout, host: ModuleHost,
                    apply: @escaping (SidebarLayout) -> Void,
                    rename: @escaping (SidebarLayout.Section) -> Void) {
            self.layout = layout
            self.host = host
            self.apply = apply
            self.rename = rename
            self.rows = layout.flattened
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
                                             host: host, apply: apply, rename: rename)
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
            guard rows.indices.contains(row) else { return nil }
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
@MainActor
private struct SidebarComposerRow: View {
    let row: SidebarLayout.Row
    let layout: SidebarLayout
    let host: ModuleHost
    let apply: (SidebarLayout) -> Void
    let rename: (SidebarLayout.Section) -> Void
    @State private var hovering = false

    var body: some View {
        switch row {
        case .section(let id):
            if let section = layout.sections.first(where: { $0.id == id }) {
                header(section)
            }
        case .module(let id, _):
            if let descriptor = ModuleRegistry.all.first(where: { $0.idRaw == id }) {
                module(descriptor)
            }
        }
    }

    private func header(_ section: SidebarLayout.Section) -> some View {
        HStack(spacing: 6) {
            Text(AppStr.sectionTitle(section))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HelmText.quiet)
            Spacer()
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
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(HelmA11y.moreActions)
            // On hover, as a source list shows its accessories. Three dots
            // parked at the edge of every heading is a row of controls where
            // the eye is looking for a list of names.
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func module(_ descriptor: any ModuleDescriptor) -> some View {
        HStack(spacing: 10) {
            HelmIconPlate(symbol: descriptor.moduleMetadata.sfSymbol,
                          tint: descriptor.moduleTint.colour, size: 20,
                          active: host.isEnabled(descriptor))
            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor.moduleMetadata.name)
                Text(descriptor.moduleMetadata.summary)
                    .font(.caption).foregroundStyle(HelmText.quiet).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Toggle(descriptor.moduleMetadata.name, isOn: Binding(
                get: { host.isEnabled(descriptor) },
                set: { host.setEnabled(descriptor, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Dimmed in place rather than sunk: sinking costs the position the
        // person chose, and they find out only when they switch it back on.
        .opacity(host.isEnabled(descriptor) ? 1 : 0.55)
        // The hairline starts past the plate, as it does in every other list in
        // the app — a rule running under the icon cuts the row in two.
        .overlay(alignment: .bottom) {
            if !isLastInSection {
                Rectangle().fill(HelmSurface.hairline)
                    .frame(height: 1)
                    .padding(.leading, 40)
            }
        }
    }

    /// The last row of a section draws no rule: the next thing down is a
    /// heading, which is its own separation.
    private var isLastInSection: Bool {
        guard case .module(let id, let sectionID) = row,
              let section = layout.sections.first(where: { $0.id == sectionID })
        else { return true }
        return section.modules.last == id
    }
}
