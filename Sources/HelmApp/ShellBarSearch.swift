import AppKit
import HelmUI

/// **The search of a Flat bar: a Helm-owned toolbar item, because the toolbar gives glass to every
/// `NSSearchToolbarItem`** (engineer knowledge, 2026-11-15: a probe on macOS 27.3 in a key window set `isBezeled`, `drawsBackground`,
/// `bezelStyle`, the cell's background, `isBordered` and `style` on an `NSSearchToolbarItem` and on its assigned
/// field, and all stayed glass; only a view in an ordinary `NSToolbarItem` escapes, and it loses AppKit's collapse
/// to the magnifier). The item's view is a
/// `ShellBarPlate` over one container that holds a plain `NSSearchField` and a magnifier button, both framed to
/// the plate. The plate's width is one constraint, `apply(width:collapsed:animated:completion:)` the only writer;
/// what it is set to comes from `ShellBarLayout.searchPlan`, which `SettingsToolbar.settleFlat` asks.
///
/// Exactly one of the field and the magnifier is shown at a time: a hidden field leaves the accessibility tree,
/// so a collapsed search offers the button alone, named like the field. Under Liquid Glass none of this exists
/// (`PageBar.searchItem` stays the `NSSearchToolbarItem`).
///
/// **Seen on a shown window** (build 1701, by hand): no glass in either look, key or not; the 36-point magnifier
/// under Always Collapse Search; a press on the magnifier opening the field to 283 with an editor; the focus ring
/// along the plate's outline; widths 860 to 1060. **Not seen:** typing, Return, the clear button, the fold at the
/// end of editing, ⌘F, the actions capsule squeezing the field, Reduce Motion, VoiceOver speech, the width
/// animation.
@MainActor
final class ShellBarSearch {
    let item: NSToolbarItem
    let plate: ShellBarPlate
    let field: ShellBarSearchField
    let magnifier: ShellBarMagnifierButton

    /// A press on the magnifier, ⌘F or a VoiceOver press opened the field and it has not yet ended editing.
    var isOpen = false

    /// Where `apply` last sent the plate, so a pass that plans the same thing starts nothing.
    private(set) var target: (width: CGFloat, collapsed: Bool)?

    /// Whether a width animation is under way.
    private(set) var isAnimating = false

    /// A newer `apply` makes an older one's completion stale.
    private var generation = 0

    private let widthConstraint: NSLayoutConstraint

    /// The magnifier's press, wired by `SettingsToolbar`.
    var onOpen: (() -> Void)?

    init(identifier: NSToolbarItem.Identifier, isActive: Bool, titlebarIsTransparent: Bool) {
        field = ShellBarSearchField()
        magnifier = ShellBarMagnifierButton()
        plate = ShellBarPlate(isActive: isActive, titlebarIsTransparent: titlebarIsTransparent)
        item = NSToolbarItem(itemIdentifier: identifier)

        let container = NSView()
        field.autoresizingMask = [.width, .height]
        magnifier.autoresizingMask = [.width, .height]
        container.addSubview(field)
        container.addSubview(magnifier)
        plate.translatesAutoresizingMaskIntoConstraints = false
        plate.content = container
        widthConstraint = plate.widthAnchor.constraint(equalToConstant: ShellBarLayout.searchWidth)
        NSLayoutConstraint.activate([
            widthConstraint,
            plate.heightAnchor.constraint(equalToConstant: ShellBarLayout.searchPlateHeight)
        ])
        magnifier.isHidden = true
        magnifier.target = self
        magnifier.action = #selector(magnifierPressed)

        item.view = plate
        item.isBordered = false
        item.visibilityPriority = .user
        patchLabels()
        item.menuFormRepresentation = {
            let entry = NSMenuItem(title: HelmA11y.searchField, action: #selector(magnifierPressed), keyEquivalent: "")
            entry.target = self
            return entry
        }()
    }

    /// Being edited: opened by a press, or the editor is up.
    var isEditing: Bool { isOpen || field.currentEditor() != nil }

    /// The words the item and its two controls name themselves by, in the running language.
    func patchLabels() {
        item.label = HelmA11y.searchField
        item.paletteLabel = HelmA11y.searchField
        item.toolTip = HelmA11y.searchField
        field.setAccessibilityLabel(HelmA11y.searchField)
        magnifier.setAccessibilityLabel(HelmA11y.searchField)
        item.menuFormRepresentation?.title = HelmA11y.searchField
    }

    func setEnabled(_ enabled: Bool) {
        field.isEnabled = enabled
        magnifier.isEnabled = enabled
        item.menuFormRepresentation?.isEnabled = enabled
    }

    @objc private func magnifierPressed() { onOpen?() }

    /// **Sets the plate's width and which of the two controls shows.** The field shows from the start of an open,
    /// the magnifier from the end of a close (the plate is narrower than the field in between, and the field
    /// overflows it for that while). Animated over `HelmMotion`'s interface duration and curve, a cut under
    /// Reduce Motion or with no window. `completion` runs once the plate is at its width, never after a newer
    /// `apply`.
    func apply(width: CGFloat, collapsed: Bool, animated: Bool, completion: (() -> Void)? = nil) {
        generation += 1
        let mine = generation
        target = (width, collapsed)
        if !collapsed {
            field.isHidden = false
            magnifier.isHidden = true
        }
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self, self.generation == mine else { return }
            self.isAnimating = false
            if collapsed {
                self.field.isHidden = true
                self.magnifier.isHidden = false
            }
            completion?()
        }
        guard animated, !HelmMotion.reduceMotion, plate.window != nil,
              abs(widthConstraint.constant - width) > 0.5 else {
            isAnimating = false
            widthConstraint.constant = width
            finish()
            return
        }
        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = HelmMotion.interfaceDuration
            context.timingFunction = HelmMotion.interfaceCurve
            context.allowsImplicitAnimation = true
            widthConstraint.animator().constant = width
        }, completionHandler: {
            MainActor.assumeIsolated { finish() }
        })
    }
}

/// The field of a Flat bar's search: no bezel and no background, the plate behind it is the surface.
@MainActor
final class ShellBarSearchField: NSSearchField {
    override class var cellClass: AnyClass? {
        get { ShellBarSearchFieldCell.self }
        set {}
    }

    init() {
        super.init(frame: .zero)
        isBezeled = false
        isBordered = false
        drawsBackground = false
        focusRingType = .exterior
        sendsWholeSearchString = true
        cell?.sendsActionOnEndEditing = false
        recentsAutosaveName = nil
        postsFrameChangedNotifications = false
    }

    required init?(coder: NSCoder) { fatalError("ShellBarSearchField is built in code") }
}

/// The cell of that field: the glyph, the text and the clear button stand inside the plate's round ends, and the
/// focus ring follows the plate's outline (radius half the height) instead of the cell's rectangle.
@MainActor
final class ShellBarSearchFieldCell: NSSearchFieldCell {
    private static let inset: CGFloat = 8

    /// What the text keeps clear of the glyph, on top of the glyph's own width.
    private static let glyphToText: CGFloat = 6

    override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        super.searchButtonRect(forBounds: rect.insetBy(dx: Self.inset, dy: 0))
    }

    /// The text's rect: inside the round ends, `glyphToText` further from the glyph, and as high as one line of the
    /// field's font, centred in the plate (an unbezeled cell draws from the top of its rect). The editor and the
    /// drawing both take their rect from here.
    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var text = super.searchTextRect(forBounds: rect.insetBy(dx: Self.inset, dy: 0))
        text.origin.x += Self.glyphToText
        text.size.width = max(0, text.width - Self.glyphToText)
        let line = ceil(NSLayoutManager().defaultLineHeight(for: font ?? .systemFont(ofSize: NSFont.systemFontSize)))
        if line < text.height {
            text.origin.y += ((text.height - line) / 2).rounded()
            text.size.height = line
        }
        return text
    }

    override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        super.cancelButtonRect(forBounds: rect.insetBy(dx: Self.inset, dy: 0))
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect { searchTextRect(forBounds: rect) }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
                       event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate,
                   event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
                         start selStart: Int, length selLength: Int) {
        super.select(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate,
                     start: selStart, length: selLength)
    }

    override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
        let radius = cellFrame.height / 2
        NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius).fill()
    }
}

/// The collapsed search: a borderless magnifier the width of the plate, pressable and named like the field.
@MainActor
final class ShellBarMagnifierButton: NSButton {
    init() {
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        contentTintColor = .secondaryLabelColor
        focusRingType = .exterior
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("ShellBarMagnifierButton is built in code") }

    override func drawFocusRingMask() {
        let radius = bounds.height / 2
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }
}
