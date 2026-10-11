import AppKit
import SwiftUI

/// **How a switcher in the settings window's toolbar labels its segments.**
///
/// All four were drawn side by side in the mockup (2026-09-17) and the owner
/// took all four, as a choice made by right-clicking the toolbar (the bar's
/// own menu, `ShellBarMenu.items`, under "Tab labels"):
///
/// - `text` — each segment as wide as its word.
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

/// **The switcher in the bar: an `NSSegmentedControl` wearing `HelmFlatSegmentedCell`,
/// sized to what it shows.**
///
/// Under both looks the strip is the same: the neutral pill of the flat cell.
/// The system's own cell was worn under Liquid Glass for a while, for the glass
/// it brings (measured 2026-09-17 against Apple Music's toolbar: pressing a
/// segment swells its glass and dragging carries that glass from segment to
/// segment), and in a key window it selected with the accent colour, which no
/// segmented control in the bar draws (`TheBarDrawsNoAccentInAKeyWindowTests`). The look changes the plate
/// under the strip (`HelmBarAppearance`), not the strip; the glass swell is
/// gone with the system's cell. Whether AppKit still draws any of its own under
/// the cell was not seen on a screen (the cell's header).
/// A press slides the pick from the old segment to the new one (`HelmFlatSegmentedCell.slide`); the page
/// under the bar still changes at once.
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
    /// beside an opening search field. One `NSSegmentedControl` instance can carry both forms:
    /// `updateNSView` refills the same control when this flips (`TheSwitcherFoldsToOneSegmentTests`).
    /// Nothing in `Sources` flips it on a mounted control: `ShellBarTabs` mounts two switchers, one of
    /// each form, and its plate holds whichever the layout says.
    private let compact: Bool
    /// The control's own `NSView.menu` — see this type's own header: the
    /// bar's menu for the centre tabs, nil for a switcher that belongs to
    /// something else (the actions capsule's, the measuring rig's).
    private let menu: NSMenu?
    @Environment(\.helmSwitcherStyle) private var style
    @Environment(\.isEnabled) private var isEnabled

    public init(_ name: String, selection: Binding<Value>, segments: [HelmSwitcherSegment<Value>],
                compact: Bool = false, menu: NSMenu? = nil, appearance: HelmBarAppearance = .liquidGlass) {
        // `appearance` is read by nothing here: both looks wear one cell (this type's header).
        self.name = name
        self.segments = segments
        self._selection = selection
        self.compact = compact
        self.menu = menu
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
        context.coordinator.watch(control)
        Self.dress(control, coordinator: context.coordinator)
        Self.fill(control, segments: displaySegments, style: style,
                  selected: displaySelectedIndex, compact: compact)
        context.coordinator.lastStyle = style
        context.coordinator.lastCompact = compact
        context.coordinator.lastNames = displaySegments.map(\.label)
        context.coordinator.lastSymbols = displaySegments.map(\.symbol)
        context.coordinator.lastAttention = displaySegments.map(\.needsAttention)
        context.coordinator.shownSelection = displaySelectedIndex
        return control
    }

    public static func dismantleNSView(_ control: NSSegmentedControl, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// **The gesture that opens a menu on a Mac**: the right button, or the left
    /// one with Control held, which is how a trackpad without a right click
    /// sends it. Public for `SettingsToolbar`'s own monitor, which is the one
    /// place the gesture is answered on the toolbar, so the two can never
    /// disagree about what it is; `ShellPageBar` reads no gesture, AppKit
    /// opens its view's `menu`.
    public static func isTheGesture(type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Bool {
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

        // **The bar's metric, written on every pass.** `dress` writes `.extraLarge` in `makeNSView`, and with this
        // write removed a mounted control read `.regular` all the same under `HelmFlatSegmentedCell`
        // (`TheFirstGlassSwitcherIsDrawnAtTheBarsSizeTests` and `TheSwitcherDrawsFlatUnderEveryLookTests` went red on
        // the control size); with the system's cell it read `.regular` after a single write here, and again once its
        // window became key. What resets it was not established under either cell. The cell's size does not read the
        // metric (`cellSize`), so this holds `controlSize`, which those two families read.
        if control.controlSize != .extraLarge { control.controlSize = .extraLarge }

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
        context.coordinator.shownSelection = selectedIndex

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

    /// **The place the cell is installed** (`fill` and the coordinator's `picked` reach it through `control.cell`, to end
    /// and to start a slide). A cell swap wipes what the control held (measured on a bare control: segment count 0, target nil, size regular),
    /// so the control's settings are written here, after the swap, and `makeNSView` fills the segments after it.
    /// Nobody has seen the flat cell drawn in a window.
    private static func dress(_ control: NSSegmentedControl, coordinator: Coordinator) {
        control.cell = HelmFlatSegmentedCell()
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
        // A refill is not a press: a slide in flight ends where the strip stands now.
        (control.cell as? HelmFlatSegmentedCell)?.cancelSlide()
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
    /// strip, put the dot at the glyph's upper right with the glyph still drawn). How the dot reads over the glass plate on a real screen was not measured.
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
        /// The index the control showed selected as of the last update or press: where a press's slide starts from.
        var shownSelection: Int?
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
            // The cell is asked to slide before the page's write is made (`TheSwitchersPickSlidesToAPressedSegmentTests`);
            // that its animation group has also returned by then is by reading, held by no row.
            let to = sender.selectedSegment
            (sender.cell as? HelmFlatSegmentedCell)?.slide(from: shownSelection, to: to)
            shownSelection = to
            pick(to)
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

/// **The bar's segmented cell, under both looks: no bezel, a capsule of
/// `HelmSurface.barPick` under the selected segment, the word in 13 pt
/// medium.** It reads each segment's label, image and menu indicator from the
/// control's own per-segment state, so what `fill` writes, the dot and the
/// refill rule stay one. `cellSize` is its own, so the control's fitting size
/// follows it (`TheSwitcherDrawsFlatUnderEveryLookTests` reads the height back
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
///
/// **A press slides the pick; nothing else does.** `slide(from:to:)` puts a temporary
/// view the pick's size over the old segment and moves it to the new one through
/// `NSAnimationContext` and the view's animator, for `HelmMotion.interfaceDuration` along
/// `HelmMotion.interfaceCurve`, while the cell draws everything but its own pick; the words
/// take their new inks at the start. Reduce Motion, a selection the page wrote and the first
/// draw leave the pick a cut. **A refill ends a slide in flight** (`cancelSlide`, called first
/// by `fill`), because a refill may change the segments' widths and with them the slide's
/// target; so a page whose answer to a press also renames a tab or moves its dot gets no
/// slide. The temporary view is removed by `finishSlide`, reached from the animation's
/// completion and from `cancelSlide`, or by the `slide` that takes it over; no row awaits the completion.
/// **Not seen on a screen:** the slide itself, and the moving pick passing over
/// the words (it is translucent, drawn above them, where the resting pick is
/// below).
final class HelmFlatSegmentedCell: NSSegmentedCell {
    /// One slide asked for: between which segments, and how long it takes.
    struct Slide: Equatable {
        let from: Int
        let to: Int
        let duration: TimeInterval
    }

    /// Whether the system asks for less motion; a seam so a row can force either answer.
    var reducesMotion: () -> Bool = { HelmMotion.reduceMotion }
    /// Told of each slide as it is begun, before its animation group opens.
    var onSlide: (Slide) -> Void = { _ in }
    /// The slide in flight, nil at rest.
    private(set) var sliding: Slide?
    private var pill: SlidingPill?
    /// Which slide a completion belongs to; a newer or a cancelled one makes it stale.
    private var generation = 0

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

    /// Where one segment stands in the cell's frame.
    private func segmentFrame(_ segment: Int, in cellFrame: NSRect) -> NSRect {
        var x = cellFrame.minX + Self.inset
        for index in 0..<segment { x += segmentWidth(index) + Self.inset }
        return NSRect(x: x, y: cellFrame.minY, width: segmentWidth(segment), height: cellFrame.height)
    }

    /// The pick inside a segment's frame: what `drawSegment` fills, and where a slide ends, and starts unless it takes another over (that one starts from the moving view's frame).
    private func pick(in segmentFrame: NSRect) -> NSRect {
        segmentFrame.insetBy(dx: 0, dy: (segmentFrame.height - Self.pill) / 2)
    }

    private func pickRect(_ segment: Int, in cellFrame: NSRect) -> NSRect {
        pick(in: segmentFrame(segment, in: cellFrame))
    }

    /// The pick's colour, resolved in the appearance it is read in.
    private func pickFill() -> NSColor {
        let fill = NSColor(HelmSurface.barPick).usingColorSpace(.sRGB) ?? NSColor(HelmSurface.barPick)
        return fill.withAlphaComponent(fill.alphaComponent * strength())
    }

    /// **Moves the pick from `from` to `to` for the length of the token, or does nothing** — no index shown before,
    /// the same segment, an index the control does not have, a disabled control, Reduce Motion and a cell with no
    /// control view leave it a cut. A slide already in flight is replaced by one that starts from the frame the
    /// moving pick holds (its presentation frame when it has one).
    func slide(from: Int?, to: Int) {
        guard let from, from != to, (0..<segmentCount).contains(from), (0..<segmentCount).contains(to),
              isEnabled, HelmMotion.travels(reduceMotion: reducesMotion()), let control = controlView
        else { return }
        let slide = Slide(from: from, to: to, duration: HelmMotion.interfaceDuration)
        onSlide(slide)

        let start = pill.map { $0.layer?.presentation()?.frame ?? $0.frame }
            ?? pickRect(from, in: control.bounds)
        pill?.removeFromSuperview()
        generation += 1
        let mine = generation
        let moving = SlidingPill(frame: start, fill: { [weak self] in self?.pickFill() ?? .clear })
        control.addSubview(moving)
        pill = moving
        sliding = slide
        control.needsDisplay = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = slide.duration
            context.timingFunction = HelmMotion.interfaceCurve
            moving.animator().frame = pickRect(to, in: control.bounds)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == mine else { return }
                self.finishSlide()
            }
        })
    }

    /// Ends a slide in flight at once; the pick is drawn by the cell again.
    func cancelSlide() {
        guard sliding != nil || pill != nil else { return }
        generation += 1
        finishSlide()
    }

    private func finishSlide() {
        sliding = nil
        // The control is redrawn with the cell's own pick before the temporary view is removed.
        controlView?.display()
        pill?.removeFromSuperview()
        pill = nil
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        for index in 0..<segmentCount {
            drawSegment(index, inFrame: segmentFrame(index, in: cellFrame), with: controlView)
        }
    }

    override func drawSegment(_ segment: Int, inFrame frame: NSRect, with controlView: NSView) {
        let selected = isSelected(forSegment: segment)
        if selected, sliding == nil {
            let pick = pick(in: frame)
            pickFill().setFill()
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

/// The pick while it travels: a view the pick's size, filled with the cell's own pick colour, which it asks for
/// again in `updateLayer`, under the view's effective appearance. It takes no click and says nothing
/// to accessibility.
private final class SlidingPill: NSView {
    private let fill: () -> NSColor

    init(frame: NSRect, fill: @escaping () -> NSColor) {
        self.fill = fill
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = HelmFlatSegmentedCell.pill / 2
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill().cgColor
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func isAccessibilityElement() -> Bool { false }
}

/// One press, over the line between a monitor's `@Sendable` handler and the
/// main actor it is already on.
private struct Press: @unchecked Sendable {
    let event: NSEvent
}
