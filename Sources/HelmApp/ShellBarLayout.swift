import CoreGraphics
import HelmRuntime

/// **The bar's arithmetic, as numbers in and numbers out: from the natural
/// widths of its zones, its own width, where the card stands in the window and
/// where the window's buttons end, one frame per zone and two verdicts, whether
/// the tabs are folded to one item and whether the search is folded to its
/// magnifier.** No view, no window; nothing here holds state.
///
/// Frames are in the bar's own coordinates: origin top-left, x to the right,
/// and x 0 is the card's minX in the window. Nothing is rounded. A zone is
/// present when its width is above zero (the search: when `hasSearch`); an
/// absent zone's frame is `.zero`, a present one stands on the row at
/// `controlTop`, `controlHeight` high.
///
/// **Where things stand.** The name starts at `leading`, or `obstacleClearance`
/// right of the window's buttons when they end further right. The status, if
/// any, ends `statusTrailing` from the bar's right edge. The actions and the
/// search stand in a chain from the right, `trailing` in from the edge (or one
/// `zoneGap` before the status): search last, the actions before it. The tabs
/// are centred on the *window*, not on the bar, and held between what the name
/// leaves on the left and what the chain leaves on the right.
///
/// **What gives way, in this order.** The search narrows from `searchWidth`
/// down to `searchFloor` to leave the tabs their room, centred while the name
/// allows it. Then the tabs fold to
/// `tabsFoldedWidth`. Then the search folds to its magnifier. Only after that
/// does the name truncate, and nothing else ever changes width. A search that
/// is in use is never folded for room, and a search the setting keeps at rest
/// is a magnifier whatever the room. A folded zone stays folded when the room
/// the fold freed would fit the open one again, so each verdict is one threshold
/// in the bar's width and nothing flaps. `fits` is false when even a name of
/// width 0 leaves no room: the tabs then start left of where the name would end
/// and nothing else moves.
///
/// **Bad numbers.** Every width is brought into `0...1_000_000` (not-a-number
/// reads 0), `cardMinX` into `-1_000_000...1_000_000`, so every frame is finite.
/// The window's buttons are an obstacle only when the rect is a place: not
/// null, not infinite, finite x and width, and a width and height above zero;
/// their row is ignored.
///
/// `controlHeight`, `controlBottom`, `actionsToSearch` and `searchWidth` are
/// readings of Helm's own toolbar in a 1060-point window, the bar inside the
/// system's titlebar. `leading` is the inset that toolbar gives its name, 16;
/// the name's own view read 16.5 from the card there. `edge`, and with it
/// `controlTop` and `trailing`, is not a reading: there the controls stood 4
/// below the card's top and ended 4 before its right edge, and inside the
/// card the bar keeps 8. `searchFloor`, `magnifierWidth`, `obstacleClearance`,
/// `nameGap`, `zoneGap` and `statusTrailing` are Helm's choices, not readings.
enum ShellBarLayout {

    /// The gap above the controls. Helm's choice for the bar inside the card;
    /// in the system's titlebar the controls, measured, stand 8 below the
    /// window's top, 4 below the card's.
    nonisolated static let edge: CGFloat = 8

    /// The height of every zone's frame on the row; the tabs, the actions and
    /// the search read 36, the name's view 24.
    nonisolated static let controlHeight: CGFloat = 36

    /// The gap below the controls.
    nonisolated static let controlBottom: CGFloat = 8

    /// Where the row starts, from the bar's top.
    nonisolated static let controlTop: CGFloat = edge

    /// How far the last control stands from the bar's right edge.
    nonisolated static let trailing: CGFloat = edge

    /// The bar's height.
    nonisolated static let height: CGFloat = edge + controlHeight + controlBottom

    /// Where the name starts when nothing is left of it, from the bar's left
    /// edge. The inset Helm's toolbar gives its name; the name's view read 16.5.
    nonisolated static let leading: CGFloat = 16

    /// How far right of the window's buttons the name starts. Helm's choice.
    nonisolated static let obstacleClearance: CGFloat = 8

    /// The space after the name. Helm's choice.
    nonisolated static let nameGap: CGFloat = 8

    /// The space between any two other neighbours. Helm's choice.
    nonisolated static let zoneGap: CGFloat = 4

    /// The space between the actions and the search, measured.
    nonisolated static let actionsToSearch: CGFloat = 4

    /// The search field's width when it has all the room it wants, measured.
    nonisolated static let searchWidth: CGFloat = 283

    /// The narrowest an open search field is made. Helm's choice, not a
    /// reading.
    nonisolated static let searchFloor: CGFloat = 120

    /// The width of the folded search, the magnifier. Helm's choice, not a
    /// reading.
    nonisolated static let magnifierWidth: CGFloat = 36

    /// How far the status stands from the bar's right edge. Its own box
    /// carries the ink's inset, so none is added here. Helm's choice.
    nonisolated static let statusTrailing: CGFloat = 0

    /// The ceiling every input is brought under.
    private nonisolated static let widest: CGFloat = 1_000_000

    /// Points. Bar coordinates are the ones `ShellBarLayout`'s comment gives.
    struct Input: Equatable, Sendable {
        /// The bar's width.
        var barWidth: CGFloat
        /// The card's minX, in the window's coordinates.
        var cardMinX: CGFloat
        /// The window's content width.
        var windowWidth: CGFloat
        /// The natural widths of the zones; 0 is an absent zone.
        var nameWidth: CGFloat
        /// The tabs unfolded.
        var tabsWidth: CGFloat
        /// The tabs folded to one item.
        var tabsFoldedWidth: CGFloat
        /// The width the actions reserve, not the one they show.
        var actionsWidth: CGFloat
        /// The status view's own box, its ink inset included.
        var statusWidth: CGFloat
        var hasSearch: Bool
        /// The setting that keeps the search a magnifier at rest.
        var alwaysCollapseSearch: Bool
        /// The field's text is not empty, or it is being edited.
        var searchInUse: Bool
        /// What the name must clear, in bar coordinates: the window's buttons' union, or in the rail the
        /// closed capsule that stands in for them; `.zero` or `.null` for none.
        var buttons: CGRect
    }

    struct Frames: Equatable, Sendable {
        var name: CGRect
        var tabs: CGRect
        var actions: CGRect
        /// The field, or the magnifier when `searchFolded`.
        var search: CGRect
        var status: CGRect
        var tabsFolded: Bool
        var searchFolded: Bool
        /// False when even a name of width 0 leaves no room.
        var fits: Bool
    }

    // MARK: - the layout

    /// **The frames and verdicts for `input`.** Total: every input gives
    /// finite frames.
    nonisolated static func frames(for input: Input) -> Frames {
        let width = bounded(input.barWidth)
        let windowWidth = bounded(input.windowWidth)
        let cardMinX = input.cardMinX.clamped(to: -widest...widest, whenNotANumber: 0)
        let nameWidth = bounded(input.nameWidth)
        let tabsWidth = bounded(input.tabsWidth)
        let foldedWidth = bounded(input.tabsFoldedWidth)
        let actionsWidth = bounded(input.actionsWidth)
        let statusWidth = bounded(input.statusWidth)

        let hasName = nameWidth > 0
        let hasTabs = tabsWidth > 0
        let hasActions = actionsWidth > 0
        let hasStatus = statusWidth > 0
        let hasSearch = input.hasSearch

        let start = nameStart(buttons: input.buttons)
        let centre = windowWidth / 2 - cardMinX

        // The trailing chain, right to left. `end` is where the search ends.
        let statusMinX = width - statusTrailing - statusWidth
        let end = hasStatus ? statusMinX - zoneGap : width - trailing

        /// The furthest right the tabs (or the name, with no tabs) may end
        /// when the search is `search` wide.
        func limit(search: CGFloat) -> CGFloat {
            var cursor = end
            if hasSearch { cursor -= search + (hasActions ? actionsToSearch : zoneGap) }
            if hasActions { cursor -= actionsWidth + zoneGap }
            return cursor
        }

        let resting = hasSearch && input.alwaysCollapseSearch && !input.searchInUse
        let leastSearch = resting ? magnifierWidth : searchFloor
        let nameEnd = start + nameWidth
        let tabsStart = nameEnd + (hasName ? nameGap : 0)

        func fits(tabs: CGFloat, search: CGFloat) -> Bool {
            hasTabs ? tabsStart + tabs <= limit(search: search) : nameEnd <= limit(search: search)
        }

        // The ladder: tabs fold first, then the search.
        var tabsFolded = false
        var searchFolded = resting
        var tabs = tabsWidth
        if !fits(tabs: tabs, search: hasSearch ? leastSearch : 0) {
            if hasTabs, foldedWidth > 0, foldedWidth < tabsWidth {
                tabsFolded = true
                tabs = foldedWidth
            }
            if !fits(tabs: tabs, search: hasSearch ? leastSearch : 0),
               hasSearch, !resting, !input.searchInUse {
                searchFolded = true
            }
        }

        // The search's width: the magnifier when folded, else what the tabs leave it, between the floor and the full field.
        var search = magnifierWidth
        if hasSearch, !searchFolded {
            let claimed = hasActions ? actionsToSearch + actionsWidth + zoneGap : zoneGap
            let need = hasTabs ? max(centre + tabs / 2, tabsStart + tabs) : nameEnd
            // Not-a-number cannot reach this clamp, every term is bounded above; the helper asks for an answer and the full field is it.
            search = (end - claimed - need).clamped(to: searchFloor...searchWidth, whenNotANumber: searchWidth)
        }
        let right = limit(search: search)

        // The name truncates last and alone.
        // Bounded terms again, so the fallback is never read; 0 is the name with no room.
        let shown = (right - (hasTabs ? tabs + nameGap : 0) - start)
            .clamped(to: 0...nameWidth, whenNotANumber: 0)
        let tabsMinX = start + shown + (shown > 0 ? nameGap : 0)
        let tabsX = min(max(centre - tabs / 2, tabsMinX), right - tabs)

        // The chain's frames.
        var cursor = end
        var searchFrame = CGRect.zero
        if hasSearch {
            searchFrame = row(x: cursor - search, width: search)
            cursor = searchFrame.minX - (hasActions ? actionsToSearch : zoneGap)
        }
        let actionsFrame = hasActions ? row(x: cursor - actionsWidth, width: actionsWidth) : .zero

        return Frames(
            name: hasName ? row(x: start, width: shown) : .zero,
            tabs: hasTabs ? row(x: tabsX, width: tabs) : .zero,
            actions: actionsFrame,
            search: searchFrame,
            status: hasStatus ? row(x: statusMinX, width: statusWidth) : .zero,
            tabsFolded: tabsFolded,
            searchFolded: searchFolded,
            fits: hasTabs ? right - tabs >= tabsMinX : start + shown <= right)
    }

    // MARK: - helpers

    private nonisolated static func bounded(_ value: CGFloat) -> CGFloat {
        value.clamped(to: 0...widest, whenNotANumber: 0)
    }

    private nonisolated static func row(x: CGFloat, width: CGFloat) -> CGRect {
        CGRect(x: x, y: controlTop, width: width, height: controlHeight)
    }

    /// Where the name starts: `leading`, or `obstacleClearance` right of the
    /// buttons when they end further right. A rect that is not a place is no
    /// obstacle, and its row does not matter.
    private nonisolated static func nameStart(buttons: CGRect) -> CGFloat {
        let edges = buttons.standardized
        let isPlace = !buttons.isNull && !buttons.isInfinite
            && buttons.origin.x.isFinite && buttons.size.width.isFinite
            && edges.maxX.isFinite && edges.width > 0 && edges.height > 0
        guard isPlace else { return leading }
        // maxX is finite by the guard above; the fallback is never read.
        let maxX = edges.maxX.clamped(to: -widest...widest, whenNotANumber: 0)
        return max(leading, maxX + obstacleClearance)
    }
}
