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
    }

    let name: String
    var selected = false
    var look = Look.plain
    var width = HelmSpace.s7
    /// The glyph's colour, where the cell's own is not the text colour; it greys when the cell is disabled and
    /// the cell's circle stays as it was. Nil leaves the glyph as it inherits it.
    var ink: Color?
    @Environment(\.isEnabled) private var enabled
    let action: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        Button(action: action) {
            icon
                .font(HelmText.rowTitle)
                .foregroundStyle(ink.map { AnyShapeStyle(enabled ? $0 : Self.disabledInk) } ?? AnyShapeStyle(.primary))
                .frame(width: width, height: HelmSpace.s7)
                .background(fill)
                .contentShape(Rectangle())
        }
        .modifier(Plain(unfaded: ink != nil))
        .help(name)
        .accessibilityLabel(name)
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
        case .plain: RoundedRectangle(cornerRadius: HelmRadius.ctl).fill(Color.primary.opacity(selected ? 0.14 : 0))
        case .greyCircle: Circle().fill(HelmSurface.onPanelFill)
        case .accent: Circle().fill(Color.accentColor)
        }
    }
}

extension GlassCell where Icon == Image {
    /// A cell drawn by an SF Symbol.
    init(symbol: String, name: String, selected: Bool = false, look: Look = .plain, width: CGFloat = HelmSpace.s7,
         ink: Color? = nil, action: @escaping () -> Void) {
        self.init(name: name, selected: selected, look: look, width: width, ink: ink, action: action) {
            Image(systemName: symbol)
        }
    }
}
