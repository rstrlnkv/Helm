import AppKit
import SwiftUI

/// The one striped list in the house — an inset `List` with the system's own
/// alternating row fill turned on.
///
/// The colour is the system's, not the design system's: `NSTableView` paints
/// the second colour itself, so there is nothing for a token to name.
///
/// **Only on the `List` itself, never on a container above it**: the modifier
/// reaches every list and table in the subtree, so on a page's outer stack it
/// would stripe every `List` under that page. `command grep -rn
/// '\.helmStripedList(rowPitch' Sources` lists the lists that take it.
///
/// **Separators are each list's own job**: no modifier at the `List` level is
/// proven to hide every row's separator, so each list hides its own with
/// `.listRowSeparator(.hidden)` on the row or its `ForEach`.
///
/// **Not `.listRowBackground`**: a background painted row by row cannot tell
/// even from odd once a `Section` header row sits above it (`HomebrewPackageList`
/// has two sections), while `NSTableView` counts the rows it draws.
///
/// `.inset` is the pairing Apple's SDK asks for in the deprecation notice on
/// `.inset(alternatesRowBackgrounds:)`.
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
/// `HelmSpace`, set once as `defaultMinListRowHeight`, which SwiftUI hands to
/// the table as its `rowHeight` and applies as every row's minimum. Rows carry
/// no minimum of their own beside it, or the stripe under the list and the rows
/// above it could drift apart. The number is declared, not measured.
extension View {
    public func helmStripedList(rowPitch: CGFloat) -> some View {
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
