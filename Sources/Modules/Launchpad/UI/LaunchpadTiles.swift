import SwiftUI
import HelmUI
import Module_Launchpad_Engine

/// The sizes the page draws at, said once. Content sizes, not the kit's: an icon is as big as the
/// system draws an app icon in a grid, whatever the spacing ladder says.
enum LaunchpadMetrics {
    static let icon: CGFloat = 56
    /// The narrowest a tile may be; the grid fits as many as the width holds. Against the widest word a language cannot
    /// break, at the label font (`.subheadline`, NSString width): German "Datenträgerverwaltung" 120.5 pt, "Systemeinstellungen"
    /// 108.7 pt. The label gets 124 pt, and the tile its own padding (`s2` a side) more: 132, which is four columns in the
    /// settings column. Longer names wrap at their spaces and hyphens, or are cut, and the tile's `.help` says them whole.
    static let tileMinimum: CGFloat = 132
    static let hiddenIcon: CGFloat = 28
    /// A folder's popover: three tiles across (their gaps and the popover's own padding with them), and at most this tall before it scrolls.
    static let popoverWidth: CGFloat = tileMinimum * 3 + HelmSpace.s5 * 4
    static let popoverMaxHeight: CGFloat = 320
    static var columns: [GridItem] {
        [GridItem(.adaptive(minimum: tileMinimum), spacing: HelmSpace.s5, alignment: .top)]
    }
}

/// The press and the pointer, as the kit's two row washes.
private struct TileStyle: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                    .fill(configuration.isPressed ? HelmSurface.rowSelection : hovering ? HelmSurface.rowHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous))
    }
}

/// One tile: an icon over a name, pressed to open. Hiding is the context menu's and VoiceOver's action.
struct LaunchpadTile<Mark: View>: View {
    let name: String
    let accessibleName: String
    let open: () -> Void
    let hide: (() -> Void)?
    @ViewBuilder let mark: Mark
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: HelmSpace.s3) {
                mark
                    .frame(width: LaunchpadMetrics.icon, height: LaunchpadMetrics.icon)
                    .accessibilityHidden(true)
                Text(name)
                    .font(HelmText.rowDetail)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, HelmSpace.s3)
            .padding(.horizontal, HelmSpace.s2)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TileStyle(hovering: hovering))
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
    /// An application's tile.
    init(app: CatalogApp, open: @escaping () -> Void, hide: @escaping () -> Void) {
        self.init(name: app.name, accessibleName: app.name, open: open, hide: hide) {
            Image(nsImage: AppInfo.icon(forFile: app.path)).resizable()
        }
    }
}

/// A saved folder: a well with up to four of its apps' icons, no border. Pressed, it opens its popover.
struct LaunchpadFolderMark: View {
    let apps: [CatalogApp]

    var body: some View {
        let inset = HelmSpace.s3
        let mini = (LaunchpadMetrics.icon - inset * 3) / 2
        ZStack {
            RoundedRectangle(cornerRadius: HelmRadius.frame, style: .continuous).fill(HelmSurface.wellFill)
            VStack(spacing: inset) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: inset) {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            if index < apps.count {
                                Image(nsImage: AppInfo.icon(forFile: apps[index].path)).resizable()
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
