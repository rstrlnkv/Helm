import AppKit
import SwiftUI
import HelmUI

/// One round-edged control on a glass bar: an icon, lit with 14 % of the primary colour while it is
/// selected, and a name that is both its tooltip and its VoiceOver label. The capture panel's mode
/// controls and the editor's palette are drawn by it, so a cell is one look on both.
struct GlassCell<Icon: View>: View {
    enum Look {
        /// The selected cell is a rounded square of 14 % primary.
        case plain
        /// A grey circle, always: Undo, Redo and ⋯.
        case greyCircle
        /// A circle in the accent colour with a white icon: Done.
        case accent
        /// Nothing behind the icon, selected or not: the editor's pen, marker and pencil, which show the choice by standing higher.
        case bare
    }

    let name: String
    var selected = false
    var look = Look.plain
    var width = HelmSpace.s7
    /// The cell's height, and its press zone's unless `hit` is set; the palette's objects are as tall as the palette.
    var height = HelmSpace.s7
    /// The glyph's colour, where the cell's own is not the text colour; it greys when the cell is disabled and
    /// the cell's circle stays as it was. Nil leaves the glyph as it inherits it.
    var ink: Color?
    /// The cell is drawn pressed: a grey circle is filled with `paletteInk`, and the glyph is the caller's `ink`
    /// (`pressedInk`). ⋯ while its menu is open. A plain cell is filled as a selected one is, without the selected
    /// trait: the panel's gear while its menu is open.
    var pressed = false
    /// The width and height of the cell's layout and of the part that takes a press, the circle centred in it; nil is the
    /// cell's own size. SwiftUI takes no press outside a view's layout, so the caller makes room for it.
    var hit: CGFloat?
    /// A 14 pt badge at the cell's lower right, drawn by this SF Symbol, and the accessibility value that goes with it.
    var badge: String?
    var value: String?
    @Environment(\.isEnabled) private var enabled
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            icon
                .font(HelmText.rowTitle)
                .foregroundStyle(ink.map { AnyShapeStyle(enabled ? $0 : Self.disabledInk) } ?? AnyShapeStyle(.primary))
                .frame(width: width, height: height)
                .background(fill)
                .overlay(alignment: .bottomTrailing) { badgeView }
                .frame(width: hit ?? width, height: hit ?? height)
                .contentShape(Rectangle())
        }
        .modifier(Plain(unfaded: ink != nil))
        .help(name)
        .accessibilityLabel(name)
        .accessibilityValue(value ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The plain button style, which fades the whole label when the cell is disabled, circle and glyph alike. A
    /// cell with an `ink` greys its glyph by itself and keeps its circle, so it takes a style that fades nothing
    /// and shows a press as the plain one does. A disabled button sends nothing in either: the environment's
    /// `isEnabled` decides that, not the style.
    private struct Plain: ViewModifier {
        let unfaded: Bool
        func body(content: Content) -> some View {
            if unfaded { content.buttonStyle(Unfaded()) } else { content.buttonStyle(.plain) }
        }
    }

    private struct Unfaded: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
        }
    }

    /// The editor palette's glyph ink, from its mockup (`#3A3A3C` light, `#E5E5EA` dark): no token of the
    /// design system is that grey, so the two values live here and nowhere else.
    static var paletteInk: Color { adaptive(light: (0x3A, 0x3A, 0x3C), dark: (0xE5, 0xE5, 0xEA)) }
    /// A disabled glyph, from the same mockup: `#B8B8BD` light, `#6C6C70` dark. Opaque, so nothing dims it twice.
    private static var disabledInk: Color { adaptive(light: (0xB8, 0xB8, 0xBD), dark: (0x6C, 0x6C, 0x70)) }

    /// The glyph on a pressed circle and in the badge, and the ring round the badge, from the mockup: `#F7F7F7` on
    /// light and `#1F1F21` on dark. The pressed circle itself is `paletteInk`.
    static var pressedInk: Color { adaptive(light: (0xF7, 0xF7, 0xF7), dark: (0x1F, 0x1F, 0x21)) }
    private static var badgeSize: CGFloat { 14 }
    private static var badgeRing: CGFloat { 1.5 }
    private static var badgeOffset: CGFloat { 3 }
    /// How far the badge and its ring reach below the circle: the offset and the ring's width.
    static var badgeReach: CGFloat { badgeOffset + badgeRing }

    @ViewBuilder private var badgeView: some View {
        if let badge {
            Image(systemName: badge)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Self.pressedInk)
                .frame(width: Self.badgeSize, height: Self.badgeSize)
                .background(Circle().fill(Self.paletteInk))
                // The mockup's 1.5 pt ring, so the badge does not merge with a pressed circle of its own colour.
                .overlay(Circle().strokeBorder(Self.pressedInk, lineWidth: Self.badgeRing).padding(-Self.badgeRing))
                .offset(x: Self.badgeOffset, y: Self.badgeOffset)
        }
    }

    private static func adaptive(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
        func ns(_ c: (Int, Int, Int)) -> NSColor {
            NSColor(srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? ns(dark) : ns(light)
        })
    }

    @ViewBuilder private var fill: some View {
        switch look {
        case .plain: RoundedRectangle(cornerRadius: HelmRadius.ctl).fill(Color.primary.opacity(selected || pressed ? 0.14 : 0))
        case .greyCircle: Circle().fill(pressed ? AnyShapeStyle(Self.paletteInk) : AnyShapeStyle(HelmSurface.onPanelFill))
        case .accent: Circle().fill(Color.accentColor)
        case .bare: Color.clear
        }
    }
}

extension GlassCell where Icon == Image {
    /// A cell drawn by an SF Symbol.
    init(symbol: String, name: String, selected: Bool = false, look: Look = .plain, width: CGFloat = HelmSpace.s7,
         ink: Color? = nil, pressed: Bool = false, hit: CGFloat? = nil, badge: String? = nil, value: String? = nil,
         action: @escaping () -> Void) {
        self.init(name: name, selected: selected, look: look, width: width, ink: ink, pressed: pressed, hit: hit,
                  badge: badge, value: value, action: action) {
            Image(systemName: symbol)
        }
    }
}
