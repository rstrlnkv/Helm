import SwiftUI
import HelmRuntime
import HelmUI
import Module_Screenshots_Engine

struct ShotToastView: View {
    @ObservedObject var model: ShotToastModel

    var body: some View {
        Group {
            if case .refusal(let title, let body, let offersSettings)? = model.refusal {
                refusal(title: title, body: body, offersSettings: offersSettings)
                    .padding(HelmSpace.s5)
                    .frame(width: ShotToast.width)
                    // Glass and no edge of our own: it carries its own.
                    .glassEffect(.regular, in: .rect(cornerRadius: HelmRadius.frame))
            } else if !model.shots.isEmpty {
                shelf(model.shots)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .opacity(model.shown ? 1 : 0)
        .offset(x: model.shown ? 0 : Self.arrivalOffset)
        .animation(HelmMotion.interface, value: model.shown)
    }

    // MARK: - The shots

    /// One shot, the pile or the row: the same views in all three, placed by `ShotShelf`, so a shot keeps its view
    /// from the single picture through the pile to the row and travels between them.
    ///
    /// Everything stands against the lower trailing corner, where the newest shot is in every shape. The row is as
    /// wide as `ShotShelf.width`; past `ShotShelf.visible` shots it is cut at its ends (`rowMask`), and only then
    /// is there a mask at all: the single shot and a group that fits are drawn as they always were.
    @ViewBuilder private func shelf(_ shots: [ShotToastModel.Shot]) -> some View {
        if shots.count > ShotShelf.visible {
            sheets(shots).mask { rowMask(count: shots.count, clips: model.unfolded) }
        } else {
            sheets(shots)
        }
    }

    private func sheets(_ shots: [ShotToastModel.Shot]) -> some View {
        let count = shots.count
        let row = model.unfolded && count > 1
        let more = row ? ShotShelf.more(count: count, offset: model.offset) : nil
        return ZStack(alignment: .bottomTrailing) {
            // The row's shadows lie under every picture: a shot's own would fall on the picture of the older shot
            // beside it. In the pile each sheet's shadow is its own, on the sheet under it.
            ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                ring(of: shot, shadow: row ? Self.shadow : 0)
                    .opacity(row ? 1 : 0)
                    .offset(x: row ? ShotShelf.shift(age: count - 1 - index, offset: model.offset, count: count) : 0)
                    .zIndex(-Double(ShotShelf.limit + 1))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                let age = count - 1 - index
                let sheet = ShotShelf.sheet(age: age)
                picture(shot, age: age, count: count)
                    .overlay(alignment: .topLeading) {
                        if let more, more.on == age { moreLabel(more.count).offset(x: -Self.moreOut, y: -Self.labelOut) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if !row, count > 1, age == 0 { counter(count).offset(x: Self.labelOut, y: -Self.labelOut) }
                    }
                    .scaleEffect(row ? 1 : sheet.scale, anchor: .topLeading)
                    .opacity(row ? 1 : sheet.opacity)
                    .offset(x: row ? ShotShelf.shift(age: age, offset: model.offset, count: count) : sheet.offset.width,
                            y: row ? 0 : sheet.offset.height)
                    .zIndex(Double(-age))
                    // A sheet that is not drawn takes no press and is not read.
                    .allowsHitTesting(row || age < ShotShelf.visible)
                    .accessibilityHidden(!row && age > 0)
            }
        }
        // Room for the capsule where the picture is narrower than it; the ring stays round the picture, at the
        // trailing edge, which is the one `ShotToast.place` stands `ShotToast.edgeInset` from the screen's.
        .frame(minWidth: row ? max(ShotShelf.width(count: count), ShotCapsule.widest) : ShotCapsule.widest,
               alignment: .bottomTrailing)
        .overlay(alignment: .bottomTrailing) {
            if row, model.barShown { scrollBar(count: count) }
        }
        .padding(ShotToast.shadowRoom)
        .animation(HelmMotion.interface, value: model.hovering)
        .animation(HelmMotion.interface, value: model.focus)
    }

    /// How far the counter and «N more» stand out of the picture's corner, 10 pt.
    private static let labelOut: CGFloat = 10
    /// How far «N more» stands out of the picture's left edge, not 10 pt (`labelOut`, which it keeps
    /// upward): the far shot's ring is 3 pt wider than its slot, and at 10 the capsule's left cap lay 6.5 pt past the
    /// row's cut, `rowOverhang`, and was cut flat; at 3 it lies 0.5 pt inside it.
    private static let moreOut: CGFloat = 3
    /// How far past the row's end it is still drawn: room for «N more», which stands `moreOut` out of the farthest
    /// whole shot, and short of the ring of the hidden shot beyond it, which begins
    /// `ShotShelf.gap` less the ring's extra width, 10 pt, from the shown one: at 12 its last 2 pt were drawn.
    private static let rowOverhang: CGFloat = 9

    /// What of the row is drawn. The end toward the oldest shot is cut while there are shots past it, the end toward
    /// the newest while the row is scrolled off it; between two rests the cut fades over `ShotShelf.edgeFade`. The
    /// pile is not cut: the mask is then far larger than it is, since a row that folds travels through the room
    /// the row had.
    private func rowMask(count: Int, clips: Bool) -> some View {
        let far = ShotShelf.farthest(count: count)
        let between = abs(model.offset - ShotShelf.snapped(model.offset, count: count)) > 0.5
        let fade = between ? ShotShelf.edgeFade : 0
        let margin = ShotToast.shadowRoom - Self.rowOverhang
        return HStack(spacing: 0) {
            if clips, model.offset < far - 0.5 {
                Color.clear.frame(width: margin)
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: fade)
            }
            Rectangle()
            if clips, model.offset > 0.5 {
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: fade)
                Color.clear.frame(width: margin)
            }
        }
        .padding(clips ? 0 : -Self.unclipped)
    }

    private static let unclipped: CGFloat = 2000

    /// The row's bar: as long as the part of the row that is seen, under the pictures, where the row is scrolled to.
    /// Drawn here and not the system's: the row is not a scroll view, its rests are `ShotShelf`'s.
    private func scrollBar(count: Int) -> some View {
        let row = ShotShelf.width(count: count), far = ShotShelf.farthest(count: count)
        let length = row * CGFloat(ShotShelf.visible) / CGFloat(max(count, ShotShelf.visible))
        let travelled = far > 0 ? model.offset / far : 0
        return Capsule()
            .fill(Self.scrollBarInk)
            .frame(width: length, height: HelmSpace.s2)
            .offset(x: -travelled * (row - length), y: HelmSpace.s5 + HelmSpace.s2)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    /// The pile's counter: how many shots there are, all of them.
    private func counter(_ count: Int) -> some View {
        Text(verbatim: "\(count)")
            .font(Self.labelFont)
            .padding(.horizontal, HelmSpace.s3)
            .frame(minWidth: Self.labelHeight, minHeight: Self.labelHeight)
            .glassEffect(.regular, in: .capsule)
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    /// «N more» on the farthest shot that is seen whole; a click shows the row from its oldest shot. **One line at its
    /// own width, whatever the shot's:** it stands over the picture's corner and is offered the picture's width, which
    /// a tall narrow window's is too little for «3 weitere» or «還有 3 張».
    private func moreLabel(_ count: Int) -> some View {
        Button { model.showOldest() } label: {
            Text(ScStr.more(count))
                .font(Self.labelFont)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, HelmSpace.s4)
                .frame(minHeight: Self.labelHeight)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
        .transition(.opacity)
    }

    /// 22 pt, on no step of `HelmSpace`.
    private static let labelHeight: CGFloat = 22

    /// One shot, in a white frame: the thumbnail macOS shows. The caption is not on the screen; it is the value
    /// a screen reader reads. The capsule comes up from the lower edge while the pointer is over it, and only when
    /// the result is in, since Edit, Copy and Show in Finder need what was written. On the newest sheet of a folded
    /// pile the capsule is the group's, and the sheet is named by the count.
    ///
    /// **While the capsule is up the pointer's zone is the picture and the capsule together.** On a shot narrower
    /// or shorter than the capsule the cells reach outside the picture, and a zone that was the picture alone
    /// would lose the pointer on its way to an outer cell and take the capsule from under it. On a shot narrower
    /// than the capsule both stand against the picture's trailing edge and reach leftward, into the window's own
    /// room: the ring stays where `ShotToast.place` counts on it, by the screen's edge, and the capsule stays on
    /// the screen.
    private func picture(_ shot: ToastShot, age: Int, count: Int) -> some View {
        let image = shot.image
        let pile = count > 1 && !model.unfolded
        let size = ShotThumbnail.fitted(pixels: CGSize(width: image.width, height: image.height))
        let cells = pile ? ShotCapsule.pileCells(hasFile: model.shots.contains { $0.file != nil })
            : ShotCapsule.cells(hasFile: shot.file != nil, canEdit: model.editSource(of: shot) != nil)
        let capsuleWidth = ShotCapsule.width(cellCount: cells.count)
        let pointed = model.unfolded ? model.focus == shot.id : model.hovering && age == 0
        let capsuleUp = pointed && shot.caption != nil
        let narrow = size.width < capsuleWidth
        let zone = capsuleUp
            ? CGSize(width: max(size.width, capsuleWidth), height: max(size.height, ShotCapsule.reach)) : size
        return Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: Self.pictureRadius))
            .overlay(alignment: narrow ? .bottomTrailing : .bottom) {
                ShotDragSource(model: model, shot: shot.id, preview: image, picture: size, trailing: narrow, newest: age == 0)
                    .frame(width: zone.width, height: zone.height)
            }
            .overlay(alignment: narrow ? .bottomTrailing : .bottom) {
                if capsuleUp { capsule(cells, of: shot) }
            }
            .padding(Self.frameWidth)
            // The shadow belongs to the ring's own shape: the capsule's glass and glyphs on the picture cast none.
            .background {
                ring(of: shot, shadow: model.unfolded && count > 1 ? 0 : age > 0 ? Self.lowerShadow : Self.shadow,
                     lower: age > 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(pile ? ScStr.screenshots(count) : ScStr.thumbnailLabel)
            .accessibilityValue(shot.caption ?? "")
    }

    private typealias ToastShot = ShotToastModel.Shot

    /// The white ring round a shot's picture, with the shadow it casts: the sheets under the top one cast a
    /// lighter one (`lower`: 0 6 18 at .25), the top sheet's is 0 10 30 at .35.
    private func ring(of shot: ToastShot, shadow: Double, lower: Bool = false) -> some View {
        let size = ShotThumbnail.fitted(pixels: CGSize(width: shot.image.width, height: shot.image.height))
        return RoundedRectangle(cornerRadius: Self.pictureRadius + Self.frameWidth)
            .fill(.white)
            .frame(width: size.width + 2 * Self.frameWidth, height: size.height + 2 * Self.frameWidth)
            .shadow(color: .black.opacity(shadow), radius: lower ? 18 : 30, y: lower ? 6 : 10)
    }

    /// How far a shot stands to the right of its place before it arrives.
    private static let arrivalOffset: CGFloat = 24
    /// The scroll bar's ink: a literal primary on glass. `HelmText.separator` is 0.50 and means a text mark.
    private static let scrollBarInk = Color.primary.opacity(0.45)
    /// The counter's and «N more»'s font. `HelmText.groupLabel` is a size smaller and would change the drawing.
    private static let labelFont = Font.callout.weight(.semibold)

    private static let shadow = 0.35
    private static let lowerShadow = 0.25

    /// The 3 pt white ring and 5 pt picture corner (the ring's outer corner is 8). `HelmRadius` has
    /// 6 · 10 · 14 · 16 · 26, so neither corner is on the ladder, and the ring has no token.
    private static let frameWidth: CGFloat = 3
    private static let pictureRadius: CGFloat = 5

    /// «Edit · Copy · Show in Finder (· Pin) | ✕», or the pile's «Copy All (N) · Show in Finder | ✕», on glass, 8 pt
    /// up from the picture's lower edge.
    ///
    /// **The whole capsule takes the press** (`ShotCapsuleView`): under it lies the drag view, whose click is «Edit»,
    /// and a press on the rim or the divider that reached it would open the editor and take the thumbnail away.
    private func capsule(_ cells: [ShotCapsule.Cell], of shot: ToastShot) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: ShotCapsule.gap) {
                ForEach(cells.filter { $0 != .close }, id: \.self) { cell in
                    switch cell {
                    case .edit: GlassCell(symbol: "pencil", name: ScStr.edit) { model.edit() }
                    case .copy: GlassCell(symbol: "doc.on.doc", name: ScStr.copy) { model.copy() }
                    case .copyAll:
                        GlassCell(symbol: "doc.on.doc", name: ScStr.copyAll(model.shots.count { $0.caption != nil })) {
                            model.copyAll()
                        }
                    case .reveal: GlassCell(symbol: "folder", name: ScStr.showInFinder) { reveal(shot) }
                    case .pin: GlassCell(symbol: "pin", name: ScStr.pin) { model.pin() }
                    case .close: EmptyView()
                    }
                }
                Divider().frame(height: ShotCapsule.separatorHeight).padding(.horizontal, ShotCapsule.separatorGap)
            }
            closeCell
        }
        .padding(ShotCapsule.inset)
        .background { ShotCapsuleShield() }
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, ShotCapsule.rise)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// This shot's file in Finder; from a folded pile, every file of the group that is still there, selected together.
    private func reveal(_ shot: ToastShot) {
        guard model.isPile else {
            if let file = shot.file { HelmReveal.inFinder(file.path) }
            return
        }
        let files = model.shots.compactMap(\.file).filter { FileManager.default.fileExists(atPath: $0.path) }
        if files.count > 1 {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        } else if let file = files.first ?? model.shots.compactMap(\.file).last {
            HelmReveal.inFinder(file.path)
        }
    }

    /// The way off the screen: the capsule's ✕ on a thumbnail whose result is in (in the row it takes that shot
    /// alone, `ShotToast.close`), and the refusal's, which stays up `ShotToast.refusalLife` in the corner where the next click
    /// goes. A thumbnail still being written has none.
    private var closeCell: some View {
        GlassCell(symbol: "xmark", name: ScStr.dismissToast) { model.dismiss() }
    }

    private func refusal(title: String, body: String, offersSettings: Bool) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            // Clear of the close control in the corner.
            Text(title).font(HelmText.rowTitle).padding(.trailing, HelmSpace.s7)
            Text(body)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
            if offersSettings {
                Button(ScStr.openSettings) { PermissionNeed.screenRecording.openSettings() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { closeCell }
    }
}
