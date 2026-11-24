import SwiftUI

/// The menu-bar shape, as a pop-up menu — the control macOS uses for a choice
/// between named things, and the one the appearance row beside it already is.
///
/// A menu rather than a row of swatches: six swatches shrink below the size
/// that makes a shape recognisable, and a menu gives every shape its name and a
/// glyph at the size it is drawn in the bar.
///
/// `selection` is a `MenuBarIconStyle` rawValue. Shared by the global menu-bar
/// settings and any module that offers its own icon, such as Keep Awake's
/// active-state shape.
public struct IconShapePicker: View {
    @Binding private var selection: String
    private let title: String
    private let tintToken: String
    private let size: MenuBarIconSize

    /// `size` is a `MenuBarIconSize` rawValue. Each shape is drawn at the chosen
    /// size, which makes this the page's one live preview of the icon as it
    /// will appear in the bar.
    public init(selection: Binding<String>,
                title: String? = nil,
                tintToken: String = "primary",
                size: String = MenuBarIconSize.small.rawValue) {
        self._selection = selection
        self.title = title ?? L(.iconShape)
        self.tintToken = tintToken
        self.size = MenuBarIconSize(stored: size)
    }

    /// Whether the glyph should follow the window's appearance rather than
    /// carry a colour of its own.
    private var neutral: Bool { tintToken == "primary" }

    /// The glyph with room after it, baked into the image.
    ///
    /// A pop-up button is an `NSMenuItem` laid out by AppKit, which ignores the
    /// spacing a SwiftUI `Label` asks for, so the space is part of the picture.
    ///
    /// Four points is a compromise: AppKit gives an open menu's items a gap of
    /// its own and the closed button none, and one image serves both. Four
    /// gives the button, which is always on screen, a gap and leaves the list a
    /// little loose. A hand-built `Menu` would escape it at the cost of the
    /// selection tick a `Picker` draws.
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
                // One `Label`, not a glyph and a `Text` side by side: two views
                // inside a `Picker`'s `ForEach` are two menu items. A neutral
                // glyph is a template so the menu colours it (`HelmIconGlyph`).
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

/// `MenuBarIconSize` rawValue, as three letters and no drawings: the sizes
/// differ by 2 pt, too little to see in a swatch. The shape pop-up above draws
/// its glyph at the chosen size, which shows it.
///
/// The system's segmented control, not chips of our own: one card should not
/// ask «chosen» in two visual languages, and white on an accent fill falls
/// under the 4.5:1 floor `HelmText` and `HelmSignal` are solved against.
public struct IconSizePicker: View {
    @Binding private var selection: String

    public init(selection: Binding<String>) {
        self._selection = selection
    }

    public var body: some View {
        // Named even though the label is hidden: the row's `LabeledContent`
        // titles it on screen, and VoiceOver reads the control itself.
        Picker(L(.iconSize), selection: $selection) {
            ForEach(MenuBarIconSize.allCases, id: \.rawValue) { size in
                Text(size.label).tag(size.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // Or it stretches to the row's full width.
        .fixedSize()
    }
}

/// A menu-bar glyph shown inside the app rather than in the bar.
///
/// A neutral glyph is drawn white and rendered as a template, so its colour
/// comes from `foregroundStyle` at draw time. `MenuBarIcon` draws with
/// `lockFocus`, which would bake `labelColor` against whatever appearance was
/// current, white on white in a light window.
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
