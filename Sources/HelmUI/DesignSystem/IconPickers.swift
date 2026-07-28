import SwiftUI

/// Glyph-forward shape picker: equal-width swatches (the glyph is the hero, the
/// container stays quiet), with the selected shape's name shown once below the
/// row so no swatch has to carry wrapping multi-line text. `selection` is a
/// `MenuBarIconStyle` rawValue. Shared by the global menu-bar settings and any
/// module that offers its own icon (e.g. Keep Awake's active-state icon).
public struct IconShapePicker: View {
    @Binding private var selection: String
    private let tintToken: String

    public init(selection: Binding<String>, tintToken: String = "primary") {
        self._selection = selection
        self.tintToken = tintToken
    }

    private var current: MenuBarIconStyle { MenuBarIconStyle(rawValue: selection) ?? .ring }

    public var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(MenuBarIconStyle.allCases, id: \.rawValue) { s in
                    swatch(s)
                }
            }
            Text(current.label)
                .font(.callout)
                .foregroundStyle(HelmText.quiet)
                .animation(HelmMotion.interface, value: selection)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    /// Whether the glyph should follow the window's appearance rather than
    /// carry a colour of its own.
    private var neutral: Bool { tintToken == "primary" }

    private func swatch(_ s: MenuBarIconStyle) -> some View {
        let selected = selection == s.rawValue
        // A neutral glyph is drawn white and rendered as a template, so its
        // colour comes from `foregroundStyle` at draw time. Baking
        // `labelColor` into the bitmap could not work: `RingIcon` draws with
        // `lockFocus`, which resolves the dynamic colour once against whatever
        // `NSAppearance.current` happened to be — and in a light window that
        // produced white glyphs on a white swatch.
        return HelmIconGlyph(image: RingIcon.make(style: s, size: .medium,
                                                  tintToken: neutral ? nil : tintToken),
                             neutral: neutral)
            .frame(width: 26, height: 26)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : HelmSurface.wellFill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .help(s.label)
            // A real button, not a tap gesture: a gesture carries no button
            // trait, takes no focus and cannot be reached from the keyboard, so
            // this setting was mouse-only and unnamed for VoiceOver.
            .onTapGesture { selection = s.rawValue }
            .accessibilityElement()
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(s.label)
            .accessibilityAction { selection = s.rawValue }
    }
}

/// Size picker that renders the given shape at each real point size, so the
/// preview is the actual on-screen result rather than an abstract label; the
/// selected size's localized name is shown once below the row. `selection` is a
/// `MenuBarIconSize` rawValue.
public struct IconSizePicker: View {
    @Binding private var selection: String
    private let style: MenuBarIconStyle
    private let tintToken: String

    public init(selection: Binding<String>, style: MenuBarIconStyle, tintToken: String = "primary") {
        self._selection = selection
        self.style = style
        self.tintToken = tintToken
    }

    private var current: MenuBarIconSize { MenuBarIconSize(rawValue: selection) ?? .medium }

    public var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(MenuBarIconSize.allCases, id: \.rawValue) { sz in
                    swatch(sz)
                }
            }
            Text(current.label)
                .font(.callout)
                .foregroundStyle(HelmText.quiet)
                .animation(HelmMotion.interface, value: selection)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var neutral: Bool { tintToken == "primary" }

    private func swatch(_ sz: MenuBarIconSize) -> some View {
        let selected = selection == sz.rawValue
        // No .resizable(): the image draws at its natural point size, so the
        // sizes differ visibly across the row.
        return HelmIconGlyph(image: RingIcon.make(style: style, size: sz,
                                                  tintToken: neutral ? nil : tintToken),
                             neutral: neutral)
            .frame(width: 28, height: 28)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : HelmSurface.wellFill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .help(sz.label)
            .onTapGesture { selection = sz.rawValue }
            .accessibilityElement()
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(sz.label)
            .accessibilityAction { selection = sz.rawValue }
    }
}

/// One glyph, drawn either in its own colour or in the window's.
///
/// The template branch exists because a bitmap cannot hold a dynamic colour:
/// `labelColor` baked at `lockFocus` time is whatever the appearance was when
/// the image was made, and that is not the appearance it is shown in.
private struct HelmIconGlyph: View {
    let image: NSImage
    let neutral: Bool

    var body: some View {
        if neutral {
            Image(nsImage: image)
                .renderingMode(.template)
                .foregroundStyle(.primary)
        } else {
            Image(nsImage: image)
        }
    }
}
