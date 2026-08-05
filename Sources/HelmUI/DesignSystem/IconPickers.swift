import SwiftUI

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
    private let size: MenuBarIconSize

    /// `size` is a `MenuBarIconSize` rawValue. The pop-up draws each shape at
    /// the size that is actually chosen, which makes it the page's one live
    /// preview of the icon: the size row below shows three letters and no
    /// picture, so without this nothing on the page ever shows the icon as it
    /// will appear in the bar.
    public init(selection: Binding<String>,
                title: String = L("Icon shape"),
                tintToken: String = "primary",
                size: String = MenuBarIconSize.small.rawValue) {
        self._selection = selection
        self.title = title
        self.tintToken = tintToken
        self.size = MenuBarIconSize(stored: size)
    }

    /// Whether the glyph should follow the window's appearance rather than
    /// carry a colour of its own.
    private var neutral: Bool { tintToken == "primary" }

    /// The glyph with room after it, baked into the image.
    ///
    /// A pop-up button is an `NSMenuItem` drawn by AppKit, which lays out the
    /// image and the title itself and ignores what a SwiftUI `Label` asks for
    /// between them — padding on the `Text` changed nothing, and the closed
    /// button read «○Кольцо». So the space is part of the picture.
    ///
    /// **Four, not six, and it is a compromise between two places that get
    /// different treatment.** AppKit gives an *open* menu's items a gap of its
    /// own — measured at 2x, about 9 pt — and gives the closed button none. One
    /// image serves both, so six made the button right and the list read at 15.
    /// Four leaves the button with a gap and the list a few points loose, and
    /// the button is the one on screen all the time.
    ///
    /// The way out of the compromise is a hand-built `Menu` whose closed label
    /// is ours and whose items are plain — and it costs the selection tick,
    /// which a `Picker` draws and a `Menu` of buttons does not.
    private func spaced(_ image: NSImage) -> NSImage {
        let gap: CGFloat = 4
        let out = NSImage(size: NSSize(width: image.size.width + gap, height: image.size.height))
        out.lockFocus()
        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        out.unlockFocus()
        out.isTemplate = image.isTemplate
        return out
    }

    public var body: some View {
        Picker(title, selection: $selection) {
            ForEach(MenuBarIconStyle.allCases, id: \.rawValue) { style in
                // One `Label`, not a glyph and a `Text` side by side. Two
                // views inside a `Picker`'s `ForEach` are two menu items, so
                // every shape appeared twice — once as a picture and once as a
                // name, each with its own tick.
                //
                // A neutral glyph is drawn white and rendered as a template so
                // its colour comes from the menu at draw time. Baking
                // `labelColor` in could not work: `MenuBarIcon` draws with
                // `lockFocus`, which resolves a dynamic colour once against
                // whatever appearance happened to be current — in a light
                // window that produced white on white.
                Label {
                    Text(style.label)
                } icon: {
                    HelmIconGlyph(image: spaced(MenuBarIcon.make(style: style, size: size,
                                                                 tintToken: neutral ? nil : tintToken)),
                                  neutral: neutral)
                }
                .tag(style.rawValue)
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
/// shorter as a letter. What shows the size now is the shape pop-up above,
/// which draws its glyph at whatever this is set to.
///
/// **The system's segmented control, not three chips of our own.** The chips
/// were 34×26 with an accent fill and white on top, two rows below a segmented
/// `Picker` that says «chosen» with a raised grey knob — one card, one
/// question asked twice in two visual languages. Measured, the chips also lost
/// on their own terms: 42.5 pt of row against the segmented control's 41.0,
/// a track at 1.08:1 against the card where the system's reads 1.15:1, and
/// white on that accent fill at **3.22:1** — the one piece of text on the page
/// under the 4.5:1 floor every colour in `HelmSurfaces` was solved against.
public struct IconSizePicker: View {
    @Binding private var selection: String

    public init(selection: Binding<String>) {
        self._selection = selection
    }

    public var body: some View {
        // Named even though the label is hidden: the row's `LabeledContent`
        // titles it on screen, and VoiceOver reads the control itself.
        Picker(L("Icon size"), selection: $selection) {
            ForEach(MenuBarIconSize.allCases, id: \.rawValue) { size in
                Text(size.label).tag(size.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // Or it stretches to the row's full width, where the segmented control
        // two rows above hugs its three words.
        .fixedSize()
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
