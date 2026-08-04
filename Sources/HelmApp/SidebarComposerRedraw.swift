import Foundation

/// What the composer table is showing, as a value it can be compared against.
///
/// `content` is one line per row, holding everything a row *draws* that is not
/// its identity — its name, whether its switch is on, whether it rounds the
/// card. Two states with the same `rowIDs` and the same `content` look the
/// same, so nothing has to be done about the difference between them.
struct SidebarComposerState: Equatable {
    var rowIDs: [String]
    var editing: Bool
    var content: [String]

    static let none = SidebarComposerState(rowIDs: [], editing: false, content: [])
}

/// What an update has to do to the table to show the new state.
///
/// **The decision is a value because the call it is made in is not one call.**
/// SwiftUI runs `updateNSView` for every change in the block around the table,
/// and the block changes when the table reports its own height — so a single
/// click on Edit arrives as several updates, of which only the first has
/// anything to say. Deciding by hand inside that call reloaded the table 31 ms
/// into a 300 ms transition (measured, with the duration temporarily at 4 s):
/// `reloadData` throws away every row view, so the rows snapped to their new
/// shape while the note and the two buttons above them went on animating.
enum SidebarComposerRedraw: Equatable {
    /// Nothing that shows has changed. The height report coming back round is
    /// this, and it must not touch the table.
    case nothing
    /// The same rows, saying something new. Handed their contents, no transition.
    case refresh
    /// The same rows in the other mode: the one case a row changes shape, and
    /// the only one that animates.
    case animate
    /// Which rows exist has changed. A row that has to appear is not a row that
    /// can change shape.
    case reload

    static func between(_ old: SidebarComposerState,
                        _ new: SidebarComposerState) -> SidebarComposerRedraw {
        if old.rowIDs != new.rowIDs { return .reload }
        if old.editing != new.editing { return .animate }
        if old.content != new.content { return .refresh }
        return .nothing
    }
}
