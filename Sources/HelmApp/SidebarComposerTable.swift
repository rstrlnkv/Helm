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
        // **Measured here, not by the table.** `usesAutomaticRowHeights` sizes a
        // row from its view and hands the answer straight to the layout, which
        // is a jump: `noteHeightOfRows` inside an `NSAnimationContext` has
        // nothing to interpolate because the row is already the new height by
        // the time the animation group opens. A height this side of the
        // delegate is a number AppKit animates like any other.
        table.usesAutomaticRowHeights = false
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
        context.coordinator.redraw()
        context.coordinator.reportHeight { height = $0 }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// What every row reads, as one object they all observe.
    ///
    /// **A row cannot be animated from outside it, in either sense.** Handing an
    /// `NSHostingView` a new `rootView` inside `withAnimation` replaces the tree
    /// rather than changing it: measured with the duration at 4 s, the rows
    /// arrived at their new shape in a single frame while the note above them
    /// took the whole four seconds. A published property gets the new value into
    /// each row's own tree, which fixes *that* — but it does not carry an
    /// animation with it either. The `withAnimation` that flips `editing` runs
    /// on the coordinator's stack, and every row is a separate hosting view with
    /// a renderer of its own; measured by anchoring on a row's icon plate
    /// through a ten-second transition, it moved 608 px → 654 in one frame with
    /// nothing in between, and `.animation(_:value:)` did not change that.
    /// Each row animates itself, from state it owns — see
    /// `SidebarComposerRow.shown`.
    @MainActor
    final class Model: ObservableObject {
        @Published var editing: Bool
        @Published var layout: SidebarLayout
        let host: ModuleHost
        var apply: (SidebarLayout) -> Void
        var rename: (SidebarLayout.Section) -> Void

        init(editing: Bool, layout: SidebarLayout, host: ModuleHost,
             apply: @escaping (SidebarLayout) -> Void,
             rename: @escaping (SidebarLayout.Section) -> Void) {
            self.editing = editing
            self.layout = layout
            self.host = host
            self.apply = apply
            self.rename = rename
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: NSTableView?
        /// Made on the first update, because it needs the host, and kept for
        /// the life of the table: the rows observe it, and a new one would be
        /// a new tree to animate from nothing.
        private var model: Model?
        private var layout: SidebarLayout { model?.layout ?? SidebarLayout(sections: []) }
        private var rows: [SidebarLayout.Row] = []
        private var editing = false
        /// What the table is showing, and what the last update asked of it.
        ///
        /// **The comparison has to be a value, because `updateNSView` is not a
        /// signal.** SwiftUI runs it for every change in the block around the
        /// table — and the block changes when the table reports its own height,
        /// so one click on Edit arrives as three or four updates. Judging each
        /// one on its own reloaded the table 31 ms into the transition.
        private var state = SidebarComposerState.none
        private var pending = SidebarComposerRedraw.nothing
        /// One measurement per (what the row says, which mode, how wide).
        private var heights: [String: CGFloat] = [:]
        private var measuredWidth: CGFloat = 0
        /// The last height handed to the block, so an update that changes
        /// nothing about it does not schedule a write to its state.
        private var reportedHeight: CGFloat = 0

        func update(layout: SidebarLayout, host: ModuleHost, editing: Bool,
                    apply: @escaping (SidebarLayout) -> Void,
                    rename: @escaping (SidebarLayout.Section) -> Void) {
            let model = self.model ?? Model(editing: editing, layout: layout, host: host,
                                            apply: apply, rename: rename)
            self.model = model
            model.apply = apply
            model.rename = rename
            model.layout = layout
            self.editing = editing
            // An empty section is a heading with a place to drop something
            // under it, which is a thing only edit mode has. At rest it would
            // be a heading naming nothing — so it is not drawn at all, the way
            // the sidebar itself does not draw it.
            self.rows = editing ? layout.flattened : layout.flattened.filter { row in
                guard case .section(let id) = row else { return true }
                return !(layout.sections.first { $0.id == id }?.modules.isEmpty ?? true)
            }
            let next = snapshot()
            pending = .between(state, next)
            state = next
        }

        /// Everything the rows draw, as one comparable value: which rows there
        /// are, which mode they are in, and what each one says.
        private func snapshot() -> SidebarComposerState {
            SidebarComposerState(rowIDs: rows.map(\.id), editing: editing,
                                 content: rows.map(describe))
        }

        private func describe(_ row: SidebarLayout.Row) -> String {
            switch row {
            case .section(let id):
                guard let section = layout.sections.first(where: { $0.id == id }) else { return id }
                return "s:\(AppStr.sectionTitle(section)):\(section.seed ?? ""):\(section.modules.count)"
            case .module(let id, let sectionID):
                let section = layout.sections.first { $0.id == sectionID }
                let enabled = ModuleRegistry.all.first { $0.idRaw == id }
                    .map { model?.host.isEnabled($0) ?? false } ?? false
                return "m:\(id):\(enabled):\(section?.modules.first == id):\(section?.modules.last == id)"
            }
        }

        /// Shows the new state, doing as little as it takes.
        ///
        /// **The two halves of a row's height move on one clock.** What a row
        /// *contains* is SwiftUI's — the grip, the summary and the row's own
        /// minimum height animate because `editing` is published and the rows
        /// observe it. How tall the *cell* is is AppKit's, and it animates
        /// because the height comes from the delegate rather than from
        /// `usesAutomaticRowHeights`. Both are told the same duration and the
        /// same shape of curve; `.smooth` is a spring with the bounce set to
        /// zero, which is ease-in-ease-out with a name.
        ///
        /// The two are also written so that a disagreement between them is
        /// invisible rather than ugly: nothing in a row sets a height of its
        /// own, so the content is laid out into whatever the cell currently is
        /// and a cell a pixel ahead of its contents crops nothing anyone reads.
        func redraw() {
            guard let table, let model else { return }
            switch pending {
            case .nothing:
                return
            case .refresh:
                // The rows are watching the model, so a rename or a switch has
                // already redrawn itself — but a longer name is a taller row,
                // and the table only asks again when it is told to.
                table.noteHeightOfRows(withIndexesChanged: IndexSet(0..<table.numberOfRows))
            case .reload:
                model.editing = editing
                table.reloadData()
            case .animate:
                withAnimation(HelmMotion.interface) { model.editing = editing }
                // Plainly, and not inside an `NSAnimationContext`: a row is the
                // same height in both modes, so there is nothing here for Core
                // Animation to interpolate. The call stays because a heading
                // can still change height — a longer name, a larger system text
                // size — and the table only re-asks when it is told to.
                table.noteHeightOfRows(withIndexesChanged: IndexSet(0..<table.numberOfRows))
            }
        }

        /// How tall the block around the table has to be, added up from the same
        /// numbers the table gives its own rows.
        ///
        /// **Added up now, delivered on the next turn.** The sum is exact the
        /// moment the update is handled — every row's height is measured off
        /// screen whether that row is on screen or not — but it is a `@State`
        /// of the block above, and writing to that from inside `updateNSView`
        /// is writing to state during a view update: SwiftUI drops it. Measured
        /// by doing it: the table kept the height it had, and everything past
        /// the fifth row was clipped.
        ///
        /// So it is handed over one turn later, which is a transaction of its
        /// own and therefore carries its own `withAnimation`. That used to cost
        /// about 30 ms, because the total was read back off the laid-out table
        /// and had to be re-read until it stopped changing —
        /// `usesAutomaticRowHeights` built row views lazily and the rows below
        /// the fold answered with estimates, once with a total 21 pt short.
        /// Now there is nothing to wait for and the turn is the whole delay.
        func reportHeight(_ report: @escaping (CGFloat) -> Void) {
            guard let table, table.bounds.width > 0 else {
                // First layout, before the table has been given a width: there
                // is nothing to measure against. The next update has the width.
                return
            }
            let total = max((0..<rows.count).reduce(CGFloat(0)) { sum, row in
                sum + tableView(table, heightOfRow: row)
            }, 1)
            guard total != reportedHeight else { return }
            reportedHeight = total
            let animate = pending == .animate
            DispatchQueue.main.async {
                // Inside the animation when the mode changed, bare otherwise —
                // a block appearing at its own size on first layout is not a
                // transition.
                if animate {
                    withAnimation(HelmMotion.interface) { report(total) }
                } else {
                    report(total)
                }
            }
        }

        // MARK: - Rows

        /// One row's SwiftUI, built the same way whether the table is asking
        /// for a view it does not have or being handed a new one for a view it
        /// already does.
        private func rowContent(_ row: Int) -> SidebarComposerRow? {
            guard rows.indices.contains(row), let model else { return nil }
            return SidebarComposerRow(row: rows[row], model: model, host: model.host)
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        /// The height a row's own SwiftUI comes to, measured off screen.
        ///
        /// Measured rather than tabulated: a row is type, and type grows with
        /// the system text size.
        ///
        /// **Measured against a model of its own, sitting still.** The live
        /// model is mid-animation when this is asked, and an animating height
        /// is not the height to animate *towards*. Cached by what the row says,
        /// which mode it is in and how wide it is drawn — the table asks for
        /// every row's height on every pass of the layout.
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard rows.indices.contains(row), let model else { return 40 }
            let width = tableView.bounds.width
            // A new width invalidates every measurement rather than adding a
            // second set beside them: the window is resizable, and a cache with
            // a row of history per pixel dragged is a leak with a lookup.
            if width != measuredWidth {
                heights.removeAll()
                measuredWidth = width
            }
            let said = state.content.indices.contains(row) ? state.content[row] : ""
            // The system's text size is in the key because a row is type: at a
            // larger size the same row is a taller row, and a cache that does
            // not say so hands back yesterday's height for the rest of the run.
            let key = "\(said)|\(editing)|\(width)|\(NSFont.systemFontSize)"
            if let known = heights[key] { return known }
            let still = Model(editing: editing, layout: model.layout, host: model.host,
                              apply: model.apply, rename: model.rename)
            let probe = NSHostingView(rootView: AnyView(
                SidebarComposerRow(row: rows[row], model: still, host: model.host)))
            probe.safeAreaRegions = []
            probe.frame.size.width = width
            var height = probe.fittingSize.height
            if case .module = rows[row] {
                height = max(height, SidebarComposerRow.height)
            }
            heights[key] = height
            return height
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            guard rows.indices.contains(row) else { return false }
            if case .section = rows[row] { return true }
            return false
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                       row: Int) -> NSView? {
            guard let content = rowContent(row) else { return nil }
            let hosting = NSHostingView(rootView: AnyView(content))
            // Without this the hosting view reserves a safe area of its own and
            // the cell comes out taller than the row it holds. Measured: the
            // content was 30 pt and the cell 32, so a 2 pt band of the *page*
            // showed between one row and the next — which broke the section's
            // card into a stack of slabs, the defect this is here to fix.
            hosting.safeAreaRegions = []
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
                  let model else { return false }
            model.apply(layout.applyingDrag(of: dragged, toFlatIndex: row))
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
    /// Observed, not passed by value: the mode has to change *inside* this view
    /// for SwiftUI to animate it. See `SidebarComposerTable.Model`.
    @ObservedObject var model: SidebarComposerTable.Model
    /// Observed as well, so a switch redraws its own row rather than waiting
    /// for the table to be told about it.
    @ObservedObject var host: ModuleHost

    private var layout: SidebarLayout { model.layout }
    private var editing: Bool { model.editing }
    private var apply: (SidebarLayout) -> Void { model.apply }
    private var rename: (SidebarLayout.Section) -> Void { model.rename }

    /// Natural sizes of the parts only edit mode has, recorded while they are
    /// on screen so they can be revealed by growing to them rather than by
    /// fading in (ARCHITECTURE.md § Motion).
    @State private var gripWidth: CGFloat = 0
    @State private var menuWidth: CGFloat = 0
    /// **The mode again, in the row's own hand.**
    ///
    /// `editing` arrives from the shared model, and a change to it does not
    /// bring an animation with it: the `withAnimation` that flipped it ran on
    /// the coordinator's stack, and each row is a separate `NSHostingView` with
    /// a renderer of its own. Measured by anchoring on the icon plate and
    /// reading its x across a ten-second transition — 608 px in one frame,
    /// 654 in the next, and nothing in between. `.animation(_:value:)` did not
    /// help either. What does is a `withAnimation` *here*, in the row's own
    /// update, over a piece of state the row owns.
    @State private var shown = false

    /// The gap between one section's card and the next heading. It is the
    /// heading's own top padding rather than table spacing, because
    /// `intercellSpacing` would put it between *every* pair of rows.
    private let sectionGap: CGFloat = 10

    /// The height macOS gives the list this one is a version of, measured on
    /// this machine rather than remembered: one line, an icon and a switch —
    /// Privacy ▸ Accessibility — is **40 pt**, separators every 80 px down a 2×
    /// capture with a 20 pt icon inset 10.
    ///
    /// **One number, not one per mode.** Edit mode used to grow every row to
    /// 53 pt to fit a second line, which moved everything below the block by
    /// 117 pt and was the whole reason two animation systems had to agree about
    /// height. The rows are the same in both modes now; what edit changes is
    /// what a row *contains*, and none of it is taller than the row.
    static let height: CGFloat = 40

    var body: some View {
        content
            // Set without an animation the first time, so a row built while the
            // table is already in edit is drawn in edit rather than animating
            // into it — a row that appears has nothing to animate *from*.
            .onAppear { shown = editing }
            .onChange(of: editing) { _, now in
                withAnimation(HelmMotion.interface) { shown = now }
            }
    }

    @ViewBuilder
    private var content: some View {
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
                // **The same label the sidebar draws, because this is a
                // picture of the sidebar.** It was 10 pt uppercase with the
                // redesign's own tracking, which made three styles of group
                // label in one window: the system's in the sidebar beside it,
                // the form's over the cards above it, and this.
                Text(AppStr.sectionTitle(section))
                    .font(HelmText.groupLabel)
                    .foregroundStyle(HelmText.quiet)
                if editing, section.seed == nil {
                    HelmBadge(AppStr.yourSection)
                }
                Spacer(minLength: 6)
                // Revealed by width, like everything else that only edit mode
                // has: a fade would draw the menu on top of the heading beside
                // it for a third of a second.
                menu(section)
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                        if width > 0 { menuWidth = width }
                    }
                    .frame(width: shown ? menuWidth : 0, alignment: .trailing)
                    .clipped()
                    // Width and ink together, like the grip: a glyph 14 pt wide
                    // has too little room to travel for the growth alone to be
                    // seen as motion rather than as an appearance.
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(editing)
                    .accessibilityHidden(!editing)
            }
            .padding(.horizontal, 4)

            // A section somebody just made is empty by definition, and an empty
            // section drawn as nothing is a heading followed by a heading with
            // no target between them. The card is still here; it just says so.
            if editing, section.modules.isEmpty {
                Text(AppStr.dragModuleHere)
                    .font(HelmText.rowTitle)
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
                .font(HelmText.rowDetail.weight(.medium))
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
        // `spacing: 0`, with every gap written as trailing padding *inside* the
        // thing it follows. A collapsed reveal is a view of zero width, and a
        // stack with spacing still puts its gap on both sides of one — so at
        // rest the icon would sit 10 pt further in than it does in the sidebar
        // this list is a picture of.
        return HStack(spacing: 0) {
            // Nine rows that can be dragged, and until now nothing said so. The
            // grip is the redesign's answer and it is also the only one that
            // works before the pointer is already on the row — and it appears
            // exactly when the drag does, so the two never disagree.
            //
            // Revealed by width rather than faded in, and by the same rule as
            // the buttons above the list: a fade puts the grip on top of the
            // icon plate for the length of the transition.
            Image(systemName: "line.3.horizontal")
                .font(HelmText.rowDetail.weight(.medium))
                .foregroundStyle(HelmText.faint)
                .accessibilityHidden(true)
                .fixedSize()
                .padding(.trailing, 10)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
                    if width > 0 { gripWidth = width }
                }
                .frame(width: shown ? gripWidth : 0)
                .clipped()
                // Width *and* ink. Eleven points of travel is over before the
                // eye follows it, so the grow alone read as a pop; the fade
                // gives the same 300 ms something to show.
                .opacity(shown ? 1 : 0)
            HelmIconPlate(symbol: descriptor.moduleMetadata.sfSymbol,
                          tint: descriptor.moduleTint.colour, size: 22,
                          active: host.isEnabled(descriptor))
                .padding(.trailing, 10)
            // **One line in both states.** The summary was the whole reason the
            // rows changed height, and a list that grows 9 rows by 13 pt each
            // moves everything below it by 117 — for a sentence the person had
            // already read on the module's own page. It stays as the tooltip.
            Text(descriptor.moduleMetadata.name)
                .font(HelmText.rowTitle)
                .help(descriptor.moduleMetadata.summary)
            Spacer(minLength: 28)
            Toggle(descriptor.moduleMetadata.name, isOn: Binding(
                get: { host.isEnabled(descriptor) },
                set: { host.setEnabled(descriptor, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        // 10, not the specification's 12: the `Form` card above this one puts
        // its labels 10 pt inside its own edge, and both cards start at the
        // same x. Two pt of difference is a column of text that does not line
        // up with the column of text above it, down the whole page.
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        // `maxHeight`, and the card is painted over the result. The cell the
        // table gives a row came out 2 pt taller than this content — measured,
        // with `intercellSpacing` confirmed at zero — and a content that does
        // not fill it sits centred, leaving 2 pt of the *page* above and below.
        // That is what broke each section's card into a stack of slabs with a
        // stripe of window between them.
        //
        // **The height is the table's, and it is the same in both modes.** It
        // lives in `SidebarComposerRow.height`, which the delegate applies. A
        // minimum here as well would be a second opinion about one number.
        .frame(maxHeight: .infinity)
        .opacity(host.isEnabled(descriptor) ? 1 : 0.55)
        .background(card(top: first, bottom: isLastInSection(sectionID)))
        // Inset 10/10 and in the system's own separator colour, both measured
        // off the `Form` card two inches up this same page: its rules run
        // 560…1917 inside a card of 540…1937, and step the luminance by
        // 0.00993 where a `HelmSurface.hairline` at half a point stepped it by
        // 0.01970 — exactly twice.
        //
        // The redesign specifies a full-bleed rule at 10% instead. It is right
        // on the specification's own page, which is not a `Form`; here the
        // thing this block is compared against is directly above it.
        .overlay(alignment: .top) {
            if !first {
                // `Divider`, not a rectangle in a colour of our choosing.
                // `HelmSurface.hairline` measured twice the system's step and
                // `NSColor.separatorColor` measured 0.04231 against the form's
                // 0.02843 — brighter still. The form does not draw its rules
                // in either; it draws them in this.
                Divider().padding(.horizontal, 10)
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
