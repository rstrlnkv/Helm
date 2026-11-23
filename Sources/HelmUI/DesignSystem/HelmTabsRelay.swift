import SwiftUI

// **How the page's tabs reach a window's toolbar.** Under Liquid Glass the settings window shows its page tabs as an
// `NSToolbar` item (`SettingsToolbar`, HelmApp), so they wear the system's toolbar glass and press-and-hold lens. The
// toolbar is an AppKit object and the declaration is closures cut from the page's state at its last body, so the
// declaration is *relayed*: the card's header row (`CardHeader`) mounts `HelmTabsRelay`, which hands it to the
// `HelmTabsSink` the window put in the environment; and a clear placeholder, `HelmTabsSlot`, stands in the row where
// the strip is, so `HeaderRowLayout` keeps centring it on the card and giving way, and reports where it is for the
// toolbar to put its item there. No sink (the Launchpad's panel, a fixture) or Flat: the row draws the tabs itself
// (`HelmHeaderTabs`).

/// What the toolbar needs to draw the page's tabs and to answer a press.
public struct HelmTabsDeclaration {
    public let tabs: [HelmHeaderTab]
    public let selected: String
    public let enabled: Bool
    public let style: HeaderTabLabels
    public let increasedContrast: Bool
    /// Writes the page's selection with animations off, so the page below is not swapped inside one.
    public let select: (String) -> Void

    public init(tabs: [HelmHeaderTab], selected: String, enabled: Bool, style: HeaderTabLabels,
                increasedContrast: Bool, select: @escaping (String) -> Void) {
        self.tabs = tabs
        self.selected = selected
        self.enabled = enabled
        self.style = style
        self.increasedContrast = increasedContrast
        self.select = select
    }
}

/// **The window's ear for the tabs.** Every call names its `owner`, one per mounted header row: the pane's root is
/// rebuilt on a change of language (`RebuiltOnLanguageChange`), and the row mints a new owner each time the look
/// leaves Glass, since the relay's dismantle retires the old one for good. The old row's late call, `release`
/// included, must not clear what the new one declared.
public struct HelmTabsSink {
    public let declare: @MainActor (_ owner: UUID, _ declaration: HelmTabsDeclaration?) -> Void
    /// The placeholder's rectangle in the window's top-left coordinates, nil when it is gone.
    public let place: @MainActor (_ owner: UUID, _ rect: CGRect?) -> Void
    public let release: @MainActor (_ owner: UUID) -> Void

    public init(declare: @escaping @MainActor (UUID, HelmTabsDeclaration?) -> Void,
                place: @escaping @MainActor (UUID, CGRect?) -> Void,
                release: @escaping @MainActor (UUID) -> Void) {
        self.declare = declare
        self.place = place
        self.release = release
    }
}

/// **Where one row's tabs go**: the window's sink and the row's owner token, which the relay and the placeholder of
/// the same row share. The owner changes with the row: on a rebuild of the pane for a language, and on each leaving
/// of Glass (the relay's dismantle retires a token for good).
struct HelmTabsTarget {
    let owner: UUID
    let sink: HelmTabsSink
}

extension EnvironmentValues {
    /// Nil: the row draws the tabs itself.
    @Entry public var helmTabsSink: HelmTabsSink?
}

/// The strip's measure: what the toolbar's control sets per segment and the placeholder takes in the row.
public enum HelmTabsMetrics {
    private static var font: NSFont { .systemFont(ofSize: HelmTabNumbers.wordSize) }
    /// The glyph's own width in a tab (the segment's padding is `HelmTabNumbers.segmentPadding`, as the `.flat` tab's).
    private static let glyph = CGFloat(16)

    public static let height = HelmHeaderActions.side

    /// The dot beside a word, and the gap before it: the room a segment with a dot gains, as `.flat`'s tab does.
    public static let dot = HelmTabNumbers.dot
    public static let dotGap = HelmTabNumbers.dotGap

    public static func word(_ tab: HelmHeaderTab) -> CGFloat {
        ceil((tab.title as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Where a segment's label ends from the segment's centre: the label is centred by the control, so the dot
    /// stands `dotGap` after it. Text: the word; with the glyph: glyph, `glyphGap` and the word.
    public static func labelHalf(_ tab: HelmHeaderTab, _ style: HeaderTabLabels) -> CGFloat {
        style == .iconsAndText ? (glyph + HelmTabNumbers.glyphGap + word(tab)) / 2 : word(tab) / 2
    }

    /// What the control keeps free either side of its segments once it stands in a toolbar item: measured on
    /// macOS 27.3, 2026-11-23, with a bordered item (Homebrew page, Russian, `.text`: a 316 pt run of segments gave a
    /// 334 pt `fittingSize`). Not readable off a control outside the toolbar, which reads the plain sum, so no test of
    /// an offscreen control can hold it: the shots can.
    /// Without it a width of the segments alone left the first label on the track's edge and the last pill past the other end.
    public static let trackInset = CGFloat(9)

    /// The `.flat` tab's width from its own label: padding either side of the word, the glyph, or both, and the room a
    /// dot beside the label takes. `word()` rounds up, so a tab can exceed Flat's by under a point.
    public static func tabWidths(_ tabs: [HelmHeaderTab], _ style: HeaderTabLabels) -> [CGFloat] {
        tabs.map { tab in
            let room = tab.needsAttention ? dot + dotGap : 0
            let padding = 2 * HelmTabNumbers.segmentPadding
            switch style {
            case .text: return word(tab) + padding + room
            case .icons: return HelmTabNumbers.iconWidth + padding
            case .iconsAndText: return glyph + HelmTabNumbers.glyphGap + word(tab) + padding + room
            }
        }
    }

    /// The whole strip's width: the plate, the tabs with a gap between two, the plate, the `.flat` strip's sum to within
    /// each word's rounding (under 1 pt per word). The plate and the gap are named once (`HelmTabNumbers`) and the width
    /// is derived from them here; it is the one source of the control's, the toolbar item's and the row's placeholder's
    /// width (Flat lays its own strip out).
    public static func total(_ tabs: [HelmHeaderTab], _ style: HeaderTabLabels) -> CGFloat {
        2 * HelmTabNumbers.plate + tabWidths(tabs, style).reduce(0, +) + HelmTabNumbers.gap * CGFloat(max(tabs.count - 1, 0))
    }

    /// Every segment's width, so no word is cut and the dots stand where the segments are. A segment owns its tab and
    /// half of each gap beside it, the first and the last also the plate, less the `trackInset` the control keeps free
    /// at its two ends: so a middle segment is centred on its `.flat` tab, and the first and the last
    /// centres stand 3.75 pt further in than their tabs' (the segment starts `trackInset` in, the tab `plate` in),
    /// as near as the control allows. The sum is
    /// `total - 2 * trackInset`.
    public static func widths(_ tabs: [HelmHeaderTab], _ style: HeaderTabLabels) -> [CGFloat] {
        let last = tabs.count - 1
        return tabWidths(tabs, style).enumerated().map { index, tab in
            let before = index == 0 ? HelmTabNumbers.plate - trackInset : HelmTabNumbers.gap / 2
            let after = index == last ? HelmTabNumbers.plate - trackInset : HelmTabNumbers.gap / 2
            return before + tab + after
        }
    }
}

/// Hands the page's declaration to the sink, every update; nil when the page declares no tabs. Zero size.
struct HelmTabsRelay: NSViewRepresentable {
    let target: HelmTabsTarget
    let content: HelmHeaderContent?
    let style: HeaderTabLabels
    let increasedContrast: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let content, !content.tabs.isEmpty, let binding = content.selectedTab else {
            target.sink.declare(target.owner, nil)
            return
        }
        target.sink.declare(target.owner, HelmTabsDeclaration(
            tabs: content.tabs, selected: binding.wrappedValue, enabled: content.tabsEnabled, style: style,
            increasedContrast: increasedContrast,
            select: { id in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { binding.wrappedValue = id }
            }))
        context.coordinator.target = target
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let target = coordinator.target {
            MainActor.assumeIsolated { target.sink.release(target.owner) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var target: HelmTabsTarget?
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? { .zero }
}

/// **The strip's place in the row under the toolbar**: clear, the strip's width by its height, in the tabs' part of
/// the row's layout; it reports its rectangle in the window to the sink.
struct HelmTabsSlot: View {
    let target: HelmTabsTarget
    let tabs: [HelmHeaderTab]
    let style: HeaderTabLabels

    var body: some View {
        Color.clear
            .frame(width: HelmTabsMetrics.total(tabs, style), height: HelmTabsMetrics.height)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { target.sink.place(target.owner, $0) }
            .onDisappear { target.sink.place(target.owner, nil) }
            .accessibilityHidden(true)
    }
}
