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
                .foregroundStyle(.secondary)
                .animation(HelmMotion.interface, value: selection)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func swatch(_ s: MenuBarIconStyle) -> some View {
        let selected = selection == s.rawValue
        return Image(nsImage: RingIcon.make(style: s, size: .medium, tintToken: tintToken))
            .frame(width: 26, height: 26)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .help(s.label)
            .onTapGesture { selection = s.rawValue }
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
                .foregroundStyle(.secondary)
                .animation(HelmMotion.interface, value: selection)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func swatch(_ sz: MenuBarIconSize) -> some View {
        let selected = selection == sz.rawValue
        // No .resizable(): the image draws at its natural point size, so the
        // sizes differ visibly across the row.
        return Image(nsImage: RingIcon.make(style: style, size: sz, tintToken: tintToken))
            .frame(width: 28, height: 28)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .help(sz.label)
            .onTapGesture { selection = sz.rawValue }
    }
}
