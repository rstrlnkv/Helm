import HelmContract
import HelmRuntime
import HelmUI

/// **The sidebar's rows as a value of two things, the arrangement and the set of
/// modules switched on: no view, no window.** A module that is off is not a row,
/// a section left with no module has no heading, and the foot row is always
/// there.
///
/// **The foot row stands for the three selections that are not a module.**
/// `SettingsSelection` has `.general`, `.log` and `.about` beside `.module`,
/// and this value gives all three the one row `.foot`.
///
/// **Not main-actor and no SwiftUI import**, so a test can build and question it
/// from values alone.
struct ShellSidebarRows: Equatable, Sendable {

    enum Row: Hashable, Sendable {
        case module(String)
        case foot
    }

    enum Direction: Sendable { case up, down }

    struct Group: Equatable, Sendable {
        /// Kept whole, not reduced to a name, so whoever draws the heading can
        /// title it from the section as it is stored.
        let section: SidebarLayout.Section
        /// The section's modules that are switched on, never empty.
        let modules: [String]
    }

    /// The sections that have something to list. **A module held by two
    /// sections appears only in the first**: a stored arrangement can hold one
    /// twice, and a row drawn in two places is two rows for one selection.
    let groups: [Group]

    /// Every group's modules in order, then the foot row.
    var rows: [Row] {
        groups.flatMap { $0.modules.map(Row.module) } + [.foot]
    }

    /// Each section's modules come from `SidebarLayout.live(in:enabled:)`, the
    /// call `SettingsWindow.swift`'s sidebar list makes too, so both read "on"
    /// from one function. An id that is enabled but held by no section is not
    /// listed: there is nowhere to put it.
    init(layout: SidebarLayout, enabled: Set<String>) {
        var seen = Set<String>()
        groups = layout.sections.compactMap { section in
            let live = layout.live(in: section, enabled: enabled).filter { seen.insert($0).inserted }
            return live.isEmpty ? nil : Group(section: section, modules: live)
        }
    }

    /// The row a selection selects, or nil when none leads there (no selection,
    /// or a module that is off or unknown).
    func row(for selection: SettingsSelection?) -> Row? {
        switch selection {
        case nil: return nil
        case .general, .log, .about: return .foot
        case .module(let id):
            let row = Row.module(id)
            return rows.contains(row) ? row : nil
        }
    }

    /// The row an arrow key lands on. **The list stops at both ends instead of
    /// wrapping**, and a row that is not in the list has no neighbour: nothing
    /// says where the person was, so the caller decides.
    func neighbour(of row: Row, moving direction: Direction) -> Row? {
        let all = rows
        guard let index = all.firstIndex(of: row) else { return nil }
        let next = direction == .up ? index - 1 : index + 1
        return all.indices.contains(next) ? all[next] : nil
    }

    /// Whether a module has declared it can do nothing without a permission
    /// macOS is currently withholding. `inertWithout` is what it declared, the
    /// three states are what macOS says now.
    ///
    /// The admin helper never blocks: it is a password prompt, not a grant that
    /// can silently go missing, and a warning that cannot be verified is worse
    /// than none.
    static func blocked(inertWithout: [ModulePermission], disk: PermissionState,
                        accessibility: PermissionState, screenRecording: PermissionState) -> Bool {
        inertWithout.contains { need in
            switch need {
            case .fullDisk: return disk == .denied
            case .accessibility: return accessibility == .denied
            case .screenRecording: return screenRecording == .denied
            case .adminHelper: return false
            }
        }
    }

    /// What a selection becomes when modules are switched on or off under the
    /// person. **A module that is off reads as General**, because the pane would
    /// otherwise keep showing a page no row leads to; everything else is
    /// returned unchanged. It asks only whether the id is on, not whether a
    /// section holds it.
    static func settled(_ selection: SettingsSelection, enabled: Set<String>) -> SettingsSelection {
        if case .module(let id) = selection, !enabled.contains(id) { return .general }
        return selection
    }

    /// The same for a selection that may be none, which stays none.
    static func settled(_ selection: SettingsSelection?, enabled: Set<String>) -> SettingsSelection? {
        selection.map { settled($0, enabled: enabled) }
    }
}
