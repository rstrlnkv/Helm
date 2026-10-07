import AppKit
import HelmUI
import SwiftUI

/// **A plate for one group of a bar's controls: a view that holds the group's
/// control and draws what is behind it, by the bar's look and by whether its
/// window is active.**
///
/// | look        | window   | behind the control                                  | `alphaValue`       |
/// |-------------|----------|-----------------------------------------------------|--------------------|
/// | liquidGlass | active   | one `NSGlassEffectView`, regular, no fill           | 1                  |
/// | liquidGlass | inactive | a fill of `HelmSurface.barPlate`                    | the name zone's    |
/// | flat        | active   | a fill of `HelmSurface.barPlate`                    | 1                  |
/// | flat        | inactive | a fill of `HelmSurface.barPlate`                    | the name zone's    |
///
/// The name zone's number is `helmNameZoneInactiveOpacity`: an inactive plate
/// dims by the number the name zone dims by, under either look, and it dims
/// the plate and its content as one unit.
///
/// **Measured on 27.2 in a standalone bench app's window, key and then not key,
/// in the dark appearance, not on this plate:** outside a toolbar an
/// `.extraLarge` stock segmented control draws a capsule track of its own, the
/// selected segment an accent capsule when the window is key and a grey one
/// when it is not; and a bare `NSGlassEffectView` on the window's background
/// loses its rim highlight by itself when its window is neither key nor main,
/// its body dimming a little.
/// The plate does not lean on the second: on the inactive edge it removes the
/// glass and draws the fill. The same bench read the brightest pixel of an
/// unselected label of a `.regular` stock segmented control as 229.3 with its
/// window key and 229.3 with it not key: a stock control does not dim its own
/// ink in an inactive window, only its selection capsule turns grey. So the
/// glass plate dims there as the flat one does. **Not seen on a screen:** this
/// plate with a control on it — how the stock control's own track reads on the
/// glass, that the flat cell's fixed inks do not dim by themselves in an
/// inactive window, how the dimmed plate reads beside the name, and that a
/// fill at `barPlate` is what AppKit's inactive platter looks like.
///
/// **The shape is the same in every state:** a continuous corner of half the
/// height, on the layer, and on the glass view when there is one; the layer
/// does not clip.
///
/// **The glass is a sibling below `content`, never its parent**, as the shell
/// content view keeps its own glass (`ShellContentView`): an activity edge
/// adds or removes the glass and leaves `content` where it is, the last
/// subview, framed to the plate's bounds in `layout()`.
///
/// The look and the activity are handed in; nothing here reads a stored
/// setting.
@MainActor
final class ShellBarPlate: NSView {
    /// Named so as not to hide `NSView.appearance`.
    var barAppearance: HelmBarAppearance {
        didSet {
            guard barAppearance != oldValue else { return }
            redraw()
        }
    }

    /// Whether the plate's window is key or main.
    var isActive: Bool {
        didSet {
            guard isActive != oldValue else { return }
            redraw()
        }
    }

    /// The group's control; always the last subview.
    var content: NSView? {
        didSet {
            guard content !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let content { addSubview(content) }
            needsLayout = true
        }
    }

    private let titlebarIsTransparent: Bool
    private var glass: NSGlassEffectView?

    init(appearance: HelmBarAppearance, isActive: Bool, titlebarIsTransparent: Bool) {
        self.barAppearance = appearance
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

    /// The corner and the glass's frame, from the current height.
    private func applyShape() {
        let radius = bounds.height / 2
        layer?.cornerRadius = radius
        // Said again after the radius: on 27.2 AppKit turned masking on by itself
        // once a radius above 0 was set — read on the shell content view's clip
        // layer (its own note), and `ThePlateDrawsByAppearanceAndActivityTests`
        // read this layer clipping without this line.
        layer?.masksToBounds = false
        glass?.frame = bounds
        glass?.cornerRadius = radius
    }

    /// Everything that depends on the look, the activity or the appearance:
    /// whether the glass is there, the fill, the dim. The fill is a colour of
    /// one appearance, so it is resolved here and again when the appearance
    /// changes, not in `layout()`.
    private func redraw() {
        let wantsGlass = barAppearance == .liquidGlass && isActive
        if wantsGlass, glass == nil {
            let view = NSGlassEffectView()
            view.style = .regular
            addSubview(view, positioned: .below, relativeTo: nil)
            glass = view
        } else if !wantsGlass, let glass {
            glass.removeFromSuperview()
            self.glass = nil
        }

        var fill: CGColor?
        var dark = false
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fill = NSColor(HelmSurface.barPlate).cgColor
            dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        layer?.backgroundColor = wantsGlass ? nil : fill

        let dims = !isActive
        alphaValue = dims
            ? CGFloat(helmNameZoneInactiveOpacity(dark: dark, titlebarIsTransparent: titlebarIsTransparent))
            : 1

        applyShape()
        needsLayout = true
    }
}
