import AppKit
import SwiftUI

/// **How a switcher in the settings window's toolbar labels its segments.**
///
/// All four were drawn side by side in the mockup (2026-09-17) and the owner
/// took all four, as a choice made by right-clicking the toolbar (the bar's
/// own menu, `ShellBarMenu.items`, under "Tab labels"):
///
/// - `text` — each segment as wide as its word, a hairline between two
///   unselected ones. The system segmented control split the capsule into
///   equal shares of the longest word: 4 × 122 pt for Homebrew in Russian,
///   with «Поиск» sitting in a field three times its own width.
/// - `icons` — a glyph per segment, 40 pt each, the word in the tooltip.
/// - `iconsAndText` — a glyph beside each word.
///
/// A fourth was drawn and lived in for a day — glyphs, with the selected
/// segment carrying its word — and cut on 2026-09-18. Its stored value,
/// `iconsNamingSelected`, is not a case any more and reads back as `text`,
/// which `init(stored:)` already answers for anything it does not know.
public enum ToolbarSwitcherStyle: String, CaseIterable, Sendable {
    case text, icons, iconsAndText

    public static let storageKey = "toolbarSwitcherStyle"

    /// Anything unknown, including nothing stored, is `text` — the mockup's
    /// recommendation.
    public init(stored: String) {
        self = ToolbarSwitcherStyle(rawValue: stored) ?? .text
    }

    /// The words the choice is offered under — all three AppKit's own, read
    /// out of its `Toolbar.loctable`: the names every toolbar's context menu
    /// already uses for the same choice.
    public var label: String {
        switch self {
        case .text: return L("Text Only")
        case .icons: return L("Icon Only")
        case .iconsAndText: return L("Icon and Text")
        }
    }
}

public extension Notification.Name {
    static let helmToolbarSwitcherStyleChanged = Notification.Name("helmToolbarSwitcherStyleChanged")
}

public extension EnvironmentValues {
    @Entry var helmSwitcherStyle: ToolbarSwitcherStyle = .text
}

/// One segment: the value it selects, its word and its glyph.
public struct HelmSwitcherSegment<Value: Hashable> {
    public let value: Value
    public let label: String
    public let symbol: String
    /// A dot on the segment, and what it says (`HelmToolbarTab.needsAttention`).
    public let needsAttention: Bool
    public let attentionNote: String?

    public init(_ value: Value, _ label: String, symbol: String, needsAttention: Bool = false, attentionNote: String? = nil) {
        self.value = value
        self.label = label
        self.symbol = symbol
        self.needsAttention = needsAttention
        self.attentionNote = attentionNote
    }
}

/// **The switcher in the window's toolbar: the system's own segmented control,
/// sized to what it shows.**
///
/// It was drawn by hand for a while, to get segments as wide as their words and
/// a divider between them — and that cost everything the system control does
/// for free, which is most of what Liquid Glass *is*: measured 2026-09-17 against
/// Apple Music's toolbar, pressing a segment swells its glass and dragging
/// carries that glass from segment to segment. None of it can be imitated from
/// SwiftUI, and none of it was.
///
/// Under `HelmBarAppearance.flat` the control keeps its class and wears
/// `HelmFlatSegmentedCell`, which draws by hand again and asks for none of that
/// glass; whether AppKit still draws any of its own under it was not seen on a
/// screen (the cell's header).
///
/// What the system control had to be told: `segmentDistribution = .fit`, which
/// is what stops every segment taking the longest word's width — 4 × 122 pt for
/// Homebrew in Russian, «Поиск» in a field three times its size.
///
/// **A right-click here is the bar's, not this control's.** Four arrangements
/// were tried on the dev build for a menu of the switcher's own and each was
/// measured: SwiftUI's `.contextMenu` on a toolbar item opens nothing; a view
/// of ours answering `hitTest` never sees the press; a menu hung on the item's
/// own views loses to the toolbar's; and the control's own `menu` is never
/// consulted by a click either. So one local monitor, `SettingsToolbar`'s,
/// takes the gesture (`isTheGesture`) anywhere on the bar, this control
/// included, and opens the bar's one menu; this control's own monitor never
/// takes it, so no two menus can answer one click whatever order AppKit calls
/// the monitors in. What the control does keep is `menu`, set as its own
/// `NSView.menu` — the menu VoiceOver's "show menu" opens on a focused
/// control, where no click is involved.
public struct HelmToolbarSwitcher<Value: Hashable>: NSViewRepresentable {
    private let name: String
    private let segments: [HelmSwitcherSegment<Value>]
    @Binding private var selection: Value
    /// **Fold the whole strip into one segment — the current tab — with a
    /// menu for the rest**, rather than letting AppKit's own overflow move
    /// the strip into the toolbar's «»» menu the moment it stops fitting
    /// beside an opening search field. The same `NSSegmentedControl`
    /// instance carries both forms: `SettingsToolbar`'s fold state
    /// (`PageBar.tabsFolded`) is what flips this, and keeping one view
    /// identity across the flip is why — a torn-down-and-rebuilt control
    /// would re-pin its own toolbar metric (`hasPinnedMetric`'s own doc, one
    /// paragraph down) and lose the item AppKit had already inserted.
    /// `ShellBarTabs` mounts two switchers instead, one of each form, and never
    /// flips this on a mounted control: outside a toolbar there is no item to lose.
    private let compact: Bool
    /// The control's own `NSView.menu` — see this type's own header: the
    /// bar's menu for the centre tabs, nil for a switcher that belongs to
    /// something else (the actions capsule's, the measuring rig's).
    private let menu: NSMenu?
    /// **Which look the strip is drawn in — an input, not the environment's
    /// value.** `.liquidGlass` is the system's own cell and is what a caller
    /// that says nothing gets, so a control never asked for the flat look is
    /// never touched (`dress`); `.flat` swaps in `HelmFlatSegmentedCell`.
    private let appearance: HelmBarAppearance

    @Environment(\.helmSwitcherStyle) private var style
    @Environment(\.isEnabled) private var isEnabled

    public init(_ name: String, selection: Binding<Value>, segments: [HelmSwitcherSegment<Value>],
                compact: Bool = false, menu: NSMenu? = nil, appearance: HelmBarAppearance = .liquidGlass) {
        self.name = name
        self.segments = segments
        self._selection = selection
        self.compact = compact
        self.menu = menu
        self.appearance = appearance
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    /// **What the control actually shows.** One segment — the current
    /// selection — when `compact`, all of them otherwise; an empty
    /// `segments` or a selection none of them names (`fill` below
    /// has to answer every index safely regardless) folds to no
    /// segment at all rather than trapping.
    private var displaySegments: [HelmSwitcherSegment<Value>] {
        guard compact else { return segments }
        guard let index = segments.firstIndex(where: { $0.value == selection }) else { return [] }
        return [segments[index]]
    }

    /// The selection's index *within `displaySegments`* — always `0` when
    /// compact and there is anything to show, since the one segment shown is
    /// always the selected one.
    private var displaySelectedIndex: Int? {
        compact ? (displaySegments.isEmpty ? nil : 0) : segments.firstIndex { $0.value == selection }
    }

    public func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentStyle = .automatic
        control.segmentDistribution = .fit
        control.trackingMode = .selectOne
        control.target = context.coordinator
        control.action = #selector(Coordinator.picked(_:))
        context.coordinator.watch(control)
        Self.dress(control, as: appearance, coordinator: context.coordinator)
        context.coordinator.lastAppearance = appearance
        Self.fill(control, segments: displaySegments, style: style,
                  selected: displaySelectedIndex, compact: compact)
        context.coordinator.lastStyle = style
        context.coordinator.lastCompact = compact
        context.coordinator.lastNames = displaySegments.map(\.label)
        context.coordinator.lastSymbols = displaySegments.map(\.symbol)
        context.coordinator.lastAttention = displaySegments.map(\.needsAttention)
        return control
    }

    public static func dismantleNSView(_ control: NSSegmentedControl, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// **The gesture that opens a menu on a Mac**: the right button, or the left
    /// one with Control held, which is how a trackpad without a right click
    /// sends it. Its one caller is in this file.
    static func isTheGesture(type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch type {
        case .rightMouseDown: return true
        case .leftMouseDown: return modifiers.contains(.control)
        default: return false
        }
    }

    public func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.pick = { index in
            guard segments.indices.contains(index) else { return }
            selection = segments[index].value
        }
        context.coordinator.compact = compact

        // A look that changed swaps the cell here, before `isInitial` below
        // is read: the swap empties the control, which is what sends this
        // update down the structural branch to refill it.
        if context.coordinator.lastAppearance != appearance {
            Self.dress(control, as: appearance, coordinator: context.coordinator)
            context.coordinator.lastAppearance = appearance
        }

        // **The metric the bar will promote it to, taken before the first
        // measurement is made in the old one.** AppKit promotes the control as
        // the toolbar inserts it in its item viewer and asks SwiftUI nothing,
        // so an unpinned control answers its first `sizeThatFits` at
        // `.regular` and every later one at `.extraLarge`, and the frame is
        // set twice.
        //
        // Filling the segments in `makeNSView` does not settle this — it
        // decides *what* is measured, not in which metric. Measured
        // 2026-09-20 against that pre-population, three placements, same
        // harness, with a print of the frame log added to that file's `mount`
        // and one placement per run of
        //
        //   bash Scripts/test.sh --filter TheToolbarSwitcherIsLaidOutOnceInTheBarsMetricTests
        //
        // With no pin at all, and with the pin written in `makeNSView`,
        // `TheToolbarSwitcherIsLaidOutOnceInTheBarsMetricTests` read
        // (252.0, 24.0) laid out against (272.0, 36.0) settled over two
        // frames — the same numbers either way, so a metric written in
        // `makeNSView` does not survive to the first measurement. Written
        // here, the same run reads one frame, (272.0, 36.0), and that file
        // passes; the `makeNSView` half of this was re-run twice on
        // 2026-09-20 and went red at those two sizes both times. What
        // overwrites it in between was not established; that it is
        // overwritten was.
        //
        // Written here and not in `fill`, which every attached-control path
        // already shares (`makeNSView` and this method's own calls below —
        // `command grep -n 'Self[.]fill(' Sources/HelmUI/DesignSystem/HelmToolbarSwitcher.swift`
        // lists them) — a control-size decision is not what `fill` exists to
        // make (what its body writes: each segment's label, image, tooltip,
        // width and menu indicator, and the selection), and conflating the
        // two would tie every future
        // caller of `fill` to this one metric. Written once rather than on
        // every pass, on a flag of its own and not on the fill gating below:
        // the bar decides its own metric, and a writer that ran every time
        // would fight a promotion to any other size rather than anticipate
        // this one.
        //
        // **That holds for a control whose cell was never swapped.** `dress`
        // writes `.extraLarge` itself after every swap, because a swap
        // resets the control to `.regular` (measured on a bare control:
        // segments gone, target nil, size regular), and the flat cell's
        // height does not read the metric. Not measured: a flat control
        // inside a toolbar — whether the bar still promotes a control whose
        // cell was swapped, and whether `dress`'s write fights that promotion.
        if !context.coordinator.hasPinnedMetric {
            context.coordinator.hasPinnedMetric = true
            control.controlSize = .extraLarge
        }

        let shown = displaySegments
        let selectedIndex = displaySelectedIndex
        let isInitial = control.segmentCount == 0
        let styleChanged = context.coordinator.lastStyle != style
        let countChanged = control.segmentCount != shown.count
        // A fold or an unfold always changes `shown.count` too (`N` down to
        // `1` or back), so it already takes the structural branch below —
        // this flag exists only so that branch is *entered* on a compact
        // flip whose count happens not to move (a single-tab page, or the
        // theoretical case of two segments folding to the same count some
        // other way), not because the branch needs telling apart from a
        // count change once inside it.
        let compactChanged = context.coordinator.lastCompact != compact

        if isInitial || countChanged || styleChanged || compactChanged {
            // Animate only when changing style on an existing populated
            // control, never on initial population and never on a fold or
            // unfold — `TheSwitcherFoldsToOneSegmentTests` requires the
            // intrinsic width to change in the same update, and animating a
            // fold or an unfold is exactly the per-segment slide the owner
            // reported as text still moving in the tabs.
            let shouldAnimate = !isInitial && !countChanged && !compactChanged && !HelmMotion.reduceMotion
            if shouldAnimate {
                NSAnimationContext.runAnimationGroup { animation in
                    // `interface`'s length, taken from the token rather than
                    // written again here: AppKit wants seconds and has nowhere
                    // to put an `Animation`, and the reduce-motion branch this
                    // number cannot carry is the `shouldAnimate` guard above.
                    animation.duration = HelmMotion.interfaceDuration
                    animation.allowsImplicitAnimation = true
                    Self.fill(control, segments: shown, style: style, selected: selectedIndex, compact: compact)
                    control.layoutSubtreeIfNeeded()
                }
            } else {
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.allowsImplicitAnimation = false
                Self.fill(control, segments: shown, style: style, selected: selectedIndex, compact: compact)
                control.layoutSubtreeIfNeeded()
                NSAnimationContext.endGrouping()
            }
            // **Every fill that ran invalidates the intrinsic size in the
            // same update.** Measured against leaving this out: the width
            // SwiftUI asks for (`sizeThatFits`, below) lagged by one update
            // in both directions — a fold showed the full width for one more
            // frame, and an unfold showed the folded width for one.
            control.invalidateIntrinsicContentSize()
            context.coordinator.lastStyle = style
            context.coordinator.lastCompact = compact
            context.coordinator.lastNames = shown.map(\.label)
            context.coordinator.lastSymbols = shown.map(\.symbol)
            context.coordinator.lastAttention = shown.map(\.needsAttention)
        } else {
            var labelsMatch = true
            let showsWord = style == .text || style == .iconsAndText
            for (idx, seg) in shown.enumerated() {
                if control.label(forSegment: idx) != (showsWord ? seg.label : "") {
                    labelsMatch = false
                    break
                }
            }
            // **A glyph-only segment draws no word, so `labelsMatch` above
            // reads the same empty string before and after a name changes —
            // it can only see the drawn word, and a glyph style draws none.**
            // The name still has to reach the tooltip and the glyph's
            // accessibility description (`fill`'s own `setToolTip` and
            // `NSImage(... accessibilityDescription:)`), which is what a
            // language change moves without moving `shown.count`, the style
            // or the selection: `AGlyphSwitcherFollowsALanguageChangeTests`
            // read the old English word back from both after switching to
            // Russian, on this exact bug. `lastNames` tracks the segments'
            // own names regardless of what style draws them, so a changed
            // name forces a fill even while `labelsMatch` alone would not.
            let namesChanged = context.coordinator.lastNames != shown.map(\.label)
            // **A glyph is drawn, not read back — `control.image(forSegment:)`
            // is the same `NSImage` whichever symbol produced it, so nothing
            // here can compare the control's own state against a changed
            // `symbol` the way `labelsMatch` compares the drawn word.** The
            // capsule's `.segmented` entries are always `.icons`
            // (`ASegmentedActionIsAlwaysGlyphsTests`), the one style where a
            // glyph is *all* that is drawn, so a page that re-declares an
            // option's glyph under the same name and the same selection has
            // nothing else here to force a refill on:
            // `AGlyphSwitcherRedrawsAChangedGlyphTests` read the old glyphs
            // still drawn after such a re-declare, on this exact gap.
            // `lastSymbols` tracks the segments' own glyphs the same way
            // `lastNames` tracks their words.
            let symbolsChanged = context.coordinator.lastSymbols != shown.map(\.symbol)
            // **A dot is an image, and an image cannot be read back** (`symbolsChanged`'s own reason), so what was
            // drawn is kept and compared.
            let attentionChanged = context.coordinator.lastAttention != shown.map(\.needsAttention)
            let selectionMoved = selectedIndex.map { control.selectedSegment != $0 } ?? (control.selectedSegment != -1)
            // Nothing structural changed, so this is the cheap path: when the
            // words and the selection both already read right — the first
            // update after `makeNSView` pre-populated the control, which is
            // the case this whole gating exists for — no fill and no layout
            // pass happen at all.
            //
            // A moved selection is applied *through* `fill` rather than by a
            // `setSelected` of its own. `fill` is idempotent for everything
            // else it writes — the style cannot have changed in this branch,
            // so the labels, images and widths it rewrites are the values
            // already there — and it carries the single bounded
            // `setSelected(forSegment:)` in this file.
            // `TheSwitcherRefusesASegmentThatIsNotThereTests` counts that call
            // and requires the one occurrence to sit inside `fill`'s body,
            // because AppKit raises `NSRangeException` on an index the control
            // does not have; a second call site is a second way to abort the
            // app for whichever caller passes an index of its own next.
            // Measured 2026-09-20: with a second `setSelected` here that file
            // read "calls setSelected( 2 time(s)" and went red.
            if !labelsMatch || selectionMoved || namesChanged || symbolsChanged || attentionChanged {
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.allowsImplicitAnimation = false
                Self.fill(control, segments: shown, style: style, selected: selectedIndex, compact: compact)
                control.layoutSubtreeIfNeeded()
                NSAnimationContext.endGrouping()
                control.invalidateIntrinsicContentSize()
                context.coordinator.lastNames = shown.map(\.label)
                context.coordinator.lastSymbols = shown.map(\.symbol)
                context.coordinator.lastAttention = shown.map(\.needsAttention)
            }
        }

        control.isEnabled = isEnabled
        control.setAccessibilityLabel(name)
        control.menu = menu

        // **The compact form's own menu** — built fresh on every update from
        // the *full* segment list, never `shown`, so a folded capsule always
        // offers every tab and not only the one it is currently drawing.
        // `nil` when not compact, so `took(_:)` and `picked(_:)` below can
        // both read "is there a menu at all" as "is this control compact"
        // with nothing else to ask.
        context.coordinator.tabsMenu = compact
            ? Self.tabsMenu(segments: segments, selected: segments.firstIndex { $0.value == selection },
                            target: context.coordinator)
            : nil
    }

    /// **The size SwiftUI lays the item out at.** Asked for the control's own
    /// fitting size on every pass, so a width that changes — the style chosen
    /// for the bar puts words on the segments or takes them off — is a size
    /// SwiftUI can move between rather than a number it is handed once.
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl,
                             context: Context) -> CGSize? {
        nsView.fittingSize
    }

    /// **The one place the cell is chosen, and the one place in `Sources` whose
    /// code names `HelmFlatSegmentedCell`.** `.flat` installs it when the
    /// control does not wear it; `.liquidGlass` installs the system's
    /// `NSSegmentedCell` only when the control wears the flat one, so a control never dressed
    /// flat is not touched at all. A cell swap wipes what the control held
    /// (measured on a bare control: segment count 0, target nil, size
    /// regular), so everything `makeNSView` writes is written again here and
    /// the caller refills the segments. Nobody has seen the flat cell drawn in
    /// a window.
    private static func dress(_ control: NSSegmentedControl, as appearance: HelmBarAppearance,
                              coordinator: Coordinator) {
        switch appearance {
        case .flat:
            guard !(control.cell is HelmFlatSegmentedCell) else { return }
            control.cell = HelmFlatSegmentedCell()
        case .liquidGlass:
            guard control.cell is HelmFlatSegmentedCell else { return }
            control.cell = NSSegmentedCell()
        }
        control.segmentStyle = .automatic
        control.segmentDistribution = .fit
        control.trackingMode = .selectOne
        control.target = coordinator
        control.action = #selector(Coordinator.picked(_:))
        control.controlSize = .extraLarge
    }

    /// The segments as the chosen style shows them — each segment's word,
    /// glyph, tooltip, width and menu indicator, and the selection. Written
    /// once by `makeNSView`, then by `updateNSView` only on an update that
    /// moved something written here: the count, the style or the fold, or,
    /// on that method's cheap path, a drawn word, a name, a glyph or the
    /// selection that no longer matches the control.
    private static func fill(_ control: NSSegmentedControl,
                             segments: [HelmSwitcherSegment<Value>],
                             style: ToolbarSwitcherStyle, selected: Int?, compact: Bool) {
        if control.segmentCount != segments.count { control.segmentCount = segments.count }
        for (index, segment) in segments.enumerated() {
            let showsGlyph = style != .text
            let showsWord = style == .text || style == .iconsAndText
            control.setLabel(showsWord ? segment.label : "", forSegment: index)
            control.setImage(image(for: segment, showsGlyph: showsGlyph), forSegment: index)
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
            // The word, for a segment showing only its glyph — the pointer is
            // where a glyph-only control says what it is.
            control.setToolTip(segment.label, forSegment: index)
            // 0 is «as wide as it needs», which `segmentDistribution` then
            // leaves alone.
            control.setWidth(0, forSegment: index)
            // Written on every fill, compact or not, so no indicator ever
            // survives an unfold — a full-width segment carrying a menu
            // arrow from its last compact appearance was never asked for.
            control.setShowsMenuIndicator(compact, forSegment: index)
        }
        // An index naming no segment — out of range on either side, which an
        // empty `segments` makes true of every index including `0` — is simply
        // not applied: AppKit's own `forSegment:` traps on it rather than
        // refusing, so the bound has to sit here, where both callers' indices
        // are checked against the count that was just written above, and not
        // repeated at each call site.
        if let selected, segments.indices.contains(selected), control.selectedSegment != selected {
            control.setSelected(true, forSegment: selected)
        }
        // No index at all clears the selection: a press AppKit has already lit must not stay lit when the
        // selection names no segment. Through `selectedSegment`, not a second `setSelected(`, which
        // `TheSwitcherRefusesASegmentThatIsNotThereTests` counts.
        if selected == nil, control.selectedSegment != -1 { control.selectedSegment = -1 }
    }

    /// **The segment's image, and the dot in it.** AppKit draws a segment's label and its image together and puts the
    /// image *before* the label (measured 2026-10-03 on a bare three-segment control in an offscreen window: a 6 pt
    /// image on the third text segment drew, red pixels found left of the word, and the strip's fitting width went from
    /// 310 to 318 pt; `NSSegmentedControl` has no image-position property); so a text segment's whole image is the dot. Where the style draws a glyph the dot is drawn into the
    /// glyph's corner, since a segment has one image (the same drawing, run in the same offscreen way on an icon-only
    /// strip, put the dot at the glyph's upper right with the glyph still drawn). How the glass lens treats the dot on a real screen, selected or
    /// not, in the bar's metric, was not measured.
    private static func image(for segment: HelmSwitcherSegment<Value>, showsGlyph: Bool) -> NSImage? {
        let glyph = showsGlyph ? NSImage(systemSymbolName: segment.symbol, accessibilityDescription: segment.label) : nil
        guard segment.needsAttention else { return glyph }
        let dot: CGFloat = 6
        guard let glyph else { return attentionDot(dot, note: segment.attentionNote ?? segment.label) }
        let image = NSImage(size: glyph.size, flipped: false) { rect in
            glyph.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceIn)
            attentionDot(dot, note: nil).draw(in: NSRect(x: rect.maxX - dot, y: rect.maxY - dot, width: dot, height: dot))
            return true
        }
        image.accessibilityDescription = segment.attentionNote ?? segment.label
        return image
    }

    /// The warning ink as a round image, drawn each time it is shown so that it follows the appearance it lands in.
    private static func attentionDot(_ side: CGFloat, note: String?) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor(HelmSignal.warning).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = note
        return image
    }

    /// **The compact form's own menu**: every tab, full — never `displaySegments`
    /// — labelled and ticked, `representedObject` carrying the *full* index
    /// `pick(_:)` already expects. Built fresh in `updateNSView` rather than
    /// kept across updates: a language or selection change has nothing else
    /// that would invalidate a cached one.
    static func tabsMenu(segments: [HelmSwitcherSegment<Value>], selected: Int?,
                         target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: HelmA11y.whatToShow)
        // Not AppKit's own automatic enabling: every item here always acts,
        // so there is nothing to disable, but a menu action-only from the
        // representedObject (no explicit `isEnabled` written) is worth
        // stating outright rather than leaving to the default.
        menu.autoenablesItems = false
        for (index, segment) in segments.enumerated() {
            let item = NSMenuItem(title: segment.label,
                                  action: #selector(Coordinator.pickedFromMenu(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: segment.symbol, accessibilityDescription: segment.label)
            item.target = target
            item.representedObject = index
            item.isEnabled = true
            item.state = index == selected ? .on : .off
            // The folded strip shows one segment, so a dot on another tab is said here: in words when there is a note, else as «•».
            if segment.needsAttention { item.badge = NSMenuItemBadge(string: segment.attentionNote ?? "•") }
            menu.addItem(item)
        }
        return menu
    }

    @MainActor public final class Coordinator: NSObject {
        var pick: (Int) -> Void = { _ in }
        /// Non-nil exactly when the control is compact — the one thing
        /// `took(_:)` and `picked(_:)` both need to ask, since a plain click
        /// on a compact control is meant to raise this rather than fire
        /// `pick(_:)` with whatever `sender.selectedSegment` (always `0`)
        /// would otherwise mean.
        var tabsMenu: NSMenu?
        var compact = false
        var lastStyle: ToolbarSwitcherStyle?
        var lastAppearance: HelmBarAppearance?
        var lastCompact: Bool?
        /// The segments' own names as of the last fill — read regardless of
        /// `lastStyle`, because a glyph-only style draws none of them: the
        /// drawn word alone (what `updateNSView`'s cheap-path `labelsMatch`
        /// reads) cannot tell a language change apart from no change at all
        /// once the word on screen is always empty.
        var lastNames: [String]?
        /// The segments' own glyphs as of the last fill — `lastNames`'s twin
        /// for the one style that draws nothing else: `.icons` shows a symbol
        /// and no word, so a re-declare that swaps a glyph under an unchanged
        /// name and selection moves nothing `labelsMatch` or `namesChanged`
        /// can see (`AGlyphSwitcherRedrawsAChangedGlyphTests`).
        var lastSymbols: [String]?
        /// Which segments carried a dot as of the last fill, for the same reason.
        var lastAttention: [Bool]?
        /// Whether the bar's metric has been written onto the control yet.
        /// Its own flag rather than a reading of the fill gating above,
        /// because the two answer different questions: that one asks whether
        /// the segments need rewriting, this one whether the control has ever
        /// been given a size class. Under `SettingsToolbar`, folding to `compact` does not touch this
        /// at all — it is the same control, the same coordinator and the
        /// same pin, which is the whole reason the fold reuses this view
        /// rather than swapping in a different one (`compact`'s own doc, on
        /// the initialiser parameter, above): only a genuine
        /// `dismantleNSView` — the switcher's item itself being torn down and
        /// rebuilt — pins the metric a second time.
        var hasPinnedMetric = false
        private weak var control: NSSegmentedControl?
        private var monitor: Any?

        func watch(_ control: NSSegmentedControl) {
            self.control = control
            stop()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
                [weak self] event in
                // The handler is `@Sendable` and `NSEvent` is not, although this
                // one arrives on the main thread — which is where it is read and
                // where the menu is raised. `Press` carries it over that line,
                // and only a `Bool` comes back.
                let press = Press(event: event)
                return MainActor.assumeIsolated { self?.took(press) ?? false } ? nil : event
            }
        }

        /// Whether the tabs menu took the press — true only for a plain press
        /// while compact, which is then not passed on.
        private func took(_ press: Press) -> Bool {
            let event = press.event
            guard let control, let window = control.window, event.window === window
            else { return false }
            let point = control.convert(event.locationInWindow, from: nil)
            guard control.bounds.contains(point) else { return false }
            // **A plain press on a compact control raises the tabs menu
            // instead of picking a segment** — there is only ever one segment
            // to pick while compact, the current tab, so the ordinary click
            // would do nothing at all; this is what lets a person choose a
            // *different* tab from the folded capsule. **Never a Control-click**:
            // that is the menu gesture (`isTheGesture`), and it belongs to the
            // bar's own menu (this type's own header), which a tabs menu
            // raised here first would shadow.
            if compact, control.isEnabled, event.type == .leftMouseDown,
               !HelmToolbarSwitcher.isTheGesture(type: event.type, modifiers: event.modifierFlags),
               let tabsMenu {
                tabsMenu.popUp(positioning: tabsMenu.items.first { $0.state == .on }, at: point, in: control)
                return true
            }
            return false
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// **The keyboard and VoiceOver path** — `took(_:)` above already
        /// intercepts every ordinary mouse press on a compact control before
        /// AppKit's own click machinery fires this at all, so this branch is
        /// what a Space or Return key, or a VoiceOver activation, still
        /// reaches.
        @objc func picked(_ sender: NSSegmentedControl) {
            if compact, let tabsMenu {
                tabsMenu.popUp(positioning: tabsMenu.items.first { $0.state == .on }, at: .zero, in: sender)
                return
            }
            pick(sender.selectedSegment)
        }

        /// A choice from the compact form's own menu — `representedObject`
        /// carries the *full* index, the same index `pick(_:)` already
        /// expects from `picked(_:)`.
        @objc func pickedFromMenu(_ sender: NSMenuItem) {
            guard let index = sender.representedObject as? Int else { return }
            pick(index)
        }
    }
}

/// **The segmented cell of the flat look: no bezel, a capsule of
/// `HelmSurface.barPick` under the selected segment, the word in 13 pt
/// medium.** It reads each segment's label, image and menu indicator from the
/// control's own per-segment state, so what `fill` writes, the dot and the
/// refill rule stay one. `cellSize` is its own, so the control's fitting size
/// follows it (`TheSwitcherDrawsFlatOnlyWhereAskedTests` reads the height back
/// as `height` and the width as the picks plus the insets).
///
/// A disabled control draws its words and template glyphs in
/// `tertiaryLabelColor`, and the pick and a glyph that carries the attention dot
/// (a composite, not a template) at the strength that ink has against
/// `labelColor`: the alpha of the one over the alpha of the other, resolved when
/// drawn.
///
/// **Measured on 27.2:** a subclass's `drawSegment` is called through
/// `cacheDisplay`, windowless; and in a standalone bench app's window, key and
/// then not key, in the dark appearance, a cell that overrode only `drawSegment`
/// had its paint on screen, with the system's own selection capsule (accent
/// when key, grey when not) still drawn under the selected segment. This cell
/// also overrides `draw(withFrame:in:)` and never calls the system's.
/// **Not seen on a screen:** this cell itself — whether the system's
/// selection capsule shows under its pick, the exact widths, the pick's
/// geometry, the dot and the fold's arrow, and that a press lands on the
/// segment drawn there (the system's own hit-testing was not made to follow
/// `segmentWidth`).
final class HelmFlatSegmentedCell: NSSegmentedCell {
    /// The pick's height; the bar's own control is `height` high.
    static let pill: CGFloat = 32
    /// The space between the cell's edge and the pick, and between two segments.
    static let inset: CGFloat = HelmSpace.s1
    /// The space either side of a segment's content.
    static let sidePadding: CGFloat = 14
    static let height: CGFloat = pill + 2 * inset

    private static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    /// The longest side a glyph is drawn at.
    private static let glyphSide: CGFloat = 16
    /// The menu indicator's width and height, and its stroke.
    private static let arrow = NSSize(width: 8, height: 4)
    private static let arrowStroke: CGFloat = 1.5

    override var cellSize: NSSize {
        var width = 2 * Self.inset
        for index in 0..<segmentCount { width += segmentWidth(index) }
        width += Self.inset * CGFloat(max(segmentCount - 1, 0))
        return NSSize(width: width, height: Self.height)
    }

    private func attributes(selected: Bool) -> [NSAttributedString.Key: Any] {
        [.font: Self.font, .foregroundColor: ink(selected: selected)]
    }

    private func ink(selected: Bool) -> NSColor {
        guard isEnabled else { return .tertiaryLabelColor }
        return selected ? .labelColor : .secondaryLabelColor
    }

    /// What a disabled cell draws everything it does not ink at: the alpha of
    /// `tertiaryLabelColor` over the alpha of `labelColor`, both resolved in sRGB
    /// in the appearance being drawn in. 1 while enabled.
    private func strength() -> CGFloat {
        guard !isEnabled else { return 1 }
        var ratio: CGFloat = 1
        NSAppearance.currentDrawing().performAsCurrentDrawingAppearance {
            let label = NSColor.labelColor.usingColorSpace(.sRGB)?.alphaComponent ?? 0
            let tertiary = NSColor.tertiaryLabelColor.usingColorSpace(.sRGB)?.alphaComponent ?? 0
            if label > 0 { ratio = tertiary / label }
        }
        return ratio
    }

    private func glyphSize(_ image: NSImage) -> NSSize {
        let longest = max(image.size.width, image.size.height)
        guard longest > Self.glyphSide else { return image.size }
        let scale = Self.glyphSide / longest
        return NSSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    /// What one segment holds, left to right: the image, the word, the arrow.
    private func contentWidth(_ segment: Int) -> CGFloat {
        var parts: [CGFloat] = []
        if let image = image(forSegment: segment) { parts.append(glyphSize(image).width) }
        if let word = label(forSegment: segment), !word.isEmpty {
            parts.append(ceil((word as NSString).size(withAttributes: [.font: Self.font]).width))
        }
        if showsArrow(segment) { parts.append(Self.arrow.width) }
        return parts.reduce(0, +) + HelmSpace.s3 * CGFloat(max(parts.count - 1, 0))
    }

    /// The menu indicator is the control's own per-segment state; the cell has
    /// no reading of it.
    private func showsArrow(_ segment: Int) -> Bool {
        (controlView as? NSSegmentedControl)?.showsMenuIndicator(forSegment: segment) ?? false
    }

    /// A width set on the segment wins; 0 is as wide as the content.
    private func segmentWidth(_ segment: Int) -> CGFloat {
        let set = width(forSegment: segment)
        return set > 0 ? set : contentWidth(segment) + 2 * Self.sidePadding
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        var x = cellFrame.minX + Self.inset
        for index in 0..<segmentCount {
            let width = segmentWidth(index)
            drawSegment(index, inFrame: NSRect(x: x, y: cellFrame.minY, width: width, height: cellFrame.height),
                        with: controlView)
            x += width + Self.inset
        }
    }

    override func drawSegment(_ segment: Int, inFrame frame: NSRect, with controlView: NSView) {
        let selected = isSelected(forSegment: segment)
        if selected {
            let pick = frame.insetBy(dx: 0, dy: (frame.height - Self.pill) / 2)
            let fill = NSColor(HelmSurface.barPick).usingColorSpace(.sRGB) ?? NSColor(HelmSurface.barPick)
            fill.withAlphaComponent(fill.alphaComponent * strength()).setFill()
            NSBezierPath(roundedRect: pick, xRadius: pick.height / 2, yRadius: pick.height / 2).fill()
        }
        let ink = ink(selected: selected)
        var x = frame.minX + (frame.width - contentWidth(segment)) / 2
        if let image = image(forSegment: segment) {
            let size = glyphSize(image)
            let rect = NSRect(x: x, y: frame.midY - size.height / 2, width: size.width, height: size.height)
            let shown = image.isTemplate ? Self.tinted(image, with: ink) : image
            shown.draw(in: rect, from: .zero, operation: .sourceOver, fraction: image.isTemplate ? 1 : strength(),
                       respectFlipped: true, hints: nil)
            x += size.width + HelmSpace.s3
        }
        if let word = label(forSegment: segment), !word.isEmpty {
            let text = NSAttributedString(string: word, attributes: attributes(selected: selected))
            let size = text.size()
            text.draw(at: NSPoint(x: x, y: frame.midY - size.height / 2))
            x += ceil(size.width) + HelmSpace.s3
        }
        if showsArrow(segment) {
            let top = frame.midY - Self.arrow.height / 2
            // The arrow points down on screen, whichever way the view's y runs.
            let base = controlView.isFlipped ? top : top + Self.arrow.height
            let apex = controlView.isFlipped ? top + Self.arrow.height : top
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: base))
            path.line(to: NSPoint(x: x + Self.arrow.width / 2, y: apex))
            path.line(to: NSPoint(x: x + Self.arrow.width, y: base))
            path.lineWidth = Self.arrowStroke
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            ink.setStroke()
            path.stroke()
        }
    }

    /// A template glyph in the ink it is drawn with, resolved when drawn.
    private static func tinted(_ image: NSImage, with ink: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            ink.set()
            rect.fill(using: .sourceIn)
            return true
        }
    }
}

/// One press, over the line between a monitor's `@Sendable` handler and the
/// main actor it is already on.
private struct Press: @unchecked Sendable {
    let event: NSEvent
}
