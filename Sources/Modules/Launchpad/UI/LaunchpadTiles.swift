import SwiftUI
import HelmUI
import Module_Launchpad_Engine

/// The sizes the window and the page draw at, said once. Content sizes, not the kit's: an icon is as big as the
/// system draws an app icon in a grid, whatever the spacing ladder says.
enum LaunchpadMetrics {
    /// An app's icon in the window.
    static let windowIcon: CGFloat = 80
    /// The narrowest a tile may be; the grid fits as many as the width holds. Against the widest word a language cannot
    /// break, at the label font (`.subheadline`, NSString width): German "Datenträgerverwaltung" 120.5 pt, "Systemeinstellungen"
    /// 108.7 pt. The label gets 124 pt, and the tile its own padding (`s2` a side) more: 132. Longer names wrap at their
    /// spaces and hyphens, or are cut, and the tile's `.help` says them whole.
    static let tileMinimum: CGFloat = 132
    /// An icon beside a name in the settings page's list of hidden apps.
    static let hiddenIcon: CGFloat = 28
    /// A tile's height: the icon, the gap, two lines of label (`.subheadline` leads at 17 pt) and the padding above and below.
    static let cellHeight: CGFloat = windowIcon + HelmSpace.s3 + 2 * 17 + 2 * HelmSpace.s3
    /// The window's margin at each side, as a share of its width.
    static let sideMargin: CGFloat = 0.08
    static let searchTop: CGFloat = 28
    static let searchHeight: CGFloat = 32
    static let searchWidth: CGFloat = 280
    /// Between the search field and the grid.
    static let gridGap: CGFloat = 36
    /// Kept under the grid for the page dots.
    static let dotsRoom: CGFloat = 64
    static let dotsBottom: CGFloat = 28
    /// The window's content before it settles at its size, as a factor.
    static let zoomFrom: CGFloat = 1.08
    /// An icon at the press that opens it.
    static let popScale: CGFloat = 1.18
}

/// The press, the pointer and the arrow keys' choice, as the kit's two row washes.
private struct TileStyle: ButtonStyle {
    let hovering: Bool
    let selected: Bool
    let glowSize: CGSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                    .fill(configuration.isPressed || selected ? HelmSurface.rowSelection : hovering ? HelmSurface.rowHover : Color.clear)
                    .colorEffect(LaunchpadGlow.shader(size: glowSize), isEnabled: selected && LaunchpadGlow.on)
            )
            .contentShape(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous))
    }
}

/// One tile: an icon over a name, pressed to open. Hiding is the context menu's and VoiceOver's action. White ink: it
/// is drawn on the window's blur, in the dark appearance.
struct LaunchpadTile<Mark: View>: View {
    let name: String
    let accessibleName: String
    let iconSize: CGFloat
    let selected: Bool
    let open: () -> Void
    let hide: (() -> Void)?
    /// The tile's cell, for the glow's light to be placed in it.
    var glowSize = CGSize(width: 1, height: 1)
    /// The app opening: its icon swells, then the window goes.
    var popped = false
    @ViewBuilder let mark: Mark
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: HelmSpace.s3) {
                mark
                    .frame(width: iconSize, height: iconSize)
                    .scaleEffect(popped && !HelmMotion.reduceMotion ? LaunchpadMetrics.popScale : 1)
                    .animation(HelmMotion.interface, value: popped)
                    .accessibilityHidden(true)
                Text(name)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(Color.white)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, HelmSpace.s3)
            .padding(.horizontal, HelmSpace.s2)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TileStyle(hovering: hovering, selected: selected, glowSize: glowSize))
        .help(name)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibleName)
        .contextMenu {
            if let hide { Button(LpStr.hide, action: hide) }
        }
        .accessibilityActions {
            if let hide { Button(LpStr.hide, action: hide) }
        }
    }
}

extension LaunchpadTile where Mark == Image {
    /// An application's tile; the icon is the caller's, from the window's own cache.
    init(app: CatalogApp, icon: NSImage, iconSize: CGFloat, selected: Bool, glowSize: CGSize, popped: Bool,
         open: @escaping () -> Void, hide: @escaping () -> Void) {
        self.init(name: app.name, accessibleName: app.name, iconSize: iconSize, selected: selected, open: open, hide: hide,
                  glowSize: glowSize, popped: popped) {
            Image(nsImage: icon).resizable()
        }
    }
}

/// A saved folder: a well with up to four of its apps' icons, no border.
struct LaunchpadFolderMark: View {
    let icons: [NSImage]
    let size: CGFloat

    var body: some View {
        let inset = HelmSpace.s3
        let mini = (size - inset * 3) / 2
        ZStack {
            RoundedRectangle(cornerRadius: HelmRadius.frame, style: .continuous).fill(Color.white.opacity(0.18))
            VStack(spacing: inset) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: inset) {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            if index < icons.count {
                                Image(nsImage: icons[index]).resizable()
                                    .frame(width: mini, height: mini)
                            } else {
                                Color.clear.frame(width: mini, height: mini)
                            }
                        }
                    }
                }
            }
        }
    }
}
