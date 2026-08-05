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

    private var current: MenuBarIconStyle { MenuBarIconStyle(stored: selection) }

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
        // A real button, not a tap gesture. The comment here used to say
        // exactly that — "a gesture carries no button trait, takes no focus and
        // cannot be reached from the keyboard" — above a line that was still
        // `.onTapGesture`; only the VoiceOver half had been added, which is the
        // loud half, and Full Keyboard Access still skipped every swatch. So
        // the menu-bar icon could not be chosen without a mouse.
        //
        // `.plain` keeps the drawing entirely ours: the fill, border and glyph
        // below are unchanged, and the button contributes focus, the button
        // trait and activation by Space and Return.
        return Button {
            selection = s.rawValue
        } label: {
            // A neutral glyph is drawn white and rendered as a template, so its
            // colour comes from `foregroundStyle` at draw time. Baking
            // `labelColor` into the bitmap could not work: `MenuBarIcon` draws with
            // `lockFocus`, which resolves the dynamic colour once against whatever
            // `NSAppearance.current` happened to be — and in a light window that
            // produced white glyphs on a white swatch.
            // The shape swatch draws at the largest size Helm offers, which is
            // not the size the person picked — this picker is about the shape.
            HelmIconGlyph(image: MenuBarIcon.make(style: s, size: .small,
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
        }
        .buttonStyle(.plain)
        .help(s.label)
        // The button trait comes with `Button`; this is the part it cannot know.
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel(s.label)
    }
}

/// Size picker that renders the given shape at each real point size, so the
/// preview is the actual on-screen result rather than an abstract label; the
/// selected size's localized name is shown once below the row. `selection` is a
/// `MenuBarIconSize` rawValue.
///
/// Three letters, no drawings.
///
/// It used to draw the glyph at each of the five sizes, which sounds like the
/// honest way to show a size and is not: the swatches are 48 pt tall and the
/// difference between the choices is 2 pt, so the row spent most of its height
/// saying nothing and the thing it was meant to show was the one part too
/// small to see. The name under it — «Medium» — did the work, and it is
/// shorter as a letter.
public struct IconSizePicker: View {
    @Binding private var selection: String

    public init(selection: Binding<String>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(MenuBarIconSize.allCases, id: \.rawValue) { size in
                Button(size.label) { selection = size.rawValue }
                    .buttonStyle(.borderless)
                    .frame(width: 34, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selection == size.rawValue
                                  ? Color.accentColor.opacity(0.9)
                                  : HelmSurface.wellFill))
                    .foregroundStyle(selection == size.rawValue ? Color.white : Color.primary)
                    .accessibilityLabel(size.label)
                    .accessibilityAddTraits(selection == size.rawValue ? [.isSelected] : [])
            }
        }
        .animation(HelmMotion.interface, value: selection)
    }
}

/// A menu-bar glyph shown inside the app rather than in the bar.
///
/// A neutral glyph is drawn white and rendered as a template, so its colour
/// comes from `foregroundStyle` at draw time. Baking `labelColor` into the
/// bitmap could not work: `MenuBarIcon` draws with `lockFocus`, which resolves
/// the dynamic colour once against whatever `NSAppearance.current` happened to
/// be — and in a light window that produced white glyphs on a white swatch.
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
