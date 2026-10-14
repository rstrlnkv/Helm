import HelmContract
import HelmRuntime
import HelmUI
import SwiftUI

/// **The column that stands on the window's backdrop: section headings, a row
/// for each module that is on, and the row for Helm's own three pages at the
/// foot.** Expanded it shows names; narrowed to a rail it shows glyphs only, a
/// divider in place of each heading and a row above the foot row that widens
/// it again. Whoever hosts it gives it its width.
///
/// **Rows are `Button`s, and the column takes keyboard focus.** A column of
/// plain buttons does not move a selection by arrow keys the way a `List` did,
/// so Up and Down are handled here and go through
/// `ShellSidebarRows.neighbour`; at either end they change nothing.
///
/// **It observes `host` itself.** The rows are filtered by whether a module is
/// on, and switching a module off in Settings calls `ModuleHost.setEnabled`
/// directly, which posts nothing this view listens for. `model.host` is a plain
/// `let`, so reaching it through the model would not redraw: the row of a
/// module that had just been switched off would stay until something else
/// invalidated the view. It is not about where the value is read from — "on" is
/// read from the store — but about being redrawn at all.
struct ShellSidebar: View {
    @ObservedObject private var model: SettingsModel
    @ObservedObject private var host: ModuleHost
    private let collapsed: Bool
    private let toggleCollapsed: () -> Void

    // Each starts at `.granted`, filled in by the trackers below as the column
    // appears and again when Helm comes forward. `blocked` asks only whether a
    // state is `.denied`, so a module that works never shows a mark in the
    // moment before the first probe answers.
    @State private var diskAccess: PermissionState = .granted
    @State private var accessibility: PermissionState = .granted
    @State private var screenRecording: PermissionState = .granted
    @FocusState private var focused: Bool

    init(model: SettingsModel, collapsed: Bool, toggleCollapsed: @escaping () -> Void) {
        self.model = model
        self.host = model.host
        self.collapsed = collapsed
        self.toggleCollapsed = toggleCollapsed
    }

    /// The owner's measures for the column, which Helm's ladders have no rung
    /// within a point of. `dotSide` is not one of them: it is the side
    /// `HelmStatusDot` draws its dot at.
    nonisolated static let rowHeight: CGFloat = 36
    nonisolated static let columnPad: CGFloat = 10
    nonisolated static let glyphSide: CGFloat = 16 * 1.3
    nonisolated static let chevronColumn: CGFloat = 20
    nonisolated static let selectionRadius: CGFloat = 8
    nonisolated static let dotSide: CGFloat = 8
    nonisolated static let headingTop: CGFloat = 10

    /// The ink of the mark on a module that is on and cannot act. The one place
    /// that names it, so choosing another colour changes this line alone.
    static var blockedInk: Color { HelmSignal.warning }

    nonisolated static func direction(_ command: MoveCommandDirection) -> ShellSidebarRows.Direction? {
        switch command {
        case .up: return .up
        case .down: return .down
        default: return nil
        }
    }

    /// Where an arrow key lands. **With no current row, down lands on the first
    /// row and up on the foot row**, the two ends the list starts from; nil is
    /// an edge, and the caller changes nothing.
    nonisolated static func landing(from current: ShellSidebarRows.Row?,
                                    moving direction: ShellSidebarRows.Direction,
                                    in rows: ShellSidebarRows) -> ShellSidebarRows.Row? {
        guard let current else { return direction == .down ? rows.rows.first : .foot }
        return rows.neighbour(of: current, moving: direction)
    }

    /// What choosing a row writes into the selection. **nil: the row is already
    /// the selected one, write nothing.** The foot row stands for three pages,
    /// so choosing it while one of them is open must not reset the tab to
    /// General.
    nonisolated static func selection(choosing row: ShellSidebarRows.Row,
                                      from current: SettingsSelection?) -> SettingsSelection? {
        let target: SettingsSelection
        switch row {
        case .module(let id): target = .module(id)
        case .foot:
            switch current {
            case .general, .log, .about: return nil
            default: target = .general
            }
        }
        return target == current ? nil : target
    }

    /// Asked once for the whole column: the arrangement is a store read plus a
    /// reconcile, and "on" is a store read per module. The order is read from
    /// settings, which SwiftUI cannot observe, so the revision is read to
    /// redraw when it changes.
    private var rows: ShellSidebarRows {
        _ = model.orderRevision
        return ShellSidebarRows(
            layout: SidebarLayoutStore.read(from: AppSettings.store, registry: SidebarLayoutStore.registry()),
            enabled: host.enabledModuleIDs)
    }

    var body: some View {
        let rows = self.rows
        let current = rows.row(for: model.selection)
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: HelmSpace.s2) {
                    // By position: a section's id can repeat in a stored arrangement.
                    ForEach(Array(rows.groups.enumerated()), id: \.offset) { offset, group in
                        if collapsed {
                            Divider()
                                .padding(.horizontal, Self.columnPad).padding(.vertical, HelmSpace.s3)
                                .opacity(offset == 0 ? 0 : 1)
                        } else if !AppStr.sectionTitle(group.section).isEmpty {
                            Text(AppStr.sectionTitle(group.section))
                                .font(HelmText.rowDetail.weight(.medium))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .padding(.horizontal, HelmSpace.s4)
                                .padding(.top, Self.headingTop).padding(.bottom, HelmSpace.s2)
                        }
                        ForEach(group.modules, id: \.self) { id in
                            if let descriptor = ModuleRegistry.descriptor(id) {
                                ShellSidebarRow(
                                    title: descriptor.moduleMetadata.shortName,
                                    glyph: descriptor.moduleGlyph,
                                    selected: current == .module(id),
                                    collapsed: collapsed,
                                    blocked: ShellSidebarRows.blocked(
                                        inertWithout: descriptor.moduleMetadata.inertWithout,
                                        disk: diskAccess, accessibility: accessibility,
                                        screenRecording: screenRecording)) {
                                    choose(.module(id))
                                }
                            }
                        }
                    }
                }
            }
            if collapsed {
                ShellSidebarRow(title: AppStr.showSidebar, glyph: .expand, selected: false,
                                collapsed: true, blocked: false, action: toggleCollapsed)
                footRow(selected: current == .foot)
            } else {
                HStack(spacing: HelmSpace.s1) {
                    footRow(selected: current == .foot).layoutPriority(1)
                    Button(action: toggleCollapsed) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(HelmText.quiet)
                            .frame(width: Self.chevronColumn, height: Self.rowHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(AppStr.hideSidebar)
                    .accessibilityLabel(AppStr.hideSidebar)
                }
            }
        }
        .padding(.horizontal, Self.columnPad)
        .padding(.bottom, Self.columnPad)
        // The column takes focus when a row is chosen, so the arrows move the
        // selection from there. No system ring: the selected row is the mark.
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onMoveCommand { command in
            guard let direction = Self.direction(command),
                  let row = Self.landing(from: current, moving: direction, in: rows) else { return }
            choose(row)
        }
        .helmTracksFullDiskAccess($diskAccess)
        .helmTracksAccessibility($accessibility)
        .helmTracksScreenRecording($screenRecording)
    }

    private func footRow(selected: Bool) -> some View {
        ShellSidebarRow(title: AppStr.settingsPane, glyph: .settings, selected: selected,
                        collapsed: collapsed, blocked: false) {
            choose(.foot)
        }
    }

    private func choose(_ row: ShellSidebarRows.Row) {
        focused = true
        if let next = Self.selection(choosing: row, from: model.selection) { model.selection = next }
    }
}

/// One row: the glyph, filled when the row is selected, and the name; in the
/// rail the glyph alone. The name is the tooltip in both, for a name cut short
/// in the column, and the accessibility label.
private struct ShellSidebarRow: View {
    let title: String
    let glyph: ShellGlyph
    let selected: Bool
    let collapsed: Bool
    let blocked: Bool
    let action: () -> Void
    @State private var hover = false

    // The owner's fills for the selected and the hovered row.
    private static let selectedFill = 0.10
    private static let hoverFill = 0.05

    init(title: String, glyph: ShellGlyph, selected: Bool, collapsed: Bool, blocked: Bool,
         action: @escaping () -> Void) {
        self.title = title
        self.glyph = glyph
        self.selected = selected
        self.collapsed = collapsed
        self.blocked = blocked
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: HelmSpace.s4) {
                ShellGlyphView(glyph, filled: selected, size: ShellSidebar.glyphSide)
                    // In the rail the mark sits on the glyph's own frame, so the
                    // glyph does not shift between a row that has one and one
                    // that has not. Centred on the frame's corner, the dot
                    // clears the glyph's strokes.
                    .overlay(alignment: .topTrailing) { if collapsed && blocked { mark.offset(x: ShellSidebar.dotSide / 2, y: -ShellSidebar.dotSide / 2) } }
                if !collapsed {
                    HStack(spacing: HelmSpace.s3) {
                        Text(title).font(HelmText.rowTitle).lineLimit(1)
                        if blocked { mark }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .padding(.horizontal, collapsed ? 0 : HelmSpace.s4)
            .frame(height: ShellSidebar.rowHeight)
            .foregroundStyle(selected ? .primary : .secondary)
            .background(
                RoundedRectangle(cornerRadius: ShellSidebar.selectionRadius, style: .continuous)
                    .fill(Color.primary.opacity(selected ? Self.selectedFill : hover ? Self.hoverFill : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(blocked ? AppStr.moduleRowBlockedByPermission : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The module is on and cannot act. One fact, a small round mark; the pane
    /// the row leads to is where it is fixed.
    private var mark: some View {
        Circle()
            .fill(ShellSidebar.blockedInk)
            .frame(width: ShellSidebar.dotSide, height: ShellSidebar.dotSide)
            .help(AppStr.moduleBlockedByPermission)
            .accessibilityLabel(AppStr.moduleBlockedByPermission)
    }
}
