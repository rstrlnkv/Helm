import AppKit
import HelmUI
import SwiftUI

/// The toolbar item's view: the control's width (its segments and the track's inset either side) and `lift` more than
/// its 36 pt in height, the control at the bottom (see `SettingsToolbar`). The control is the `contentView` of the
/// strip's own glass track, and both are fresh each time the strip enters a window (a glass that re-entered drew
/// empty; a control that re-entered drew a divider between unselected segments every second entry). The attention dots and the accessibility elements lie over the segments' places and take no
/// press.
@MainActor final class TabsStrip: NSView {
    var onPick: (Int) -> Void = { _ in }

    /// The toolbar centres an item at window y 26 and the row centres at 30, so the strip reaches 8 above the control.
    static let lift = CGFloat(8)

    private var control = NSSegmentedControl()
    private var glass = NSGlassEffectView()
    private var dots: [NSView] = []
    private var elements: [SegmentElement] = []
    private var declaration: HelmTabsDeclaration?
    private var widthConstraint: NSLayoutConstraint!

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: HelmTabsMetrics.height + Self.lift))
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([widthConstraint, heightAnchor.constraint(equalToConstant: HelmTabsMetrics.height + Self.lift)])
        control = makeControl()
        glass.contentView = control
        glass.cornerRadius = HelmTabsMetrics.height / 2
        addSubview(glass)
        setAccessibilityElement(false)
    }

    private func makeControl() -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .selectOne
        control.controlSize = .extraLarge
        // A reused control drew a divider between unselected segments every second entry under every style; with the default style even a first entry drew one at times, with `.capsule` no fresh control did.
        control.segmentStyle = .capsule
        control.target = self
        control.action = #selector(picked(_:))
        control.setAccessibilityElement(false)
        return control
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        let fresh = NSGlassEffectView()
        fresh.cornerRadius = HelmTabsMetrics.height / 2
        fresh.frame = glass.frame
        glass.contentView = nil
        control = makeControl()
        fresh.contentView = control
        glass.removeFromSuperview()
        addSubview(fresh, positioned: .below, relativeTo: nil)
        glass = fresh
        apply(declaration)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    var segmentCountForTesting: Int { control.segmentCount }
    func labelForTesting(_ index: Int) -> String? { control.label(forSegment: index) }
    func hasDotForTesting(_ index: Int) -> Bool { dots.indices.contains(index) && !dots[index].isHidden }
    func dotAlphaForTesting(_ index: Int) -> CGFloat { dots[index].alphaValue }
    var selectedSegmentForTesting: Int { control.selectedSegment }
    var widthForTesting: CGFloat { widthConstraint.constant }

    func select(_ index: Int) {
        control.selectedSegment = index
        refreshElements()
    }

    @objc private func picked(_ sender: NSSegmentedControl) { onPick(sender.selectedSegment) }

    /// Every segment from the declaration, the count first; nil leaves the strip as it is (the item is hidden).
    func apply(_ declaration: HelmTabsDeclaration?) {
        self.declaration = declaration
        guard let declaration else { return }
        let tabs = declaration.tabs
        let style = declaration.style
        let widths = HelmTabsMetrics.widths(tabs, style)
        control.segmentCount = tabs.count
        for (index, tab) in tabs.enumerated() {
            control.setWidth(widths[index], forSegment: index)
            control.setLabel(style == .icons ? "" : tab.title, forSegment: index)
            let size: CGFloat = style == .icons ? HelmTabNumbers.iconSize : HelmTabNumbers.wordSize
            control.setImage(style == .text ? nil : NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size, weight: .regular)), forSegment: index)
            control.setToolTip(style == .icons ? tab.title : nil, forSegment: index)
        }
        control.selectedSegment = tabs.firstIndex { $0.id == declaration.selected } ?? -1
        control.isEnabled = declaration.enabled
        let total = HelmTabsMetrics.total(tabs, style)
        widthConstraint.constant = total
        glass.frame = NSRect(x: 0, y: Self.lift, width: total, height: HelmTabsMetrics.height)
        layoutDots(widths)
        refreshElements()
    }

    private func layoutDots(_ widths: [CGFloat]) {
        guard let declaration else { return }
        while dots.count < declaration.tabs.count {
            let dot = DotView(frame: NSRect(x: 0, y: 0, width: HelmTabsMetrics.dot, height: HelmTabsMetrics.dot))
            addSubview(dot)
            dots.append(dot)
        }
        var x = HelmTabsMetrics.trackInset
        let size = HelmTabsMetrics.dot
        for (index, dot) in dots.enumerated() {
            guard index < declaration.tabs.count else { dot.isHidden = true; continue }
            let tab = declaration.tabs[index]
            dot.isHidden = !tab.needsAttention
            // The control centres the label, so the dot stands `dotGap` after it, centred on the row as `.flat`'s
            // is; on a glyph alone it sits on the glyph's top right, as `.flat`'s does.
            let mid = x + widths[index] / 2
            if declaration.style == .icons {
                dot.frame = NSRect(x: mid + 7, y: Self.lift + 8, width: size, height: size)
            } else {
                dot.frame = NSRect(x: mid + HelmTabsMetrics.labelHalf(tab, declaration.style) + HelmTabsMetrics.dotGap,
                                   y: Self.lift + (HelmTabsMetrics.height - size) / 2, width: size, height: size)
            }
            // Dimmed with the control, as `.flat`'s group is.
            dot.alphaValue = declaration.enabled ? 1 : HelmTabNumbers.dimmed
            x += widths[index]
        }
        recolourDots()
    }

    private func recolourDots() {
        let increased = declaration?.increasedContrast ?? false
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor(HelmSignal.warning(increased: increased)).cgColor
            for dot in dots { dot.layer?.backgroundColor = color }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        recolourDots()
    }

    // MARK: - accessibility

    private func refreshElements() {
        guard let declaration else { elements = []; return }
        let widths = HelmTabsMetrics.widths(declaration.tabs, declaration.style)
        var x = HelmTabsMetrics.trackInset
        elements = declaration.tabs.enumerated().map { index, tab in
            let element = SegmentElement()
            element.setAccessibilityRole(.radioButton)
            element.setAccessibilityLabel(tab.title)
            element.setAccessibilityHelp(tab.attentionNote)
            element.setAccessibilityValue(control.selectedSegment == index ? 1 : 0)
            element.setAccessibilityParent(self)
            element.setAccessibilityEnabled(declaration.enabled)
            element.setAccessibilityFrameInParentSpace(NSRect(x: x, y: Self.lift, width: widths[index],
                                                              height: HelmTabsMetrics.height))
            element.press = { [weak self] in
                guard let self, declaration.enabled else { return false }
                self.control.selectedSegment = index
                self.onPick(index)
                return true
            }
            x += widths[index]
            return element
        }
    }

    override func accessibilityChildren() -> [Any]? { elements }
    override func isAccessibilityElement() -> Bool { false }
}

/// A segment as VoiceOver sees it: a radio button with its title, selected state and a press.
final class SegmentElement: NSAccessibilityElement {
    var press: () -> Bool = { false }
    override func accessibilityPerformPress() -> Bool { press() }
}

/// The attention dot: a layer's fill, and it answers no press.
private final class DotView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The leading spacer item's view: as wide as its constraint says.
final class LeadSpacer: NSView {
    private var widthConstraint: NSLayoutConstraint!
    var width: CGFloat {
        get { widthConstraint.constant }
        set { widthConstraint.constant = newValue }
    }
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([widthConstraint, heightAnchor.constraint(equalToConstant: 1)])
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
}
