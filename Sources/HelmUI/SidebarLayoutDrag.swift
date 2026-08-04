import Foundation

/// The flat view of a layout, and the arithmetic of a drop into it.
///
/// `NSTableView` speaks in row indices and knows nothing about sections;
/// `SidebarLayout` speaks in sections and knows nothing about rows. Everything
/// that translates between the two lives here, so a drop landing in the wrong
/// section is a failing test rather than something noticed later — the table
/// itself only reports *which row* and *which index*.
public extension SidebarLayout {

    /// One line of the table: a section's heading, or a module inside one.
    enum Row: Equatable, Identifiable, Sendable {
        case section(String)
        case module(String, in: String)

        public var id: String {
            switch self {
            case .section(let id): return "section:\(id)"
            case .module(let id, let section): return "module:\(section):\(id)"
            }
        }
    }

    /// Heading, then its modules, section after section.
    ///
    /// An empty section is still one row. It has to be: without a heading there
    /// is nothing to drop the first module onto, and a section somebody just
    /// made is empty by definition.
    var flattened: [Row] {
        sections.flatMap { section in
            [Row.section(section.id)] + section.modules.map { Row.module($0, in: section.id) }
        }
    }

    /// The layout after `row` is dropped with the insertion indicator above
    /// `flatIndex`. `flatIndex == flattened.count` is a drop past the last row.
    func applyingDrag(of row: Row, toFlatIndex flatIndex: Int) -> SidebarLayout {
        switch row {
        case .module(let module, _): return droppingModule(module, at: flatIndex)
        case .section(let section): return droppingSection(section, at: flatIndex)
        }
    }

    // MARK: - A module

    private func droppingModule(_ module: String, at flatIndex: Int) -> SidebarLayout {
        let rows = flattened
        // Above the first heading there is no section. Clamping into the first
        // one beats refusing: the indicator was already drawn there, and a drop
        // that does nothing where the table promised something is the table
        // lying about itself.
        let owner = sectionOwning(flatIndex, in: rows)
        guard let sectionID = owner ?? sections.first?.id else { return self }

        var before: String?
        if owner == nil {
            // Clamped from above the first heading. The indicator was at the
            // very top of the table, so the module goes to the front of the
            // first section — appending it would drop it as far as possible
            // from where the person aimed.
            before = sections.first?.modules.first { $0 != module }
        } else if flatIndex < rows.count,
                  case .module(let next, let itsSection) = rows[flatIndex],
                  itsSection == sectionID, next != module {
            // What it lands in front of, but only when that row is a module of
            // the same section. A heading or the end of the table both mean the
            // end of this section.
            before = next
        }
        return moving(module, toSection: sectionID, before: before)
    }

    /// The section a drop at `flatIndex` belongs to.
    ///
    /// The row immediately above the indicator always names one — a heading
    /// names its own section and a module names the section holding it — so
    /// this looks one row up and no further. It was written as a search
    /// backwards, which was a loop that could never take a second turn and read
    /// as if it might.
    private func sectionOwning(_ flatIndex: Int, in rows: [Row]) -> String? {
        let above = min(flatIndex, rows.count) - 1
        guard above >= 0 else { return nil }
        switch rows[above] {
        case .section(let id): return id
        case .module(_, let id): return id
        }
    }

    // MARK: - A section

    private func droppingSection(_ section: String, at flatIndex: Int) -> SidebarLayout {
        let rows = flattened
        // A heading dropped among another section's modules lands *before* that
        // section rather than splitting it in half: a section inside a section
        // is not a thing this layout can hold, and the person dragged a group.
        // The modules travel with it, because leaving them behind would file
        // them under a heading that no longer describes them.
        guard flatIndex < rows.count else { return movingSection(section, before: nil) }
        let target: String?
        switch rows[flatIndex] {
        case .section(let id): target = id
        case .module(_, let id): target = id
        }
        guard let target, target != section else { return self }
        return movingSection(section, before: target)
    }
}
