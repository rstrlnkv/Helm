import SwiftUI

/// One button in a row of choices, for the two pickers that sit one above the
/// other in Settings.
///
/// They were two classes of control doing one job: the shape was six 50 pt
/// boxes with a name underneath, the size three 24 pt buttons pushed to the
/// right margin — measured on the page, 80 pt of row against 24. Adjacent rows
/// that ask the same question ("pick one of these") and answer at a third of
/// each other's weight read as two different kinds of setting.
///
/// So both are this: a 26 pt tall button, filled when chosen. The glyph or the
/// letter is what differs, which is the only thing that should.
struct HelmChoiceButton<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        // A real button, not a tap gesture. The comment here used to say
        // exactly that — "a gesture carries no button trait, takes no focus and
        // cannot be reached from the keyboard" — above a line that was still
        // `.onTapGesture`; only the VoiceOver half had been added, which is the
        // loud half, and Full Keyboard Access still skipped every swatch. So
        // the menu-bar icon could not be chosen without a mouse.
        //
        // `.plain` keeps the drawing entirely ours, and the button still
        // contributes focus, the button trait and activation by Space and
        // Return.
        Button(action: action) {
            label()
                .frame(width: 34, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor : HelmSurface.wellFill))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        // The button trait comes with `Button`; this is the part it cannot know.
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Six shapes in a row, each drawn as itself. `selection` is a
/// `MenuBarIconStyle` rawValue. Shared by the global menu-bar settings and any
/// module that offers its own icon (e.g. Keep Awake's active-state icon).
///
/// The name of the chosen shape used to sit on a line of its own under the
/// row. It cost the same height as the swatches to say what the highlighted
/// swatch already said, and with six shapes it read as an orphan under the
/// middle of a row it did not belong to. It is the tooltip and the
/// accessibility label now, which is where a name for a picture belongs.
public struct IconShapePicker: View {
    @Binding private var selection: String
    private let tintToken: String

    public init(selection: Binding<String>, tintToken: String = "primary") {
        self._selection = selection
        self.tintToken = tintToken
    }

    /// Whether the glyph should follow the window's appearance rather than
    /// carry a colour of its own.
    private var neutral: Bool { tintToken == "primary" }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(MenuBarIconStyle.allCases, id: \.rawValue) { style in
                let selected = selection == style.rawValue
                HelmChoiceButton(selected: selected) {
                    selection = style.rawValue
                } label: {
                    // A neutral glyph is drawn white and rendered as a
                    // template, so its colour comes from `foregroundStyle` at
                    // draw time. Baking `labelColor` into the bitmap could not
                    // work: `MenuBarIcon` draws with `lockFocus`, which
                    // resolves the dynamic colour once against whatever
                    // `NSAppearance.current` happened to be — and in a light
                    // window that produced white glyphs on a white swatch.
                    //
                    // Drawn at the largest size Helm offers, which is not the
                    // size the person picked: this picker is about the shape.
                    HelmIconGlyph(image: MenuBarIcon.make(style: style, size: .small,
                                                          tintToken: neutral ? nil : tintToken),
                                  neutral: neutral)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .help(style.label)
                .accessibilityLabel(style.label)
            }
        }
        .animation(HelmMotion.interface, value: selection)
    }
}

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
                let selected = selection == size.rawValue
                HelmChoiceButton(selected: selected) {
                    selection = size.rawValue
                } label: {
                    Text(size.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .accessibilityLabel(size.label)
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
        } else {
            Image(nsImage: image)
        }
    }
}
