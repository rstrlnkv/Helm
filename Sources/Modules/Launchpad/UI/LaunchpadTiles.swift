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
    /// The Dock helper's icon on the settings page: big enough to take hold of and drag.
    static let dockIcon: CGFloat = 40
    /// What a tile holds besides its icon: the gap, two lines of label (`.subheadline` leads at 17 pt) and the padding above and below. Fixed by the fonts.
    static let cellChrome: CGFloat = HelmSpace.s3 + 2 * 17 + 2 * HelmSpace.s3
    /// A tile's height: the icon plus `cellChrome`.
    static func cellHeight(icon: CGFloat) -> CGFloat { icon + cellChrome }
    /// The smallest an icon shrinks to when the grid asked for does not fit.
    static let iconFloor: CGFloat = 24
    /// A tile's padding at each side, which the grid's fit counts too.
    static let tileSidePadding: CGFloat = HelmSpace.s2
    /// The window's margin at each side, as a share of its width.
    static let sideMargin: CGFloat = 0.08
    static let searchTop: CGFloat = 28
    /// The kit's header-control height, the switch's.
    static let searchHeight: CGFloat = 36
    static let searchWidth: CGFloat = 280
    /// What the switch ("Apps", "Categories") is given at the left of the search field: the strip is 196 pt in the widest pair of the
    /// eight languages (Russian, "Приложения" and "Категории"), plus a gap of 20 pt that keeps it from the field. Measured by `fittingSize`
    /// on 2026-11-21 in the text style, which is what the window always draws (it sets no `helmHeaderChoices`).
    /// `TheSwitchFitsItsRoomInEveryLanguageTests` measures it again.
    static let switchRoom: CGFloat = 216
    /// The switch's own height (the kit's segmented tabs, a 36 pt strip), centred on the search field's.
    static let switchHeight: CGFloat = 36
    /// Between the search field and the grid. 32 is no `HelmSpace` step (s7 is 28, s8 is 40): it keeps the grid's top at 96 with the 36 pt field.
    static let gridGap: CGFloat = 32
    /// The fill of a folder's, a category's and the Hidden block's well, and of its cluster.
    static let wellFill = Color.white.opacity(0.18)
    /// The search field's capsule.
    static let fieldFill = Color.white.opacity(0.14)
    /// The search field's placeholder (about 5:1 on the capsule over a dark wallpaper, measured offscreen); the glyph and the empty Hidden card's message are `secondaryInk`.
    static let placeholderInk = Color.white.opacity(0.75)
    /// Secondary white ink on the window's blur: the search glyph, the Hidden card's empty message.
    static let secondaryInk = Color.white.opacity(0.7)
    /// The dimming behind a folder's card (black).
    static let scrim = 0.35
    /// An unlit page dot's white.
    static let unlitDot = 0.35
    /// A folder or category well's side as a share of its frame, so it reads as big as an app icon's visible body; its corner is `wellCorner` of that side.
    static let wellShare: CGFloat = 0.85
    static let wellCorner: CGFloat = 0.225
    /// The keyboard choice's ring when the glow is off (Reduce Motion, Increase Contrast): measured offscreen by the designer at 4.68:1 against the tile wash and 6.56:1 against the ground (a dark stand-in), so chosen is not pressed.
    static let selectionRing = Color.white.opacity(0.6)
    /// Kept under the grid for the page dots.
    static let dotsRoom: CGFloat = 64
    static let dotsBottom: CGFloat = 28
    /// The window's content before it settles at its size, as a factor.
    static let zoomFrom: CGFloat = 1.08
    /// From a cell's top to its icon's top.
    static let iconTop: CGFloat = HelmSpace.s3
    /// The tile carried by the pointer.
    static let liftScale: CGFloat = 1.08
    /// An icon at the press that opens it.
    static let popScale: CGFloat = 1.18
}

/// The press, the pointer and the arrow keys' choice, as the kit's two row washes.
private struct TileStyle: ButtonStyle {
    let hovering: Bool
    let selected: Bool
    /// Pressed by the window's own mouse routing (the panel takes the press before a button sees it), or a drop's target.
    let pressed: Bool
    let glowSize: CGSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                    .fill(configuration.isPressed || pressed || selected ? HelmSurface.rowSelection : hovering ? HelmSurface.rowHover : Color.clear)
                    .colorEffect(LaunchpadGlow.shader(size: glowSize), isEnabled: selected && LaunchpadGlow.on)
            )
            .overlay {
                if selected && !LaunchpadGlow.on {
                    RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous).strokeBorder(LaunchpadMetrics.selectionRing, lineWidth: 2)
                }
            }
            .animation(HelmMotion.wellFade, value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous))
    }
}

/// **The menu of an app, wherever it is drawn:** Hide, and "Move to category" with the app's own category as the undo on top
/// (disabled while the app is not moved) and every category under it, the one the app is in now checked. "Others" is last.
/// A VoiceOver custom action cannot be a submenu, and 29 of them would be noise: VoiceOver reaches Move through the
/// context menu (VO-Shift-M), and Hide stays an action as well, on the grid's and the cards' tiles. A category block's large
/// icons have neither for VoiceOver (the block tile has `hide: nil`, the menu is on the inner image): it reaches them through the card.
struct LaunchpadAppMenu: View {
    let app: CatalogApp
    let moved: LaunchpadCategoryTarget?
    let hide: () -> Void
    let move: (LaunchpadCategoryTarget?) -> Void

    /// Where the app is shown now: its move, else its own.
    static func effective(moved: LaunchpadCategoryTarget?, raw: String?) -> LaunchpadCategoryTarget {
        moved ?? LaunchpadCategoryTarget(raw: raw)
    }

    /// The undo row has something to undo only while the app is moved.
    static func canReturn(moved: LaunchpadCategoryTarget?) -> Bool { moved != nil }

    var body: some View {
        let effective = Self.effective(moved: moved, raw: app.category)
        Button(LpStr.hide, action: hide)
        Menu(LpStr.moveToCategory) {
            Button(LpStr.ownCategory) { move(nil) }.disabled(!Self.canReturn(moved: moved))
            Divider()
            ForEach(LaunchpadCategoryName.choices(), id: \.target) { choice in
                Toggle(choice.title, isOn: Binding(get: { choice.target == effective },
                                                   set: { _ in if choice.target != effective { move(choice.target) } }))
            }
        }
    }
}

/// What VoiceOver may do with a tile's place: each action is there only where the move exists (`LaunchpadScreenState.moves`), and
/// every one is the chord's own reorder, keyed by this tile.
struct LaunchpadTileMoves {
    var earlier: (() -> Void)?
    var later: (() -> Void)?
    var previousPage: (() -> Void)?
    var nextPage: (() -> Void)?
    var folderWithPrevious: (() -> Void)?
    var folderWithNext: (() -> Void)?
    var addToPreviousFolder: (() -> Void)?
    var addToNextFolder: (() -> Void)?
    var takeOut: (() -> Void)?
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
    var pressed = false
    /// A folder's other size, offered beside hide: its menu item's title and what it does.
    var resize: (title: String, action: () -> Void)?
    /// An app's menu (Hide and Move to category) in place of the bare Hide.
    var menu: LaunchpadAppMenu?
    /// The tile is in the Hidden card: its one action, from the menu and from VoiceOver, is Show (the `hide` closure), and it cannot be moved.
    var inHidden = false
    /// The tile's place by VoiceOver: nil where no reorder is allowed (a search, the category view, the Hidden card).
    var reorder: LaunchpadTileMoves?
    @ViewBuilder let mark: Mark
    @State private var hovering = false

    /// Whether the name has a space or a hyphen to wrap at.
    static func canBreak(_ name: String) -> Bool { name.contains { $0 == " " || $0 == "-" } }

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
                    // A name with no space or hyphen has no place to break: it takes one line and shrinks to fit (German "Festplattendienstprogramm"),
                    // since two lines would split it mid-word before the scale ever applied. `tileMinimum` stays.
                    .lineLimit(Self.canBreak(name) ? 2 : 1, reservesSpace: true)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, HelmSpace.s3)
            .padding(.horizontal, LaunchpadMetrics.tileSidePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(TileStyle(hovering: hovering, selected: selected, pressed: pressed, glowSize: glowSize))
        .help(name)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibleName)
        .contextMenu {
            if let menu { menu } else if let hide { Button(inHidden ? HelmWord.show : LpStr.hide, action: hide) }
            if let resize { Button(resize.title, action: resize.action) }
        }
        .accessibilityActions {
            if let hide { Button(inHidden ? HelmWord.show : LpStr.hide, action: hide) }
            if let resize { Button(resize.title, action: resize.action) }
            if let reorder { moveActions(reorder) }
        }
    }

    @ViewBuilder private func moveActions(_ moves: LaunchpadTileMoves) -> some View {
        if let action = moves.earlier { Button(LpStr.moveEarlier, action: action) }
        if let action = moves.later { Button(LpStr.moveLater, action: action) }
        if let action = moves.previousPage { Button(LpStr.moveToPreviousPage, action: action) }
        if let action = moves.nextPage { Button(LpStr.moveToNextPage, action: action) }
        if let action = moves.folderWithPrevious { Button(LpStr.makeFolderWithPrevious, action: action) }
        if let action = moves.folderWithNext { Button(LpStr.makeFolderWithNext, action: action) }
        if let action = moves.addToPreviousFolder { Button(LpStr.addToPreviousFolder, action: action) }
        if let action = moves.addToNextFolder { Button(LpStr.addToNextFolder, action: action) }
        if let action = moves.takeOut { Button(LpStr.takeOutOfFolder, action: action) }
    }
}

extension LaunchpadTile where Mark == Image {
    /// An application's tile; the icon is the caller's, from the window's own cache.
    init(app: CatalogApp, icon: NSImage, iconSize: CGFloat, selected: Bool, glowSize: CGSize, popped: Bool, pressed: Bool = false, inHidden: Bool = false,
         moved: LaunchpadCategoryTarget?, open: @escaping () -> Void, hide: @escaping () -> Void,
         move: @escaping (LaunchpadCategoryTarget?) -> Void, reorder: LaunchpadTileMoves? = nil) {
        self.init(name: app.name, accessibleName: app.name, iconSize: iconSize, selected: selected, open: open, hide: hide,
                  glowSize: glowSize, popped: popped, pressed: pressed,
                  menu: inHidden ? nil : LaunchpadAppMenu(app: app, moved: moved, hide: hide, move: move), inHidden: inHidden, reorder: reorder) {
            Image(nsImage: icon).resizable()
        }
    }
}

/// A saved folder: a well with up to nine of its apps' icons, three by three, no border. The icons and the room round them
/// follow the tile's size, like the icon does.
struct LaunchpadFolderMark: View {
    let icons: [NSImage]
    let size: CGFloat
    /// The apps past what the mark's cells show, as icons: the last cell holds up to four of them, two by two, tiny.
    var overflow: [NSImage] = []
    /// The icon (by index) a press is on, which takes the wash instead of the tile, and the one whose app is opening, which swells.
    var pressed: Int?
    var popped: Int?

    /// The well's side: an app icon's visible body is about this much of its frame, and the well is drawn as big, centred in the frame.
    static func well(_ size: CGFloat) -> CGFloat { size * LaunchpadMetrics.wellShare }
    /// From the frame's edge to the well's.
    static func inset(_ size: CGFloat) -> CGFloat { (size - well(size)) / 2 }
    static func pad(_ size: CGFloat) -> CGFloat { well(size) * 0.10 }
    static func gap(_ size: CGFloat) -> CGFloat { well(size) * 0.05 }
    static func mini(_ size: CGFloat) -> CGFloat { (well(size) - 2 * pad(size) - 2 * gap(size)) / 3 }

    /// Where icon `index` (0 to 8, reading order) is drawn, from the mark's top left: the one place the drawing and a click on an icon read.
    static func frame(ofIcon index: Int, size: CGFloat) -> CGRect {
        let step = mini(size) + gap(size)
        let origin = inset(size) + pad(size)
        return CGRect(x: origin + CGFloat(index % 3) * step, y: origin + CGFloat(index / 3) * step, width: mini(size), height: mini(size))
    }

    var body: some View {
        let gap = Self.gap(size), mini = Self.mini(size)
        ZStack {
            RoundedRectangle(cornerRadius: LaunchpadMetrics.wellCorner * Self.well(size), style: .continuous).fill(LaunchpadMetrics.wellFill)
                .frame(width: Self.well(size), height: Self.well(size))
            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { column in
                            let index = row * 3 + column
                            if index < icons.count {
                                Image(nsImage: icons[index]).resizable()
                                    .frame(width: mini, height: mini)
                                    .background {
                                        // Concentric with the icon: its own corner (0.225 of its side) plus the wash's inset (0.1).
                                        RoundedRectangle(cornerRadius: mini * 0.325, style: .continuous)
                                            .fill(pressed == index ? HelmSurface.rowSelection : Color.clear)
                                            .padding(-mini * 0.1)
                                    }
                                    .animation(HelmMotion.wellFade, value: pressed)
                                    .scaleEffect(popped == index && !HelmMotion.reduceMotion ? LaunchpadMetrics.popScale : 1)
                                    .animation(HelmMotion.interface, value: popped)
                                    .zIndex(popped == index ? 1 : 0)
                            } else if index == 8, !overflow.isEmpty {
                                LaunchpadClusterCell(icons: overflow, side: mini)
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

/// A well with up to four icons two by two inside it, tiny: the ninth cell of a folder of more than nine, and the fourth quarter of a
/// category block, which opens what the large icons do not show.
struct LaunchpadClusterCell: View {
    let icons: [NSImage]
    let side: CGFloat

    var body: some View {
        let inset = side * 0.10, between = side * 0.06
        let tiny = (side - 2 * inset - between) / 2
        ZStack {
            RoundedRectangle(cornerRadius: LaunchpadMetrics.wellCorner * side, style: .continuous).fill(LaunchpadMetrics.wellFill)
            VStack(spacing: between) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: between) {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            if index < icons.count {
                                Image(nsImage: icons[index]).resizable().frame(width: tiny, height: tiny)
                            } else {
                                Color.clear.frame(width: tiny, height: tiny)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: side, height: side)
    }
}

/// A category block: a well of two by two, the first three (four, when the category has four or fewer apps) large icons that launch,
/// the fourth quarter a cluster of four tiny ones that opens the category. Same well, pad and gap as the folder mark.
struct LaunchpadCategoryMark: View {
    /// Up to four icons drawn large, in reading order, then `cluster`, up to four tiny, in the fourth quarter when there are any.
    let large: [NSImage]
    let cluster: [NSImage]
    let size: CGFloat
    /// The large icon (by quadrant) a press is on, which takes the wash instead of the tile, and the one whose app is opening, which swells.
    var pressed: Int?
    var popped: Int?
    /// The menu of the large icon at this index (the icons are the block's apps, in order): a right-click on the icon is the app's.
    var menu: ((Int) -> LaunchpadAppMenu)?

    /// The side of a quadrant: the same pad and gap as the folder mark's, two to a side.
    static func quadrant(_ size: CGFloat) -> CGFloat { (LaunchpadFolderMark.well(size) - 2 * LaunchpadFolderMark.pad(size) - LaunchpadFolderMark.gap(size)) / 2 }

    /// Where quadrant `index` (0 to 3, reading order) is drawn, from the mark's top left: the one place the drawing and a click read.
    static func frame(ofQuadrant index: Int, size: CGFloat) -> CGRect {
        let side = quadrant(size), step = side + LaunchpadFolderMark.gap(size)
        let origin = LaunchpadFolderMark.inset(size) + LaunchpadFolderMark.pad(size)
        return CGRect(x: origin + CGFloat(index % 2) * step, y: origin + CGFloat(index / 2) * step, width: side, height: side)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: LaunchpadMetrics.wellCorner * LaunchpadFolderMark.well(size), style: .continuous).fill(LaunchpadMetrics.wellFill)
                .frame(width: LaunchpadFolderMark.well(size), height: LaunchpadFolderMark.well(size))
                .offset(x: LaunchpadFolderMark.inset(size), y: LaunchpadFolderMark.inset(size))
            ForEach(Array(large.prefix(4).enumerated()), id: \.offset) { index, icon in
                let frame = Self.frame(ofQuadrant: index, size: size)
                Image(nsImage: icon).resizable()
                    .frame(width: frame.width, height: frame.height)
                    .background {
                        // Concentric with the icon: its own corner (0.225 of its side) plus the wash's inset (0.1).
                        RoundedRectangle(cornerRadius: frame.width * 0.325, style: .continuous)
                            .fill(pressed == index ? HelmSurface.rowSelection : Color.clear)
                            .padding(-frame.width * 0.1)
                    }
                    .animation(HelmMotion.wellFade, value: pressed)
                    .scaleEffect(popped == index && !HelmMotion.reduceMotion ? LaunchpadMetrics.popScale : 1)
                    .animation(HelmMotion.interface, value: popped)
                    .zIndex(popped == index ? 1 : 0)
                    .contextMenu { if let menu { menu(index) } }
                    .offset(x: frame.minX, y: frame.minY)
            }
            if !cluster.isEmpty {
                let frame = Self.frame(ofQuadrant: 3, size: size)
                LaunchpadClusterCell(icons: cluster, side: frame.width).offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }
}

/// The locked Hidden block: the same well as a category block's, empty, and a lock in it. Nothing of what is behind it is drawn: no icons, no count.
struct LaunchpadHiddenMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LaunchpadMetrics.wellCorner * LaunchpadFolderMark.well(size), style: .continuous).fill(LaunchpadMetrics.wellFill)
                .frame(width: LaunchpadFolderMark.well(size), height: LaunchpadFolderMark.well(size))
            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.34, weight: .regular))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
    }
}
