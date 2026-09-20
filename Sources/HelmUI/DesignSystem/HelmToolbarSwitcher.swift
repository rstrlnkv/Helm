import AppKit
import SwiftUI

/// **How a switcher in the settings window's toolbar labels its segments.**
///
/// All four were drawn side by side in the mockup (2026-09-17) and the owner
/// took all four, as a choice made by right-clicking the switcher:
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

    /// The words the choice is offered under. Three are AppKit's own, read out
    /// of its `Toolbar.loctable` — the names every toolbar's context menu
    /// already uses for the same choice; the fourth has no system spelling.
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

/// Where a right-click on a switcher writes the choice.
///
/// A named type rather than a closure because the `@Entry` macro warns on a
/// closure-typed entry — "Storing a closure in `@Entry var
/// helmSetSwitcherStyle` may invalidate dependents on every update because
/// closures may not be comparable" — and a nominal type silences it. That is
/// the whole of what is measured here: the warning is gone from
/// `swift build` after this change and was present before it.
///
/// `AppSettings.ToolbarSwitcherStyleSetter`, the one conforming type and the
/// place the choice is actually stored from, has no stored properties, so it
/// is the same value on every evaluation, where a closure literal carries a
/// fresh context each time. Whether a switcher below is invalidated any less
/// often is unmeasured — nobody has counted, in either direction — and
/// nothing here should be read as saying that it is or that it is not.
@MainActor
public protocol SwitcherStyleSetter: Sendable {
    func callAsFunction(_ style: ToolbarSwitcherStyle)
}

public extension EnvironmentValues {
    @Entry var helmSwitcherStyle: ToolbarSwitcherStyle = .text
    /// Nil where nothing stores it — a page mounted on its own — and the menu
    /// is then not raised.
    @Entry var helmSetSwitcherStyle: SwitcherStyleSetter?
}

public extension View {
    /// Follows `ToolbarSwitcherStyle` as it is changed and hands every switcher
    /// below the way to change it — a right-click on the switcher, which is the
    /// gesture Finder's own display-mode menu teaches.
    func helmTracksSwitcherStyle(_ current: @escaping () -> ToolbarSwitcherStyle,
                                 set: SwitcherStyleSetter) -> some View {
        modifier(SwitcherStyleTracker(current: current, set: set))
    }
}

private struct SwitcherStyleTracker: ViewModifier {
    let current: () -> ToolbarSwitcherStyle
    let set: SwitcherStyleSetter
    @State private var style: ToolbarSwitcherStyle?

    func body(content: Content) -> some View {
        content
            .environment(\.helmSwitcherStyle, style ?? current())
            .environment(\.helmSetSwitcherStyle, set)
            // **No new identity here, unlike `PageBarStyle`'s tracker.** That one
            // adds and removes a toolbar item, which the bridge republishes only
            // for a subtree it has not seen. This style changes nothing about
            // which items exist: the switcher is one `NSView` that lives across
            // the change and rewrites its own segments, so a rebuild would only
            // throw that view away — measured 2026-09-18, which is what made the
            // bar's items jump as the style was chosen.
            .onReceive(NotificationCenter.default.publisher(for: .helmToolbarSwitcherStyleChanged)) { _ in
                style = current()
            }
    }
}

/// One segment: the value it selects, its word and its glyph.
public struct HelmSwitcherSegment<Value: Hashable> {
    public let value: Value
    public let label: String
    public let symbol: String

    public init(_ value: Value, _ label: String, symbol: String) {
        self.value = value
        self.label = label
        self.symbol = symbol
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
/// What the system control had to be told: `segmentDistribution = .fit`, which
/// is what stops every segment taking the longest word's width — 4 × 122 pt for
/// Homebrew in Russian, «Поиск» in a field three times its size.
///
/// **The right-click is caught before AppKit answers it.** Four arrangements
/// were tried on the dev build and each was measured: SwiftUI's `.contextMenu`
/// on a toolbar item opens nothing; a view of ours answering `hitTest` never
/// sees the press; a menu hung on the item's own views loses to the toolbar's;
/// and the control's own `menu` is never consulted either, because the bar
/// answers first — with its display-mode menu, which `SettingsWindow` turns off
/// because it only changed the bar's height. A local event monitor is ahead of
/// all of it: a right-click inside this control opens this menu and goes no
/// further, and every other press in the bar is left alone.
public struct HelmToolbarSwitcher<Value: Hashable>: NSViewRepresentable {
    private let name: String
    private let segments: [HelmSwitcherSegment<Value>]
    @Binding private var selection: Value

    @Environment(\.helmSwitcherStyle) private var style
    @Environment(\.helmSetSwitcherStyle) private var setStyle
    @Environment(\.isEnabled) private var isEnabled

    public init(_ name: String, selection: Binding<Value>, segments: [HelmSwitcherSegment<Value>]) {
        self.name = name
        self.segments = segments
        self._selection = selection
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentStyle = .automatic
        control.segmentDistribution = .fit
        control.trackingMode = .selectOne
        control.target = context.coordinator
        control.action = #selector(Coordinator.picked(_:))
        context.coordinator.watch(control)
        Self.fill(control, segments: segments, style: style,
                  selected: segments.firstIndex { $0.value == selection })
        context.coordinator.lastStyle = style
        return control
    }

    public static func dismantleNSView(_ control: NSSegmentedControl, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// **The gesture that opens a menu on a Mac**: the right button, or the left
    /// one with Control held, which is how a trackpad without a right click
    /// sends it.
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
        context.coordinator.choose = setStyle

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
        // Written here and not in `fill`, which `width(of:in:)` also calls
        // against a detached control that `HomebrewSettingsPage`'s own
        // reserve is calibrated photographically against. Written once rather
        // than on every pass, on a flag of its own and not on the fill
        // gating below: the bar decides its own metric, and a writer that ran
        // every time would fight a promotion to any other size rather than
        // anticipate this one.
        if !context.coordinator.hasPinnedMetric {
            context.coordinator.hasPinnedMetric = true
            control.controlSize = .extraLarge
        }

        let selectedIndex = segments.firstIndex { $0.value == selection }
        let isInitial = control.segmentCount == 0
        let styleChanged = context.coordinator.lastStyle != style
        let countChanged = control.segmentCount != segments.count

        if isInitial || countChanged || styleChanged {
            // Animate only when changing style on an existing populated control, never on initial population
            let shouldAnimate = !isInitial && !countChanged && !HelmMotion.reduceMotion
            if shouldAnimate {
                NSAnimationContext.runAnimationGroup { animation in
                    // `interface`'s length, taken from the token rather than
                    // written again here: AppKit wants seconds and has nowhere
                    // to put an `Animation`, and the reduce-motion branch this
                    // number cannot carry is the `shouldAnimate` guard above.
                    animation.duration = HelmMotion.interfaceDuration
                    animation.allowsImplicitAnimation = true
                    Self.fill(control, segments: segments, style: style, selected: selectedIndex)
                    control.layoutSubtreeIfNeeded()
                }
            } else {
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.allowsImplicitAnimation = false
                Self.fill(control, segments: segments, style: style, selected: selectedIndex)
                control.layoutSubtreeIfNeeded()
                NSAnimationContext.endGrouping()
            }
            context.coordinator.lastStyle = style
        } else {
            var labelsMatch = true
            let showsWord = style == .text || style == .iconsAndText
            for (idx, seg) in segments.enumerated() {
                if control.label(forSegment: idx) != (showsWord ? seg.label : "") {
                    labelsMatch = false
                    break
                }
            }
            let selectionMoved = selectedIndex.map { control.selectedSegment != $0 } ?? false
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
            if !labelsMatch || selectionMoved {
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.allowsImplicitAnimation = false
                Self.fill(control, segments: segments, style: style, selected: selectedIndex)
                control.layoutSubtreeIfNeeded()
                NSAnimationContext.endGrouping()
            }
        }

        control.isEnabled = isEnabled
        control.setAccessibilityLabel(name)
        let styleMenu = setStyle == nil ? nil
            : Self.menu(title: L("Tab labels"), style: style, target: context.coordinator)
        context.coordinator.styleMenu = styleMenu
        // Kept as the control's own menu as well: it costs nothing, and it is
        // what answers anywhere AppKit does consult the control.
        control.menu = styleMenu
    }

    /// **The size SwiftUI lays the item out at.** Asked for the control's own
    /// fitting size on every pass, so a width that changes — the style chosen
    /// for the bar puts words on the segments or takes them off — is a size
    /// SwiftUI can move between rather than a number it is handed once.
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl,
                             context: Context) -> CGSize? {
        nsView.fittingSize
    }

    /// The segments as the chosen style shows them. Written every update
    /// because the style, the words and the selection can each change under it.
    private static func fill(_ control: NSSegmentedControl,
                             segments: [HelmSwitcherSegment<Value>],
                             style: ToolbarSwitcherStyle, selected: Int?) {
        if control.segmentCount != segments.count { control.segmentCount = segments.count }
        for (index, segment) in segments.enumerated() {
            let showsGlyph = style != .text
            let showsWord = style == .text || style == .iconsAndText
            control.setLabel(showsWord ? segment.label : "", forSegment: index)
            control.setImage(showsGlyph
                ? NSImage(systemSymbolName: segment.symbol, accessibilityDescription: segment.label)
                : nil, forSegment: index)
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
            // The word, for a segment showing only its glyph — the pointer is
            // where a glyph-only control says what it is.
            control.setToolTip(segment.label, forSegment: index)
            // 0 is «as wide as it needs», which `segmentDistribution` then
            // leaves alone.
            control.setWidth(0, forSegment: index)
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
    }

    /// How wide the switcher draws in `style` — asked of a control built the
    /// same way, because the system decides its own metrics.
    @MainActor
    public static func width(of labels: [String], in style: ToolbarSwitcherStyle,
                             symbol: String = "circle") -> CGFloat {
        let control = NSSegmentedControl()
        control.segmentStyle = .automatic
        control.segmentDistribution = .fit
        let segments = labels.enumerated().map { index, label in
            HelmSwitcherSegment(index, label, symbol: symbol)
        }
        HelmToolbarSwitcher<Int>.fill(control, segments: segments, style: style, selected: 0)
        return control.fittingSize.width
    }

    /// Every style, the current one ticked, each item carrying the style it
    /// stands for.
    static func menu(title: String, style: ToolbarSwitcherStyle, target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: title)
        for choice in ToolbarSwitcherStyle.allCases {
            let item = NSMenuItem(title: choice.label,
                                  action: #selector(Coordinator.chose(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = choice.rawValue
            item.state = choice == style ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @MainActor public final class Coordinator: NSObject {
        var pick: (Int) -> Void = { _ in }
        var choose: SwitcherStyleSetter?
        var styleMenu: NSMenu?
        var lastStyle: ToolbarSwitcherStyle?
        /// Whether the bar's metric has been written onto the control yet.
        /// Its own flag rather than a reading of the fill gating above,
        /// because the two answer different questions: that one asks whether
        /// the segments need rewriting, this one whether the control has ever
        /// been given a size class. It goes with the view on
        /// `dismantleNSView`, so a switcher torn down and rebuilt — Homebrew's
        /// `switcherFits` choosing the pop-up button instead is a different
        /// `View` on each side of the `if` — pins once more on the new one.
        var hasPinnedMetric = false
        private weak var control: NSSegmentedControl?
        private var monitor: Any?

        func watch(_ control: NSSegmentedControl) {
            self.control = control
            stop()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) {
                [weak self] event in
                // The handler is `@Sendable` and `NSEvent` is not, although this
                // one arrives on the main thread — which is where it is read and
                // where the menu is raised. `Press` carries it over that line,
                // and only a `Bool` comes back.
                let press = Press(event: event)
                return MainActor.assumeIsolated { self?.took(press) ?? false } ? nil : event
            }
        }

        /// Whether this menu took the press — true only for the gesture, inside
        /// this control, which is then not passed on.
        private func took(_ press: Press) -> Bool {
            let event = press.event
            guard HelmToolbarSwitcher.isTheGesture(type: event.type, modifiers: event.modifierFlags),
                  let control, let styleMenu,
                  let window = control.window, event.window === window
            else { return false }
            let point = control.convert(event.locationInWindow, from: nil)
            guard control.bounds.contains(point) else { return false }
            styleMenu.popUp(positioning: nil, at: point, in: control)
            return true
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        @objc func picked(_ sender: NSSegmentedControl) {
            pick(sender.selectedSegment)
        }

        @objc func chose(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String else { return }
            choose?(ToolbarSwitcherStyle(stored: raw))
        }
    }
}

/// One press, over the line between a monitor's `@Sendable` handler and the
/// main actor it is already on.
private struct Press: @unchecked Sendable {
    let event: NSEvent
}
