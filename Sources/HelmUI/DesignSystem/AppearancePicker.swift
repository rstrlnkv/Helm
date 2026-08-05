import SwiftUI
import HelmRuntime

/// Light, dark or automatic — as three pictures, the way System Settings asks
/// the same question.
///
/// It was a pop-up menu of three words. The words are accurate and they are
/// not what anybody is choosing between: this is the one setting in Helm whose
/// answer *is* an appearance, and a picture of it says in one glance what
/// «Auto» takes a sentence to explain. macOS asks it this way on its own
/// Appearance pane, so a person arriving here has already answered it once in
/// this shape.
///
/// **Drawn rather than borrowed.** The system's thumbnails are private assets
/// of System Settings; these are the same idea in Helm's own hand — a
/// wallpaper and a window with its three lights — and the automatic one is the
/// two of them split down the middle, which is the convention macOS itself
/// uses for that case.
public struct AppearancePicker: View {
    @Binding private var selection: AppAppearance
    private let title: String

    public init(selection: Binding<AppAppearance>, title: String) {
        self._selection = selection
        self.title = title
    }

    /// Light, dark, then automatic. Not `allCases`, which is declared
    /// `system, light, dark` — the enum's order is about which one is the
    /// fallback, and this row is about which one a person is looking for.
    private static let order: [AppAppearance] = [.light, .dark, .system]

    public var body: some View {
        // `LabeledContent`, and the label stays on the first baseline.
        //
        // It was hand-built for a while, to centre the label against the whole
        // block the way `SidebarComposerRow` centres its button. Measured, that
        // was the consistent choice — 22 pt off against every other row in the
        // card — and looked at, it was not: a button is one small thing beside
        // a label and belongs level with it, while this is a 62 pt block of
        // pictures with names under them, and a label floating at its middle
        // reads as attached to nothing. On the first line it introduces what
        // follows, which is what the pictures are arranged as.
        LabeledContent(title) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Self.order, id: \.self) { mode in
                    swatch(mode)
                }
            }
        }
    }

    private func swatch(_ mode: AppAppearance) -> some View {
        let selected = selection == mode
        return Button {
            selection = mode
        } label: {
            VStack(spacing: 6) {
                AppearanceThumbnail(mode: mode)
                    .frame(width: 74, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    // The accent ring on the chosen one; a hairline on all
                    // three so the unchosen ones have an edge at all.
                    //
                    // The thumbnails bake literal colours, and the one that
                    // matches the window's own appearance disappears into the
                    // card behind it: in light mode the light thumbnail's
                    // window body and the card measured the *same pixel value*,
                    // 1.00:1, leaving a pale blue L with three lights floating
                    // in nothing. Dark against dark measured 1.12:1 — the same
                    // failure, symmetric. A 0.5 pt hairline is not a card
                    // border; this is a picture of a window, and the ring is
                    // still what says which one is chosen.
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : HelmSurface.hairline,
                                          lineWidth: selected ? 2.5 : 0.5)
                    }
                Text(AppearanceNames.of(mode))
                    .font(.caption)
                    // Weight, not colour: the ring already says which one is
                    // chosen, and a second colour saying it again is what makes
                    // the two that are not chosen look disabled.
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? Color.primary : HelmText.quiet)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppearanceNames.of(mode))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The names, here rather than in the app, because the picker that draws them
/// lives here too.
enum AppearanceNames {
    static func of(_ mode: AppAppearance) -> String {
        switch mode {
        case .system: L("Auto")
        case .light: L("Light")
        case .dark: L("Dark")
        }
    }
}

/// A Mac, small: wallpaper, a window, three lights.
///
/// Everything is a fraction of the frame rather than a point size, so the same
/// drawing serves the 74 pt swatch and anything larger that wants it later.
private struct AppearanceThumbnail: View {
    let mode: AppAppearance

    var body: some View {
        switch mode {
        case .light: face(dark: false)
        case .dark: face(dark: true)
        case .system:
            // The two halves of one picture, which is how macOS draws this
            // case: the dark one masked to the right of the light one, so the
            // window and its row line up across the seam.
            ZStack {
                face(dark: false)
                face(dark: true)
                    .mask {
                        HStack(spacing: 0) {
                            Color.clear
                            Color.black
                        }
                    }
            }
        }
    }

    private func face(dark: Bool) -> some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: dark
                               ? [Color(red: 0.16, green: 0.18, blue: 0.34),
                                  Color(red: 0.07, green: 0.08, blue: 0.16)]
                               : [Color(red: 0.78, green: 0.84, blue: 0.94),
                                  Color(red: 0.55, green: 0.66, blue: 0.86)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                // The window, offset down and right so the wallpaper shows on
                // two sides — the same asymmetry the system's own thumbnail has.
                // Padded on two edges only, so it always runs exactly to the
                // right and bottom of the frame.
                RoundedRectangle(cornerRadius: w * 0.068, style: .continuous)
                    .fill(dark ? Color(white: 0.17) : Color(white: 0.97))
                    .overlay(alignment: .topLeading) {
                        // Three lights in the corner of the title bar, and
                        // nothing else. There was a selected row under them in
                        // the accent colour; at 74 pt it was a blue bar with
                        // no list for it to be a row of, and it read as the
                        // window's content rather than as one item in it.
                        HStack(spacing: w * 0.045) {
                            ForEach([Color(red: 0.99, green: 0.37, blue: 0.34),
                                     Color(red: 0.99, green: 0.74, blue: 0.18),
                                     Color(red: 0.24, green: 0.79, blue: 0.33)], id: \.self) { tint in
                                Circle().fill(tint).frame(width: h * 0.11, height: h * 0.11)
                            }
                        }
                        .padding(.leading, w * 0.04)
                        .padding(.top, h * 0.065)
                    }
                    .padding(.leading, w * 0.135)
                    .padding(.top, h * 0.152)
            }
        }
    }
}
