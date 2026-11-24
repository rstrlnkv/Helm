import SwiftUI
import HelmRuntime

/// Light, dark or automatic — as three pictures, the way System Settings asks
/// the same question.
///
/// This is the one setting whose answer *is* an appearance, and a picture says
/// at a glance what «Auto» takes a sentence to explain; macOS asks it this way
/// on its own Appearance pane. Drawn in Helm's own hand, since the system's
/// thumbnails are private assets: a wallpaper and a window with its three
/// lights, and automatic as the two split down the middle, as macOS does.
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
        // `LabeledContent`, with the label on the first baseline: beside a
        // 62 pt block of pictures with names under them, a label at its middle
        // reads as attached to nothing, while on the first line it introduces
        // what follows. The row of pictures is `HelmChoiceCards`.
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
        case .system: L(.auto)
        case .light: L(.light)
        case .dark: L(.dark)
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
                // two sides, as in the system's thumbnail, and padded on two
                // edges only so it runs to the right and bottom of the frame.
                //
                // Two tones, the sidebar and what it opens, from the mockup:
                // at 74 pt they make the picture read as this app's window
                // rather than a plain rectangle.
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
                        // nothing else: a selected row at this size reads as the
                        // window's content rather than one item in it.
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
