import AppKit
import HelmUI
import SwiftUI

/// **The tabs zone of the page bar: one plate holding one of two always-mounted
/// switchers, the whole strip or the folded one, whichever `ShellBarLayout`
/// says.**
///
/// Both switchers are rooted from the same drawing on every change, and they differ
/// only in `compact`. Their natural widths are the fitting widths of the two hosts,
/// read when the shape of the drawing moves and not before; a fold is the plate
/// swapping which host it holds, so nothing asks SwiftUI for an update inside the
/// bar's layout pass. `apply` is the one writer of the fold.
///
/// **What the drawing holds, and what it leaves out.** `Drawn` is compared on every
/// `show` of a page that has tabs; an equal one re-roots and measures nothing. `isLive` and the activity flag are not in
/// it: the first would rebuild the strip on every frozen turn of a page, the second
/// is the plate's own. A press is `pick`, the one place a page's handler is called,
/// and it needs a live page whose tabs are enabled and hold the pressed tab; a press
/// it refuses, or whose binding reads back another tab, re-roots both hosts, because
/// AppKit has already moved the selected segment and the switcher puts it back only
/// on an update.
///
/// **Measured on 27.2 with views outside any window:** the fitting width of a host
/// that was never framed equals its control's once the host is laid out, and
/// `reroot` lays both out, since a host never laid out holds no control;
/// the folded host of a selection that names no tab holds a control with no
/// segments (`displaySegments`), so the zone answers 0 for it and the layout
/// never folds. **Not seen on a screen:** the fold as a person sees it,
/// a press on the strip through the bar, and keyboard focus across a fold.
@MainActor
final class ShellBarTabs: ShellBarZone {

    /// What the zone draws. Equal to the last one: nothing is re-rooted, nothing is measured.
    struct Drawn: Equatable {
        /// What a width was measured under: the fields that can move a width, and the look, which moves none since both looks wear one cell and is measured again all the same.
        struct Shape: Equatable {
            var titles: [String]
            var symbols: [String]
            var attention: [Bool]
            var style: ToolbarSwitcherStyle
            var selectedID: String?
            var appearance: HelmBarAppearance
        }
        var shape: Shape
        /// The values the segments select; they draw nothing.
        var ids: [String]
        /// The accessibility description of a dot and the folded menu's badge.
        var notes: [String?]
        var name: String
        var isDisabled: Bool
        var menu: ObjectIdentifier?
    }

    /// The menu of the bar, handed to both switchers as their own `NSView.menu`. `SettingsWindow` sets it to the
    /// bar view's menu; a change shows the last state again.
    var barMenu: NSMenu? {
        didSet {
            guard barMenu !== oldValue, let shown else { return }
            show(shown)
        }
    }

    private(set) var view: NSView?
    /// Stored and never called: every width changes inside a `show`, and the controller collects after each.
    var measuresMoved: (() -> Void)?

    private var drawn: Drawn?
    /// 0 while the page has no tabs.
    private var fullWidth: CGFloat = 0
    /// 0 while the page has no tabs or the selection names no tab.
    private var foldedWidth: CGFloat = 0
    private(set) var isFolded = false
    /// Times both widths were read.
    private(set) var measureCount = 0
    /// Times the two hosts were given a root.
    private(set) var redrawCount = 0

    private let plate: ShellBarPlate
    private let full = NSHostingView.inBar(rootView: ShellBarTabsRoot(compact: false))
    private let folded = NSHostingView.inBar(rootView: ShellBarTabsRoot(compact: true))
    private let labelStyle: @MainActor () -> ToolbarSwitcherStyle
    /// Replaced on every show, before any guard: the binding reads it at call time.
    private var shown: ShellBarZoneState?

    /// `labelStyle` is read once per show; a test hands in its own.
    init(titlebarIsTransparent: Bool,
         labelStyle: @escaping @MainActor () -> ToolbarSwitcherStyle = { AppSettings.toolbarSwitcherStyle }) {
        self.labelStyle = labelStyle
        plate = ShellBarPlate(appearance: .flat, isActive: true, titlebarIsTransparent: titlebarIsTransparent)
    }

    func show(_ state: ShellBarZoneState) {
        shown = state
        guard let content = state.content, !content.tabs.isEmpty else {
            view = nil
            fullWidth = 0
            foldedWidth = 0
            drawn = nil
            return
        }
        plate.barAppearance = state.appearance
        plate.isActive = state.appearsActive

        let tabs = content.tabs
        let selectedID = content.selectedTab?.wrappedValue
        let next = Drawn(
            shape: Drawn.Shape(titles: tabs.map(\.title), symbols: tabs.map(\.symbol),
                               attention: tabs.map(\.needsAttention), style: labelStyle(),
                               selectedID: selectedID, appearance: state.appearance),
            ids: tabs.map(\.id), notes: tabs.map(\.attentionNote), name: HelmA11y.whatToShow,
            isDisabled: state.isDimmed || !content.tabsEnabled, menu: barMenu.map(ObjectIdentifier.init))
        if next == drawn {
            view = plate
            return
        }
        let measured = next.shape != drawn?.shape
        drawn = next
        reroot()
        if measured {
            fullWidth = full.fittingSize.width
            foldedWidth = selectedID.map { id in tabs.contains { $0.id == id } } == true
                ? folded.fittingSize.width : 0
            measureCount += 1
        }
        plate.content = isFolded ? folded : full
        view = plate
    }

    func measure(into measures: inout ShellPageBarView.Measures) {
        measures.tabs = fullWidth
        measures.tabsFolded = foldedWidth
    }

    func apply(_ verdicts: ShellPageBarView.Verdicts) {
        guard verdicts.tabsFolded != isFolded else { return }
        isFolded = verdicts.tabsFolded
        plate.content = isFolded ? folded : full
    }

    /// The one place a page's handler is called.
    private func pick(_ id: String) {
        guard let shown, shown.isLive, let content = shown.content, content.tabsEnabled,
              content.tabs.contains(where: { $0.id == id }),
              let selected = content.selectedTab else {
            refuse()
            return
        }
        selected.wrappedValue = id
        if selected.wrappedValue != id { refuse() }
    }

    private func refuse() {
        reroot()
    }

    private func reroot() {
        redrawCount += 1
        full.rootView = root(compact: false)
        folded.rootView = root(compact: true)
        // A host makes its control when it is laid out, and nothing else lays out a host that is in no window.
        full.layoutSubtreeIfNeeded()
        folded.layoutSubtreeIfNeeded()
    }

    private func root(compact: Bool) -> ShellBarTabsRoot {
        guard let drawn, let tabs = shown?.content?.tabs else { return ShellBarTabsRoot(compact: compact) }
        let segments = tabs.indices.map { index in
            HelmSwitcherSegment(drawn.ids[index], drawn.shape.titles[index], symbol: drawn.shape.symbols[index],
                                needsAttention: drawn.shape.attention[index], attentionNote: drawn.notes[index])
        }
        let selection = Binding<String>(
            get: { [weak self] in self?.shown?.content?.selectedTab?.wrappedValue ?? "" },
            set: { [weak self] in self?.pick($0) })
        return ShellBarTabsRoot(segments: segments, name: drawn.name, selection: selection, compact: compact,
                                menu: barMenu, appearance: drawn.shape.appearance, style: drawn.shape.style,
                                isDisabled: drawn.isDisabled)
    }
}

/// The root of each host. Not Equatable: it carries a binding of closures.
private struct ShellBarTabsRoot: View {
    var segments: [HelmSwitcherSegment<String>] = []
    var name = ""
    var selection: Binding<String> = .constant("")
    var compact: Bool
    var menu: NSMenu?
    var appearance: HelmBarAppearance = .flat
    var style: ToolbarSwitcherStyle = .text
    var isDisabled = false

    var body: some View {
        HelmToolbarSwitcher(name, selection: selection, segments: segments, compact: compact, menu: menu,
                            appearance: appearance)
            .environment(\.helmSwitcherStyle, style)
            .disabled(isDisabled)
    }
}
