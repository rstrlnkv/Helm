import SwiftUI

/// One button in a row of choices. Used by the size picker, which is three of
/// them.
///
/// Written when the shape picker was a row of swatches too and the two
/// disagreed about how much of a row a choice deserves — 80 pt against 26.
/// The shape is a pop-up menu now, so this has one caller; kept as its own
/// type because three letters in a row is still a control with a state, and
/// the alternative is that state spelled out inline three times.
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

/// The menu-bar shape, as a pop-up menu — the control macOS uses for a choice
/// between named things, and the one the appearance row beside it already is.
///
/// It was six swatches in a row. Six is where a row of swatches stops working:
/// each one shrinks to hold the row, and what a swatch is *for* is being big
/// enough to recognise. A menu gives every shape its full name and a glyph at
/// the size it is drawn in the bar, and gives the row back its height.
///
/// `selection` is a `MenuBarIconStyle` rawValue. Shared by the global menu-bar
/// settings and any module that offers its own icon — Keep Awake's
/// active-state shape, which had no label at all until this carried one.
public struct IconShapePicker: View {
    @Binding private var selection: String
    private let title: String
    private let tintToken: String

    public init(selection: Binding<String>,
                title: String = L("Icon shape"),
                tintToken: String = "primary") {
        self._selection = selection
        self.title = title
        self.tintToken = tintToken
    }

    /// Whether the glyph should follow the window's appearance rather than
    /// carry a colour of its own.
    private var neutral: Bool { tintToken == "primary" }

    public var body: some View {
        Picker(title, selection: $selection) {
            ForEach(MenuBarIconStyle.allCases, id: \.rawValue) { style in
                // Glyph and name, not one or the other: the name is what a
                // menu is good at and the glyph is what the setting is about.
                //
                // A neutral glyph is drawn white and rendered as a template so
                // its colour comes from the menu at draw time. Baking
                // `labelColor` in could not work: `MenuBarIcon` draws with
                // `lockFocus`, which resolves a dynamic colour once against
                // whatever appearance happened to be current — in a light
                // window that produced white on white.
                HelmIconGlyph(image: MenuBarIcon.make(style: style, size: .small,
                                                      tintToken: neutral ? nil : tintToken),
                              neutral: neutral)
                Text(style.label)
            }
        }
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
