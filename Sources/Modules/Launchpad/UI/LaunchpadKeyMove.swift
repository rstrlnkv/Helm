import Foundation
import Module_Launchpad_Engine

/// **What a reorder by key or by VoiceOver means as a drop.** Pure: the window's drawn order in, a `LaunchpadDropDestination` out,
/// which `LaunchpadLayout.edit(dropping:)` and `LaunchpadScreenState.place` then write as they write a pointer's drop. No
/// index of the layout is ever written (the window draws a subset of `layout.items`: a hidden app and a page break are not
/// drawn), only anchors by id.
///
/// The order is the flat list of tiles drawn (a large folder is one stop), the index each page starts at (`LaunchpadPaging`),
/// and the indices at which a **stored** page break starts a new run (a page that ends only because it is full has none).
struct LaunchpadKeyMove: Equatable {
    /// What a chord or an action asks of a tile. The arrows are the arrow keys' own steps, so a chord goes where the choice goes.
    enum Kind: Equatable {
        /// Option+arrow, and Move earlier / Move later: one place toward the arrow.
        case move(dx: Int, dy: Int)
        /// Option+Shift+arrow, and the folder actions: onto the tile the arrow reaches (an app onto an app makes a folder).
        case combine(dx: Int, dy: Int)
        /// Move to the previous (-1) or next (+1) page.
        case page(Int)
        /// Out of the open card, to the place right after the folder's tile.
        case takeOut
    }

    let ids: [String]
    let folders: Set<String>
    let starts: [Int]
    let breaks: Set<Int>

    static let empty = LaunchpadKeyMove(ids: [], folders: [], starts: [0], breaks: [])

    /// Beside the tile at `to`, on the side the move comes from. Where a stored page break lies between the two the tile lands
    /// on the near side of the page it enters (first on the next, last on the previous) and the break stays where it is; where a
    /// page ends only because it is full, the page after the move is cut again by the capacity and the same rule lands it there too.
    /// nil: no such tile, or no move.
    func destination(from: Int, to: Int) -> LaunchpadDropDestination? {
        guard ids.indices.contains(from), ids.indices.contains(to), from != to else { return nil }
        var after = to > from
        if after, breaks.contains(to) { after = false } else if !after, breaks.contains(to + 1) { after = true }
        return .beside(ids[to], after: after)
    }

    /// Onto the tile at `to`. A folder never nests: nil for a carried folder.
    func combine(from: Int, to: Int) -> LaunchpadDropDestination? {
        guard ids.indices.contains(from), ids.indices.contains(to), from != to, !folders.contains(ids[from]) else { return nil }
        return .onto(ids[to])
    }

    /// The first tile of the next page, or the last of the previous; nil past the first and the last page (no page is made by key).
    func pageTarget(from: Int, step: Int) -> Int? {
        guard ids.indices.contains(from) else { return nil }
        let page = LaunchpadPaging.page(of: from, starts: starts)
        if step > 0 { return starts.indices.contains(page + 1) ? starts[page + 1] : nil }
        return page > 0 ? starts[page] - 1 : nil
    }

    /// Inside the open card: beside the member at `to`, in the folder's own order.
    static func inFolder(_ folder: UUID, ids: [String], from: Int, to: Int) -> LaunchpadDropDestination? {
        guard ids.indices.contains(from), ids.indices.contains(to), from != to else { return nil }
        return .intoFolder(folder, relativeTo: ids[to], after: to > from)
    }
}
