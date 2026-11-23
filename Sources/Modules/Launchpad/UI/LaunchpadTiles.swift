import SwiftUI
import HelmUI
import HelmRuntime
import Module_Launchpad_Engine

/// The sizes the window and the page draw at, said once. Content sizes, not the kit's: an icon is as big as the
/// system draws an app icon in a grid, whatever the spacing ladder says.
enum LaunchpadMetrics {
    /// An app's icon in the window.
    static let windowIcon: CGFloat = 80
    /// How far a name with no place to break shrinks before it is cut: 0.78. The square cell leaves a name that long ("Festplattendienstprogramm" without its soft hyphens) cut only on the smaller screens (1024 x 768 and 1280 x 800 at x1; whole from 1440 x 900), and the hover scrolls the rest (`LaunchpadLabel`, `AutomaticIsTheSameGridOnEveryScreenTests`).
    static let unbreakableShrink: CGFloat = 0.78
    /// An icon beside a name in the settings page's list of hidden apps.
    static let hiddenIcon: CGFloat = 28
    /// The Dock helper's icon on the settings page: big enough to take hold of and drag.
    static let dockIcon: CGFloat = 40
    /// What a tile holds besides its icon at scale `scale` (`scale(for:topSafe:)`; 1 under Manual): the gap, two lines of label (`labelLeading`, which
    /// does not shrink below 17 pt) and the padding above and below. The gap and the padding follow the scale, the lines follow `max(1, scale)`, as the label font does.
    /// Without app names (`LaunchpadGridSettings.showNames`) one line is left: the names of folders, category blocks and the Hidden block stay, on one line, and a cell is one height for every tile.
    static func cellChrome(names: Bool, scale: CGFloat) -> CGFloat { 3 * HelmSpace.s3 * scale + (names ? 2 : 1) * labelLeading * max(1, scale) }
    /// A tile's height: the icon plus `cellChrome`.
    static func cellHeight(icon: CGFloat, names: Bool, scale: CGFloat) -> CGFloat { icon + cellChrome(names: names, scale: scale) }
    /// One label line's height at scale 1 (`.subheadline` leads at 17 pt).
    static let labelLeading: CGFloat = 17
    /// The screen the layout is drawn for at scale 1, and the room its height holds besides the menu bar's strip and the 36 pt the grid keeps under it
    /// (900 − 36 = 864): the window's width and height divide by these.
    static let referenceWidth: CGFloat = 1440
    static let referenceHeight: CGFloat = 864
    /// The room kept besides the top strip in the reference height.
    static let referenceKeep: CGFloat = 36
    /// How far the scale goes either way.
    static let scaleRange: ClosedRange<CGFloat> = 0.6...1.6
    /// Automatic is this many columns and rows on every screen; only a screen that cannot hold the rows at the floor icon holds fewer (`LaunchpadGeometry.counts`).
    static let automaticColumns = 7
    static let automaticRows = 5
    /// The most Automatic asks for: the reference icon at the top of the scale and of the multiplier (80 * 1.6 * 1.25 = 160 pt), so the multiplier still enlarges the icon
    /// on the largest screens, where `iconRange`'s 128 would cap it. Manual keeps `iconRange`. The cell's width and height still cap what is drawn.
    static let automaticIconCeiling: CGFloat = windowIcon * scaleRange.upperBound * CGFloat(LaunchpadGridSettings.multiplierRange.upperBound)
    /// The scale of a screen `size` whose top `topSafe` is kept: the narrower of the width's and the height's share of the reference, inside `scaleRange`.
    /// A share that is not a number (a size that is not a size) is 1, an infinite one goes to its end: finite for any input.
    static func scale(for size: CGSize, topSafe: CGFloat) -> CGFloat {
        let wide = (size.width / referenceWidth).clamped(to: scaleRange, whenNotANumber: 1)
        let tall = ((size.height - topSafe - referenceKeep) / referenceHeight).clamped(to: scaleRange, whenNotANumber: 1)
        return min(wide, tall)
    }
    /// The "new" dot: the system blue with a dark ring, so it parts from a blue icon and from a bright wallpaper. Its side is a share of the icon
    /// (not under `newDotLeast`), and it sits `newDotInset` of the icon in from the frame's corner, on the art's corner: an app's art is inset
    /// about a tenth of its frame. The ring's darkness and the share were chosen by eye on shots over a blue icon and a light ground
    /// (2026-11-22). Offscreen probes read the ring against App Store's blue at about 3:1, against a light ground 6.2:1, the fill against a dark ground 4.5:1; not measured over real glass or with Increase Contrast. With Increase Contrast the ring is opaque and thicker.
    static func newDot(icon: CGFloat) -> CGFloat { max(newDotLeast, icon * 0.14) }
    static let newDotLeast: CGFloat = 8
    static let newDotInset: CGFloat = 0.08
    static let newDotInk = Color.blue
    static func newDotRing(increased: Bool) -> (color: Color, width: CGFloat) {
        increased ? (Color.black, 2) : (Color.black.opacity(0.6), 1.5)
    }
    /// The smallest an icon shrinks to when the grid asked for does not fit.
    static let iconFloor: CGFloat = 24
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
    /// What "Done" is given at the right of the search field, as `switchRoom` is at the left: its button in the widest of the eight languages plus the same gap of 20 pt
    /// (85 pt in Portuguese, the widest, measured by `fittingSize` on 2026-11-23; `TheDoneButtonFitsItsRoomInEveryLanguageTests` measures it again). A window with less room has the button above the page dots.
    static let doneRoom: CGFloat = 105
    /// The removal card's width, and what its buttons are given inside its padding (the 324 pt the German and Russian "Quit and Move to Trash" overflowed side by side).
    static let removalCardWidth: CGFloat = 360
    static let removalRoom: CGFloat = removalCardWidth - 2 * HelmSpace.s6
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
    /// A one-cell folder's well side as a share of its frame, so it reads as big as an app icon's visible body; a large mark's well takes the small icon's inset instead (`LaunchpadGeometry.largeEdge`), so it meets the four icons' bodies. Its corner is `wellCorner` of the well's side.
    static let wellShare: CGFloat = 0.85
    static let wellCorner: CGFloat = 0.225
    /// The keyboard choice's ring when the glow is off (Reduce Motion, Increase Contrast): measured offscreen by the designer at 4.68:1 against the tile wash and 6.56:1 against the ground (a dark stand-in), so chosen is not pressed.
    static let selectionRing = Color.white.opacity(0.6)
    /// Kept under the grid for the page dots.
    static let dotsRoom: CGFloat = 64
    static let dotsBottom: CGFloat = 28
    /// The window's content before it settles at its size, as a factor.
    static let zoomFrom: CGFloat = 1.08
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

/// What an app's menu and VoiceOver actions offer about its file: show it in Finder, copy its path. Made only by
/// `LaunchpadScreenState.fileActions(for:)`, which is where a hidden app is kept out.
struct LaunchpadFileActions {
    let reveal: () -> Void
    let copyPath: () -> Void
}

/// "Show in Finder" and "Copy Path", as menu rows.
private struct LaunchpadFileButtons: View {
    let files: LaunchpadFileActions

    var body: some View {
        Button(HelmWord.showInFinder, action: files.reveal)
        Button(LpStr.copyPath, action: files.copyPath)
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
    /// Show in Finder and Copy Path under Move to category; nil where the app's file is not offered.
    var files: LaunchpadFileActions?

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
        if let files {
            Divider()
            LaunchpadFileButtons(files: files)
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

/// What a tile wears in the edit mode: its icon wiggles (`seed` sets its place in the shake), and an app wears the badges whose press is given: the × (`remove`, only where
/// the Uninstaller offers the app) and the eye (`hide`). The frames are `LaunchpadBadge.frames`, which the pointer's hit test reads too.
struct LaunchpadTileEdit {
    var seed: Int
    var remove: (() -> Void)?
    var hide: (() -> Void)?

    var kinds: LaunchpadBadge.Kinds {
        var kinds: LaunchpadBadge.Kinds = []
        if remove != nil { kinds.insert(.remove) }
        if hide != nil { kinds.insert(.hide) }
        return kinds
    }

    /// The same number for the same id in every run, so a tile does not change its step when the window is opened again (`String.hashValue` is chosen anew at each launch).
    static func seed(of id: String) -> Int { id.utf8.reduce(5381) { ($0 &* 33 &+ Int($1)) & 0xFFFF } }
}

/// The mark's small, endless tilt in the edit mode (`HelmMotion.wiggle`): none under Reduce Motion, where the badges alone say the mode is on.
private struct LaunchpadWiggle: ViewModifier {
    let seed: Int
    let on: Bool
    @State private var swung = false
    static let degrees = 1.6

    func body(content: Content) -> some View {
        let animation = on ? HelmMotion.wiggle(seed: seed) : nil
        content
            .rotationEffect(.degrees(animation != nil ? (swung ? Self.degrees : -Self.degrees) : 0))
            .animation(animation, value: swung)
            .onChange(of: on, initial: true) { _, now in swung = now }
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
    var pressed = false
    /// A folder's other size, offered beside hide: its menu item's title and what it does.
    var resize: (title: String, action: () -> Void)?
    /// An app's menu (Hide and Move to category) in place of the bare Hide.
    var menu: LaunchpadAppMenu?
    /// The tile is in the Hidden card: its one action, from the menu and from VoiceOver, is Show (the `hide` closure), and it cannot be moved.
    var inHidden = false
    /// The tile's place by VoiceOver: nil where no reorder is allowed (a search, the category view, the Hidden card).
    var reorder: LaunchpadTileMoves?
    /// An app's Show in Finder and Copy Path, in the Hidden card's menu (which has no `menu`) and as VoiceOver actions.
    var files: LaunchpadFileActions?
    /// An app's name is not drawn (`LaunchpadGeometry.names` off); `help` and the accessibility label keep it.
    var hidesName = false
    /// The name stays but the cell holds one line of it (names are off for apps): a folder's, a category's, the Hidden block's.
    var oneLine = false
    /// The app was added in the last 30 days and not opened from Launchpad: a dot on its icon, and "new" for VoiceOver.
    var isNew = false
    /// The geometry's scale (`LaunchpadGeometry.scale`): the tile's gap and padding follow it, the label font follows `max(1, scale)`.
    var scale: CGFloat = 1
    /// The edit mode's wiggle and badges; nil outside the mode, and on the tile the lift carries.
    var editMode: LaunchpadTileEdit?
    /// "Edit" in the tile's menu: nil where the mode cannot begin (or already is).
    var beginEditing: (() -> Void)?
    @ViewBuilder let mark: Mark
    @State private var hovering = false
    /// The hover scroll's offset (0 or negative): moved by `.task(id: marqueeOn)`, which owns it.
    @State private var scrolled: CGFloat = 0
    @Environment(\.helmTraits) private var traits

    /// The "new" dot at the icon art's top right corner (`LaunchpadMetrics.newDot(icon:)`).
    private var newDot: some View {
        let side = LaunchpadMetrics.newDot(icon: iconSize), ring = LaunchpadMetrics.newDotRing(increased: traits.increasedContrast)
        return Circle().fill(LaunchpadMetrics.newDotInk)
            .overlay(Circle().strokeBorder(ring.color, lineWidth: ring.width))
            .frame(width: side, height: side)
            .offset(x: -LaunchpadMetrics.newDotInset * iconSize, y: LaunchpadMetrics.newDotInset * iconSize)
    }

    /// The kit's detail font at the owner's text size, larger on a screen that scales up and never smaller (`LaunchpadLabel.fontSize`).
    private var labelFont: Font {
        scale > 1 ? .system(size: LaunchpadLabel.fontSize(scale: scale)) : HelmText.rowDetail
    }

    /// The room the label has: the tile's width (`glowSize`: a cell's, a large block's two cells) less its side padding (`LaunchpadLabel.room`).
    private var labelRoom: CGFloat { LaunchpadLabel.room(width: glowSize.width, scale: scale) }

    /// How far a cut name scrolls under the pointer: 0 where it is not cut. Asked only while hovering, so no tile measures its name until it is pointed at.
    private var marqueeDistance: CGFloat {
        hovering && !hidesName ? LaunchpadLabel.overflow(name: name, room: labelRoom, scale: scale, oneLine: oneLine) : 0
    }

    /// The cut name scrolls while the pointer is on it and nothing presses the tile; with Reduce Motion it stays cut and `help` holds the whole name.
    private var marqueeOn: Bool { marqueeDistance > 0 && !pressed && !HelmMotion.reduceMotion }

    /// The scrolling line: the name on one line at the shrunk size, from the label's left edge, clipped to the label's room with a fade (`LaunchpadLabel.fade`) at each end that has more
    /// of the name behind it: none at the left until it has scrolled, none at the right once the end is shown. It sits over the label, which keeps the cell's two lines of height.
    private var marquee: some View {
        let edge = LaunchpadLabel.fade / labelRoom, atEnd = scrolled <= -marqueeDistance
        return Text(name)
            .font(.system(size: LaunchpadLabel.fontSize(scale: scale) * LaunchpadLabel.shrink(name)))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: scrolled)
            .frame(width: labelRoom, alignment: .leading)
            .mask(LinearGradient(stops: [.init(color: Color.black.opacity(scrolled < 0 ? 0 : 1), location: 0), .init(color: .black, location: edge),
                                         .init(color: .black, location: 1 - edge), .init(color: Color.black.opacity(atEnd ? 1 : 0), location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .allowsHitTesting(false)
    }

    /// One go to the end of the name after a short wait, a hold, and back; the pointer leaving, a press or a lift ends it (the id changes, the task is cancelled, the offset is 0).
    private func scroll(by distance: CGFloat) async {
        scrolled = 0
        guard distance > 0, marqueeOn else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        withAnimation(HelmMotion.marquee(distance: distance)) { scrolled = -distance }
        try? await Task.sleep(for: .seconds(HelmMotion.marqueeDuration(distance: distance) + 0.9))
        guard !Task.isCancelled else { return }
        withAnimation(HelmMotion.interface) { scrolled = 0 }
    }

    var body: some View {
        Button(action: open) {
            VStack(spacing: HelmSpace.s3 * scale) {
                mark
                    .frame(width: iconSize, height: iconSize)
                    .modifier(LaunchpadWiggle(seed: editMode?.seed ?? 0, on: editMode != nil))
                    .scaleEffect(popped && !HelmMotion.reduceMotion ? LaunchpadMetrics.popScale : 1)
                    .animation(HelmMotion.interface, value: popped)
                    .overlay(alignment: .topTrailing) {
                        if isNew, editMode == nil { newDot }
                    }
                    .accessibilityHidden(true)
                if !hidesName {
                    Text(name)
                        .font(labelFont)
                        .foregroundStyle(Color.white)
                        // A name with no place to break (`LaunchpadLabel.canBreak`: no space, hyphen, soft hyphen or CJK letter) takes one line and shrinks to fit
                        // (German "Festplattendienstprogramm"), since two lines would split it mid-word before the scale ever applied.
                        .lineLimit(LaunchpadLabel.canBreak(name) && !oneLine ? 2 : 1, reservesSpace: true)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(LaunchpadLabel.shrink(name))
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity)
                        .opacity(marqueeOn ? 0 : 1)
                        .overlay(alignment: .leading) { if marqueeOn { marquee } }
                }
            }
            .padding(.vertical, HelmSpace.s3 * scale)
            .padding(.horizontal, LaunchpadLabel.sidePadding(scale: scale))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(TileStyle(hovering: hovering, selected: selected, pressed: pressed, glowSize: glowSize))
        .help(name)
        .onHover { hovering = $0 }
        .task(id: marqueeOn) { await scroll(by: marqueeDistance) }
        .overlay(alignment: .topLeading) { badges }
        .accessibilityLabel(accessibleName)
        .contextMenu {
            if let menu { menu } else {
                if let hide { Button(inHidden ? HelmWord.show : LpStr.hide, action: hide) }
                if let files { Divider(); LaunchpadFileButtons(files: files) }
            }
            if let resize { Button(resize.title, action: resize.action) }
            if let beginEditing { Button(HelmWord.edit, action: beginEditing) }
            if let remove = editMode?.remove { Button(LpStr.removeAction, action: remove) }
        }
        .accessibilityActions {
            if let remove = editMode?.remove { Button(LpStr.removeAction, action: remove) }
            if let hide { Button(inHidden ? HelmWord.show : LpStr.hide, action: hide) }
            if let files { LaunchpadFileButtons(files: files) }
            if let resize { Button(resize.title, action: resize.action) }
            if let reorder { moveActions(reorder) }
        }
    }

    /// The edit mode's badges, each a button drawn where `LaunchpadBadge.frames` says: a dark disc with a white glyph. VoiceOver reaches what they do through the tile's actions, not through them.
    @ViewBuilder private var badges: some View {
        if let editMode, !editMode.kinds.isEmpty {
            let side = LaunchpadBadge.side(icon: iconSize)
            ZStack(alignment: .topLeading) {
                ForEach(LaunchpadBadge.frames(editMode.kinds, cell: glowSize, icon: iconSize, iconTop: HelmSpace.s3 * scale)) { badge in
                    let press = badge.kind == .remove ? editMode.remove : editMode.hide
                    Button { press?() } label: {
                        Image(systemName: badge.kind == .remove ? "xmark" : "eye.slash")
                            .font(.system(size: side * 0.5, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: side, height: side)
                            .background(Circle().fill(Color.black.opacity(traits.increasedContrast ? 1 : 0.72)))
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: traits.increasedContrast ? 1.5 : 0).frame(width: side, height: side))
                            .frame(width: badge.frame.width, height: badge.frame.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(badge.kind == .remove ? LpStr.removeNamed(name) : LpStr.hideNamed(name))
                    .accessibilityHidden(true)
                    .offset(x: badge.frame.minX, y: badge.frame.minY)
                }
            }
            .frame(width: glowSize.width, height: glowSize.height, alignment: .topLeading)
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
    /// An application's tile; the icon is the caller's, from the window's own cache (nil until it is drawn: an empty slot of the same frame).
    init(app: CatalogApp, icon: NSImage?, iconSize: CGFloat, selected: Bool, glowSize: CGSize, popped: Bool, pressed: Bool = false, inHidden: Bool = false,
         moved: LaunchpadCategoryTarget?, open: @escaping () -> Void, hide: @escaping () -> Void,
         move: @escaping (LaunchpadCategoryTarget?) -> Void, reorder: LaunchpadTileMoves? = nil,
         files: LaunchpadFileActions? = nil, showName: Bool = true, oneLine: Bool = false, isNew: Bool = false, scale: CGFloat = 1,
         editMode: LaunchpadTileEdit? = nil, beginEditing: (() -> Void)? = nil) {
        self.init(name: app.name, accessibleName: isNew ? LpStr.appIsNew(app.name) : app.name, iconSize: iconSize, selected: selected, open: open, hide: hide,
                  glowSize: glowSize, popped: popped, pressed: pressed,
                  menu: inHidden ? nil : LaunchpadAppMenu(app: app, moved: moved, hide: hide, move: move, files: files), inHidden: inHidden,
                  reorder: reorder, files: files, hidesName: !showName, oneLine: oneLine, isNew: isNew, scale: scale,
                  editMode: editMode, beginEditing: beginEditing) {
            Image(nsImage: icon ?? LaunchpadIcons.empty).resizable()
        }
    }
}

/// A saved folder: a well with up to nine of its apps' icons, three by three, no border. The icons and the room round them
/// follow the tile's size, like the icon does.
struct LaunchpadFolderMark: View {
    let icons: [NSImage?]
    let size: CGFloat
    /// The well's inset where the mark is large (`LaunchpadGeometry.largeEdge`); nil for a one-cell mark.
    var edge: CGFloat?
    /// The apps past what the mark's cells show, as icons: the last cell holds up to four of them, two by two, tiny.
    var overflow: [NSImage?] = []
    /// The icon (by index) a press is on, which takes the wash instead of the tile, and the one whose app is opening, which swells.
    var pressed: Int?
    var popped: Int?
    /// The well's side: an app icon's visible body is about this much of its frame, and the well is drawn as big, centred in the frame.
    /// A large mark passes `edge` (`LaunchpadGeometry.largeEdge`), the small icon's inset, so its well meets the visible edges of the four icons it stands for.
    static func well(_ size: CGFloat, edge: CGFloat? = nil) -> CGFloat { size - 2 * inset(size, edge: edge) }
    /// From the frame's edge to the well's: `edge` where the caller says, else the share of the frame that makes the well `wellShare` of it. The one function every
    /// drawing and hit test reads.
    static func inset(_ size: CGFloat, edge: CGFloat? = nil) -> CGFloat { edge ?? size * (1 - LaunchpadMetrics.wellShare) / 2 }
    static func pad(_ size: CGFloat, edge: CGFloat? = nil) -> CGFloat { well(size, edge: edge) * 0.10 }
    static func gap(_ size: CGFloat, edge: CGFloat? = nil) -> CGFloat { well(size, edge: edge) * 0.05 }
    /// The apps a folder's mark draws, by what the screen asks the cache for: the first nine (eight when a large folder holds more than
    /// nine), and for a large one the last cell's up to four tiny ones.
    static func cells(_ apps: [CatalogApp], large: Bool) -> (shown: ArraySlice<CatalogApp>, overflow: ArraySlice<CatalogApp>) {
        (apps.prefix(large && apps.count > 9 ? 8 : 9), large ? apps.dropFirst(8).prefix(apps.count > 9 ? 4 : 0) : [])
    }
    static func mini(_ size: CGFloat, edge: CGFloat? = nil) -> CGFloat { (well(size, edge: edge) - 2 * pad(size, edge: edge) - 2 * gap(size, edge: edge)) / 3 }

    /// Where icon `index` (0 to 8, reading order) is drawn, from the mark's top left: the one place the drawing and a click on an icon read.
    static func frame(ofIcon index: Int, size: CGFloat, edge: CGFloat? = nil) -> CGRect {
        let step = mini(size, edge: edge) + gap(size, edge: edge)
        let origin = inset(size, edge: edge) + pad(size, edge: edge)
        return CGRect(x: origin + CGFloat(index % 3) * step, y: origin + CGFloat(index / 3) * step, width: mini(size, edge: edge), height: mini(size, edge: edge))
    }

    var body: some View {
        let gap = Self.gap(size, edge: edge), mini = Self.mini(size, edge: edge), well = Self.well(size, edge: edge)
        ZStack {
            RoundedRectangle(cornerRadius: LaunchpadMetrics.wellCorner * well, style: .continuous).fill(LaunchpadMetrics.wellFill)
                .frame(width: well, height: well)
            VStack(spacing: gap) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<3, id: \.self) { column in
                            let index = row * 3 + column
                            if index < icons.count {
                                Image(nsImage: icons[index] ?? LaunchpadIcons.empty).resizable()
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
    let icons: [NSImage?]
    let side: CGFloat

    /// The side of one of the four icons in a cell `side` across: the view draws them at it and the caller asks the cache for it.
    static func tiny(_ side: CGFloat) -> CGFloat { (side - 2 * side * 0.10 - side * 0.06) / 2 }

    var body: some View {
        let between = side * 0.06
        let tiny = Self.tiny(side)
        ZStack {
            RoundedRectangle(cornerRadius: LaunchpadMetrics.wellCorner * side, style: .continuous).fill(LaunchpadMetrics.wellFill)
            VStack(spacing: between) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: between) {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            if index < icons.count {
                                Image(nsImage: icons[index] ?? LaunchpadIcons.empty).resizable().frame(width: tiny, height: tiny)
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
    let large: [NSImage?]
    let cluster: [NSImage?]
    let size: CGFloat
    /// The well's inset (`LaunchpadGeometry.largeEdge`).
    var edge: CGFloat?
    /// The large icon (by quadrant) a press is on, which takes the wash instead of the tile, and the one whose app is opening, which swells.
    var pressed: Int?
    var popped: Int?
    /// The menu of the large icon at this index (the icons are the block's apps, in order): a right-click on the icon is the app's.
    var menu: ((Int) -> LaunchpadAppMenu)?

    /// The side of a quadrant: the same pad and gap as the folder mark's, two to a side.
    static func quadrant(_ size: CGFloat, edge: CGFloat? = nil) -> CGFloat {
        (LaunchpadFolderMark.well(size, edge: edge) - 2 * LaunchpadFolderMark.pad(size, edge: edge) - LaunchpadFolderMark.gap(size, edge: edge)) / 2
    }

    /// Where quadrant `index` (0 to 3, reading order) is drawn, from the mark's top left: the one place the drawing and a click read.
    static func frame(ofQuadrant index: Int, size: CGFloat, edge: CGFloat? = nil) -> CGRect {
        let side = quadrant(size, edge: edge), step = side + LaunchpadFolderMark.gap(size, edge: edge)
        let origin = LaunchpadFolderMark.inset(size, edge: edge) + LaunchpadFolderMark.pad(size, edge: edge)
        return CGRect(x: origin + CGFloat(index % 2) * step, y: origin + CGFloat(index / 2) * step, width: side, height: side)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            let well = LaunchpadFolderMark.well(size, edge: edge), inset = LaunchpadFolderMark.inset(size, edge: edge)
            RoundedRectangle(cornerRadius: LaunchpadMetrics.wellCorner * well, style: .continuous).fill(LaunchpadMetrics.wellFill)
                .frame(width: well, height: well)
                .offset(x: inset, y: inset)
            ForEach(Array(large.prefix(4).enumerated()), id: \.offset) { index, icon in
                let frame = Self.frame(ofQuadrant: index, size: size, edge: edge)
                Image(nsImage: icon ?? LaunchpadIcons.empty).resizable()
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
                let frame = Self.frame(ofQuadrant: 3, size: size, edge: edge)
                LaunchpadClusterCell(icons: cluster, side: frame.width).offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }
}

/// The locked Hidden block: the same well as a category block's, empty, and a lock in it. Nothing of what is behind it is drawn: no icons, no count.
struct LaunchpadHiddenMark: View {
    let size: CGFloat
    /// The well's inset (`LaunchpadGeometry.largeEdge`).
    var edge: CGFloat?

    var body: some View {
        let well = LaunchpadFolderMark.well(size, edge: edge)
        ZStack {
            RoundedRectangle(cornerRadius: LaunchpadMetrics.wellCorner * well, style: .continuous).fill(LaunchpadMetrics.wellFill)
                .frame(width: well, height: well)
            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.34, weight: .regular))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
    }
}
