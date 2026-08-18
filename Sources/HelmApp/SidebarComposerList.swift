import SwiftUI
import HelmUI

/// The sidebar's arrangement as a SwiftUI `List` — the prototype that asks
/// whether the `NSTableView` was necessary.
///
/// **The table exists because `.onMove` cannot cross a `Section`.** That is
/// true, and it stops being a problem the moment the sections are not
/// `Section`s: this list is one flat `ForEach` over `layout.flattened`, where a
/// heading is a row like any other and a section is something the rows *draw* —
/// the first module rounds the top corners, the last rounds the bottom. Then
/// `.onMove` hands over flat indices, which is exactly what
/// `SidebarLayout.applyingDrag(of:toFlatIndex:)` has always taken: the same
/// pure function, with the same tests, that the table's `acceptDrop` called.
///
/// What it buys is one renderer for the whole block, which is what the version
/// before the redesign had and what made its transition smooth without anything
/// being asked of it: `withAnimation` around `editing` reaches every row,
/// because there is no hosting view between them.
@MainActor
struct SidebarComposerList: View {
    let layout: SidebarLayout
    @ObservedObject var host: ModuleHost
    let editing: Bool
    @Binding var height: CGFloat
    let apply: (SidebarLayout) -> Void
    let rename: (SidebarLayout.Section) -> Void

    /// Measured per row and summed, the way the pre-redesign list did it: the
    /// block's height is an expression evaluated in the same pass, not a value
    /// reported back through a binding on a later turn of the run loop.
    @State private var heights: [String: CGFloat] = [:]

    /// At rest an empty section is a heading naming nothing, so it is not
    /// drawn — the sidebar itself does not draw it either.
    ///
    /// One spelling, read by the view and by `estimatedHeight`. It was written
    /// out in both, which is the pair that decides what is drawn and the pair
    /// that decides how tall it will be: the two disagreeing is a sheet sized
    /// for rows it does not show.
    static func rows(of layout: SidebarLayout, editing: Bool) -> [SidebarLayout.Row] {
        guard !editing else { return layout.flattened }
        return layout.flattened.filter { row in
            guard case .section(let id) = row else { return true }
            return !(layout.sections.first { $0.id == id }?.modules.isEmpty ?? true)
        }
    }

    private var rows: [SidebarLayout.Row] { Self.rows(of: layout, editing: editing) }

    private var total: CGFloat {
        max(rows.reduce(0) { $0 + (heights[$1.id] ?? Self.estimate(of: $1, in: layout, editing: editing)) }, 1)
    }

    /// What a row will be, before anything has been drawn.
    ///
    /// Measuring is more accurate and it arrives too late for the one caller
    /// that cannot wait: a sheet's window is sized by AppKit at presentation,
    /// so a height that lands a turn of the run loop later leaves the window at
    /// whatever the first frame asked for. `tableHeight` started at a flat 200,
    /// which put the sheet at its 360 pt floor while its content wanted 631 —
    /// title, Done, both footer buttons and the last two modules outside the
    /// window, and Escape the only way out.
    ///
    /// Pinned by `SidebarComposerHeightTests`, which draws the real list in a
    /// real window and compares. That test is the reason this is allowed to be
    /// a second opinion about a height rather than a number that drifts.
    static func estimate(of row: SidebarLayout.Row, in layout: SidebarLayout,
                         editing: Bool) -> CGFloat {
        switch row {
        case .module: return SidebarComposerListRow.height
        case .section(let id):
            let empty = layout.sections.first { $0.id == id }?.modules.isEmpty ?? true
            return SidebarComposerListRow.headerHeight(empty: empty, editing: editing)
        }
    }

    /// The whole list, for a caller that has to know before it draws.
    static func estimatedHeight(of layout: SidebarLayout, editing: Bool) -> CGFloat {
        max(rows(of: layout, editing: editing)
                .reduce(0) { $0 + estimate(of: $1, in: layout, editing: editing) }, 1)
    }

    var body: some View {
        // Spelled out rather than inlined: the ternary is an optional closure,
        // which the type checker cannot infer inside a `List` builder. **The
        // drag is off at rest** — a row that lifts under a pointer that meant to
        // scroll changes an arrangement nobody asked to change, and there is no
        // undo here.
        var onMove: ((IndexSet, Int) -> Void)?
        if editing { onMove = { move(from: $0, to: $1) } }
        return List {
            ForEach(rows, id: \.id) { row in
                SidebarComposerListRow(row: row, layout: layout, host: host,
                                       editing: editing, apply: apply, rename: rename)
                    // `interface`, not the modifier's default: what these
                    // measurements correct is a row that is already being
                    // reordered on that curve, and two systems need one curve
                    // rather than one duration.
                    //
                    // The store is a dictionary, so «not measured yet» is a
                    // missing key rather than a sentinel — which is the state
                    // the modifier's `CGFloat?` is named after. The first
                    // measurement of a row is the answer and not a change here
                    // for a reason of this list's own: `total` has already
                    // counted that row, by estimate.
                    .helmMeasuredHeight(Binding(get: { heights[row.id] },
                                                set: { heights[row.id] = $0 }),
                                        animation: HelmMotion.interface)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: onMove)
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .frame(height: total)
        // **Said explicitly, because the sum lands a pass late.** The rows
        // report their measured heights during layout, so `total` changes after
        // the transaction that flipped the mode has closed — and what animated
        // it then was whatever transaction happened to be open, which is how the
        // block came to trail its own rows by a tenth of a second.
        .animation(HelmMotion.interface, value: total)
        // The sheet's own window is sized from this, so it has to travel in the
        // same transaction as the list inside it. Written raw, the list ramped
        // inside a window that jumped.
        .onChange(of: total) { _, now in
            withAnimation(HelmMotion.interface) { height = now }
        }
        .onAppear { height = total }
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let index = source.first, rows.indices.contains(index) else { return }
        apply(layout.applyingDrag(of: rows[index], toFlatIndex: destination))
    }
}

/// One line of the list: a section's heading with its menu, or a module with its
/// switch. The drawing is the table's, unchanged — what changes is who owns the
/// renderer it draws into.
@MainActor
struct SidebarComposerListRow: View {
    let row: SidebarLayout.Row
    let layout: SidebarLayout
    @ObservedObject var host: ModuleHost
    let editing: Bool
    let apply: (SidebarLayout) -> Void
    let rename: (SidebarLayout.Section) -> Void

    /// The height macOS gives the list this one is a version of: one line, an
    /// icon and a switch — Privacy ▸ Accessibility — is 40 pt.
    static let height: CGFloat = 40
    /// The gap between one section's card and the next heading.
    private static let sectionGap: CGFloat = 10
    /// An 11 pt semibold line, as `HelmText.groupLabel` draws it.
    private static let headerLabelHeight: CGFloat = 13
    /// The drop target an empty section shows while editing, and the 5 pt the
    /// header's own `VStack` puts above it.
    private static let dropZoneHeight: CGFloat = 30

    /// A heading row, without drawing it. Same arithmetic as `header(_:)`
    /// directly below — kept beside it so the two are read together.
    static func headerHeight(empty: Bool, editing: Bool) -> CGFloat {
        let showsDropZone = empty && editing
        return sectionGap                              // .padding(.top)
            + headerLabelHeight
            + (showsDropZone ? 5 + dropZoneHeight : 0) // VStack spacing + the zone
            + (empty ? 0 : 5)                          // .padding(.bottom)
    }

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

    private func header(_ section: SidebarLayout.Section) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(AppStr.sectionTitle(section))
                    .font(HelmText.groupLabel)
                    .foregroundStyle(HelmText.quiet)
                if editing, section.seed == nil {
                    HelmBadge(AppStr.yourSection)
                }
                Spacer(minLength: 6)
                if editing { menu(section) }
            }
            .padding(.horizontal, 4)

            if editing, section.modules.isEmpty {
                Text(AppStr.dragModuleHere)
                    .font(HelmText.rowTitle)
                    .foregroundStyle(HelmText.faint)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(card(top: true, bottom: true))
            }
        }
        .padding(.top, Self.sectionGap)
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

    private func module(_ descriptor: any ModuleDescriptor, in sectionID: String) -> some View {
        let first = isFirstInSection(sectionID)
        return HStack(spacing: HelmSpace.s5) {
            // Plain insertion, as before the redesign: one tree, so the
            // `withAnimation` that flips the mode reaches this.
            if editing {
                Image(systemName: "line.3.horizontal")
                    .font(HelmText.rowDetail.weight(.medium))
                    .foregroundStyle(HelmText.faint)
                    .accessibilityHidden(true)
            }
            HelmIconPlate(symbol: descriptor.moduleMetadata.sfSymbol,
                          tint: descriptor.moduleTint.colour, size: 22,
                          active: host.isEnabled(descriptor))
            // 6 more than the stack's own 10, because a letter does not start
            // where its box does: measured at 2x, the plate-to-glyph gap read
            // 7.5 pt where the handle-to-plate gap beside it read 11, and the
            // difference is the side bearing of whatever letter the name
            // begins with. The eye compares the two gaps, not the numbers.
            Text(descriptor.moduleMetadata.name)
                .font(HelmText.rowTitle)
                .padding(.leading, 6)
                .help(descriptor.moduleMetadata.summary)
            Spacer(minLength: 18)
            Toggle(descriptor.moduleMetadata.name, isOn: Binding(
                get: { host.isEnabled(descriptor) },
                set: { host.setEnabled(descriptor, $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(minHeight: Self.height)
        .opacity(host.isEnabled(descriptor) ? 1 : 0.55)
        .background(card(top: first, bottom: isLastInSection(sectionID)))
        .overlay(alignment: .top) {
            if !first { Divider().padding(.horizontal, 10) }
        }
    }

    private func card(top: Bool, bottom: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: top ? HelmRadius.card : 0,
            bottomLeadingRadius: bottom ? HelmRadius.card : 0,
            bottomTrailingRadius: bottom ? HelmRadius.card : 0,
            topTrailingRadius: top ? HelmRadius.card : 0,
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
