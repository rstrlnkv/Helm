import AppKit
import SwiftUI

/// The one striped list in the house — an inset `List` with the system's own
/// alternating row fill turned on.
///
/// The colour is the system's, not the design system's: `#F4F5F5` in the light
/// appearance, white at 4.7% in the dark one, measured on macOS 27.2. There is
/// no token for it because there is nothing to choose — `NSTableView` paints
/// the second colour itself, and a token here would name a value this house
/// does not set.
///
/// **Only on the `List` itself, never on a page or a container above it.**
/// Apple's own wording for the modifier is "lists and tables in this view" —
/// it reaches the whole subtree it is attached to, not one list picked out of
/// several. Putting it on a page's outer stack would stripe every `List`
/// mounted under that page, which is the one way Disk, Duplicates or
/// Autopilot could end up striped by accident; the lists that take it are
/// `command grep -rn '\.helmStripedList(rowPitch' Sources`.
///
/// **Separators are each list's own job, not this modifier's.** There is no
/// proven way for a modifier at the `List` level to hide the separator on
/// every row under it; each striped list in this house hides its own with
/// `.listRowSeparator(.hidden)` on the row or the `ForEach` that produces it,
/// the way `OrphansView` already did before this modifier existed.
///
/// **Why not `.listRowBackground`.** A background painted row by row cannot
/// tell which row is even and which is odd once a `Section` — with its own
/// header row — sits above it; `HomebrewSettingsPage`'s health list carries
/// three sections in one `List` and its package list two; alternation there is `NSTableView`'s own
/// count of the rows it draws, not a colour this code could compute row by
/// row and get right.
///
/// `.inset` is the pairing Apple's own SDK asks for: the deprecation notice on
/// `.inset(alternatesRowBackgrounds:)` reads "Use the `.inset` style with the
/// `.alternatingRowBackgrounds()` view modifier." Both sides of that pair are
/// available from macOS 14, well under this platform's floor of 26.0.
///
/// **Below the last row, the stripe repeats at the table's own `rowHeight`, and
/// each list declares that step itself.** AppKit's header for `rowHeight` says
/// so in as many words: "For variable row height tableViews … -rowHeight will
/// be used to draw alternating rows past the last row in the tableView"
/// (`NSTableView.h`, on `rowHeight`; the same reason Finder's empty area
/// repeats at one step whatever the rows above it are). A SwiftUI `List` is
/// variable-height, so that number is the empty area's pitch and not a limit on
/// any row: **a row taller than `rowPitch` — a failure line that wraps, a name
/// that takes two — keeps its own height, and only the area under the last row
/// is drawn at the pitch.**
///
/// `rowPitch` is the one step the list's rows are laid out at, taken from
/// `HelmSpace`, and it is set once as `defaultMinListRowHeight`, which SwiftUI
/// hands to the table as its `rowHeight` and applies as the minimum height of
/// every row. The caller passes one step and its rows carry no minimum of
/// their own beside it — a second literal on a row would let the stripe under
/// the list and the rows above it drift apart the day one of them moves. Nothing is measured
/// at run time: the number is declared, so there is no reading that can be
/// stale and no second view to keep in step with the list.
public extension View {
    func helmStripedList(rowPitch: CGFloat) -> some View {
        modifier(HelmStripedListModifier(rowPitch: rowPitch))
    }
}

private struct HelmStripedListModifier: ViewModifier {
    let rowPitch: CGFloat

    func body(content: Content) -> some View {
        content.listStyle(.inset).alternatingRowBackgrounds()
            .environment(\.defaultMinListRowHeight, rowPitch)
    }
}
