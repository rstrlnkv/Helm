import AppKit
import HelmUI
import SwiftUI

/// **A plate for one group of a bar's controls: a view that holds the group's
/// control and draws what is behind it, by whether its window is active.**
///
/// | window   | behind the control               | `alphaValue`    |
/// |----------|----------------------------------|-----------------|
/// | active   | a fill of `HelmSurface.barPlate` | 1               |
/// | inactive | a fill of `HelmSurface.barPlate` | the name zone's |
///
/// The name zone's number is `helmNameZoneInactiveOpacity`: an inactive plate
/// dims by the number the name zone dims by, and it dims the plate and its
/// content as one unit.
///
/// **Measured on 27.2 in a standalone bench app's window, key and then not key,
/// in the dark appearance, not on this plate:** outside a toolbar an
/// `.extraLarge` stock segmented control draws a capsule track of its own, the
/// selected segment an accent capsule when the window is key and a grey one
/// when it is not. The same bench read the brightest pixel of an
/// unselected label of a `.regular` stock segmented control as 229.3 with its
/// window key and 229.3 with it not key: that control, outside a toolbar, did not dim its
/// label when its window stopped being key, only its selection capsule turned grey (in a toolbar
/// AppKit's own control does dim when the app is inactive). The strip
/// on this plate is `HelmFlatSegmentedCell`, whose inks are fixed.
/// **Not seen on a screen:** this plate with a control on it — that the flat
/// cell's fixed inks do not dim by themselves in an inactive window, how the
/// dimmed plate reads beside the name, and that a fill at `barPlate` is what
/// AppKit's inactive platter looks like.
///
/// **The shape is the same in every state:** a continuous corner of half the
/// height, on the layer, which does not clip.
///
/// `content` is the plate's only subview, framed to the plate's bounds in
/// `layout()`.
///
/// The activity is handed in; nothing here reads a stored setting.
@MainActor
final class ShellBarPlate: NSView {
    /// Whether the plate's window is key or main.
    var isActive: Bool {
        didSet {
            guard isActive != oldValue else { return }
            redraw()
        }
    }

    /// The group's control.
    var content: NSView? {
        didSet {
            guard content !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let content { addSubview(content) }
            needsLayout = true
        }
    }

    private let titlebarIsTransparent: Bool

    init(isActive: Bool, titlebarIsTransparent: Bool) {
        self.isActive = isActive
        self.titlebarIsTransparent = titlebarIsTransparent
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        redraw()
    }

    required init?(coder: NSCoder) { fatalError("ShellBarPlate is built in code") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        redraw()
    }

    override func layout() {
        super.layout()
        applyShape()
        content?.frame = bounds
    }

    /// The corner, from the current height.
    private func applyShape() {
        let radius = bounds.height / 2
        layer?.cornerRadius = radius
        // Said again after the radius: on 27.2 AppKit turned masking on by itself
        // once a radius above 0 was set — read on the shell content view's clip
        // layer (its own note), and this layer read as clipping without this line.
        layer?.masksToBounds = false
    }

    /// Everything that depends on the activity or the appearance: the fill,
    /// the dim. The fill is a colour of one appearance, so it is resolved here
    /// and again when the appearance changes, not in `layout()`.
    private func redraw() {
        var fill: CGColor?
        var dark = false
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fill = NSColor(HelmSurface.barPlate).cgColor
            dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        layer?.backgroundColor = fill

        let dims = !isActive
        alphaValue = dims
            ? CGFloat(helmNameZoneInactiveOpacity(dark: dark, titlebarIsTransparent: titlebarIsTransparent))
            : 1

        applyShape()
        needsLayout = true
    }
}
