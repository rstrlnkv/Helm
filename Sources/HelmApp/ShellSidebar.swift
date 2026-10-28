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
/// **Typing the first letters of a row's name selects that row**, as a system list's type-select does
/// (`typeSelect`). The buffer is an event-stream value, so it has three ways to clear and none relies on
/// an event that may not come: a press after a gap longer than `typeSelectGap` (the time of each press is
/// compared with the last, there is no timer to cancel; `KeyPress` carries no timestamp, so it is read
/// when the handler runs), Escape, and the column losing focus. If none of them comes the
/// buffer lingers, and the next press after any gap starts afresh. A press with ⌘, ⌃ or ⌥ is not text and
/// passes. The match is by the name the row draws, anchored, blind to case, accents and width; no name in
/// the eight languages begins with an article. The column is a focusable view, not a text input client,
/// so a system input method does not compose into it. Tried in a script with the same match options,
/// not in a running window: katakana typed matches a katakana name; hiragana does not, and the kanji
/// names (重複, 設定) match nothing typed as kana; pinyin matches nothing.
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
    @State private var typedText = ""
    @State private var lastTyped = Date.distantPast

    init(model: SettingsModel, collapsed: Bool, toggleCollapsed: @escaping () -> Void) {
        self.model = model
        self.host = model.host
        self.collapsed = collapsed
        self.toggleCollapsed = toggleCollapsed
    }

    /// The owner's measures for the column, which Helm's ladders have no rung
    /// within a point of. The row's own are in `HelmSidebarRow`.
    nonisolated static let columnPad: CGFloat = 10
    nonisolated static let chevronColumn: CGFloat = 20
    nonisolated static let headingTop: CGFloat = 10

    /// How long the type-select buffer waits for the next letter. AppKit exposes no interval for its own
    /// type-select (`NSEvent` has `doubleClickInterval`, `keyRepeatDelay` and `keyRepeatInterval`, none of them
    /// type-select's), so the number is ours: well past
    /// the key-repeat delay, so a held key is not a gap, and short enough that a second word typed a
    /// moment later starts afresh. Not measured against the system's.
    nonisolated static let typeSelectGap: TimeInterval = 1

    /// The text a press adds to the type-select buffer, or nil when the press is not text for it.
    /// **Only Shift and Caps Lock may be held**; ⌘, ⌃ and ⌥ are shortcuts and pass. `.function` and
    /// `.numericPad` are refused too, as anything not listed (not tried against a running window).
    nonisolated static func typed(_ press: KeyPress, buffer: String) -> String? {
        guard acceptsModifiers(press.modifiers) else { return nil }
        return typeSelectText(press.characters, buffer: buffer)
    }

    nonisolated static func acceptsModifiers(_ modifiers: EventModifiers) -> Bool {
        modifiers.subtracting([.shift, .capsLock]).isEmpty
    }

    /// What of a press's `characters` is text. **Control characters and the function-key range
    /// (U+F700–U+F8FF, where AppKit puts the arrows, Home, End, F1…) are not text**, so an arrow can
    /// never join the buffer and be `.handled` away from the move command. A space with an empty
    /// buffer is not a start (whether space presses anything in this column is untried).
    nonisolated static func typeSelectText(_ characters: String, buffer: String) -> String? {
        let refused = { (scalar: Unicode.Scalar) in
            CharacterSet.controlCharacters.contains(scalar) || (0xF700...0xF8FF).contains(scalar.value)
        }
        guard !characters.isEmpty, !characters.unicodeScalars.contains(where: refused) else { return nil }
        if buffer.isEmpty && characters.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        return characters
    }

    /// The name a row draws, the one string the row, its tooltip and type-select all read.
    static func title(of row: ShellSidebarRows.Row) -> String {
        switch row {
        case .module(let id): return ModuleRegistry.descriptor(id)?.moduleMetadata.shortName ?? ""
        case .foot: return AppStr.settingsPane
        }
    }

    /// What the warning on a blocked row says, the strings the permission note already uses.
    private var blockedWarning: HelmSidebarRow.Warning {
        HelmSidebarRow.Warning(mark: AppStr.moduleBlockedByPermission, spoken: AppStr.moduleRowBlockedByPermission)
    }

    private func position(of row: ShellSidebarRows.Row, in rows: ShellSidebarRows) -> HelmSidebarRow.Position? {
        rows.position(of: row).map { HelmSidebarRow.Position(index: $0.index, count: $0.count) }
    }

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
                                HelmSidebarRow(
                                    title: Self.title(of: .module(id)),
                                    glyph: descriptor.moduleGlyph,
                                    selected: current == .module(id),
                                    collapsed: collapsed,
                                    warning: ShellSidebarRows.blocked(
                                        inertWithout: descriptor.moduleMetadata.inertWithout,
                                        disk: diskAccess, accessibility: accessibility,
                                        screenRecording: screenRecording) ? blockedWarning : nil,
                                    position: position(of: .module(id), in: rows)) {
                                    choose(.module(id))
                                }
                            }
                        }
                    }
                }
            }
            if collapsed {
                HelmSidebarRow(title: AppStr.showSidebar, glyph: .expand, selected: false,
                               collapsed: true, action: toggleCollapsed)
                footRow(selected: current == .foot, in: rows)
            } else {
                HStack(spacing: HelmSpace.s1) {
                    footRow(selected: current == .foot, in: rows).layoutPriority(1)
                    Button(action: toggleCollapsed) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: Self.chevronColumn, height: HelmSidebarRow.height)
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
        .onKeyPress(phases: .down) { press in
            typeSelect(press, in: rows)
        }
        .onChange(of: focused) { _, now in if !now { typedText = "" } }
        .helmTracksFullDiskAccess($diskAccess)
        .helmTracksAccessibility($accessibility)
        .helmTracksScreenRecording($screenRecording)
    }

    private func footRow(selected: Bool, in rows: ShellSidebarRows) -> some View {
        HelmSidebarRow(title: Self.title(of: .foot), glyph: .settings, selected: selected,
                       collapsed: collapsed, position: position(of: .foot, in: rows)) {
            choose(.foot)
        }
    }

    /// One key press of type-select. Escape clears the buffer and passes; a text press after a gap over
    /// `typeSelectGap` starts a new buffer; a match selects its row, no match changes nothing.
    private func typeSelect(_ press: KeyPress, in rows: ShellSidebarRows) -> KeyPress.Result {
        if press.key == .escape {
            typedText = ""
            return .ignored
        }
        let now = Date()
        let stale = now.timeIntervalSince(lastTyped) > Self.typeSelectGap
        guard let text = Self.typed(press, buffer: stale ? "" : typedText) else { return .ignored }
        typedText = (stale ? "" : typedText) + text
        lastTyped = now
        if let row = rows.row(typed: typedText, title: Self.title(of:)) { choose(row) }
        return .handled
    }

    private func choose(_ row: ShellSidebarRows.Row) {
        focused = true
        if let next = Self.selection(choosing: row, from: model.selection) { model.selection = next }
    }
}
