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
        //
        // The row of pictures itself is `HelmChoiceCards`, which is where the
        // ring, the hairline and the label's weight now live — this file kept
        // its own copy of all three while the VPN page drew the same control
        // one size and one radius away.
        LabeledContent(title) {
            HelmChoiceCards(selection: $selection,
                            items: Self.order.map {
                                .init(id: $0, label: AppearanceNames.of($0),
                                      preview: AppearanceThumbnail(mode: $0))
                            })
        }
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
                HelmWallpaper(dark: dark)

                // The window, offset down and right so the wallpaper shows on
                // two sides — the same asymmetry the system's own thumbnail has.
                // Padded on two edges only, so it always runs exactly to the
                // right and bottom of the frame.
                //
                // **Two tones, not one**: the sidebar and what it opens. The
                // mockup draws them (measured `#E1E7F7` against `#FFFEFF`
                // light, `#494E5C` against `#383838` dark), and at 74 pt they
                // are what makes the picture read as *this* app's window
                // rather than as a plain rectangle — Helm has a sidebar on
                // every screen a person will see after choosing.
                RoundedRectangle(cornerRadius: w * 0.068, style: .continuous)
                    .fill(dark ? Color(white: 0.22) : Color(white: 1.0))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(dark ? Color(red: 0.286, green: 0.306, blue: 0.361)
                                       : Color(red: 0.882, green: 0.906, blue: 0.969))
                            .frame(width: w * 0.36)
                            .clipShape(
                                .rect(topLeadingRadius: w * 0.068,
                                      bottomLeadingRadius: w * 0.068,
                                      bottomTrailingRadius: 0, topTrailingRadius: 0,
                                      style: .continuous)
                            )
                    }
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
