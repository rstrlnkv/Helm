import SwiftUI
import HelmUI

/// What the capsule over a thumbnail offers, in order; the ✕ stands after a divider. «Edit» only where there is
/// something to open the editor on (`ShotToastModel.editSource`), «Show in Finder» only for a shot that has a
/// file, and Pin only while `PinEntry.isOffered`. A folded pile's capsule acts on the whole group (`pileCells`).
enum ShotCapsule {
    enum Cell: Equatable { case edit, copy, copyAll, reveal, pin, close }

    static func cells(hasFile: Bool, canEdit: Bool) -> [Cell] {
        var cells: [Cell] = canEdit ? [.edit, .copy] : [.copy]
        if hasFile { cells.append(.reveal) }
        if PinEntry.isOffered { cells.append(.pin) }
        return cells + [.close]
    }

    /// The pile's: «Copy All (N) · Show in Finder | ✕». No Edit and no Pin, which are about one picture; «Show in
    /// Finder» while any shot of the group has a file.
    static func pileCells(hasFile: Bool) -> [Cell] {
        hasFile ? [.copyAll, .reveal, .close] : [.copyAll, .close]
    }

    /// Between a cell and the capsule's edge: the mockup's 4 pt, so a 28 pt cell makes a capsule 36 pt high.
    static let inset = HelmSpace.s2
    /// The divider's height and each side's air. The mockup's 22 pt is on no step of `HelmSpace`, whose steps are
    /// 2 · 4 · 6 · 8 · 12 · 18 · 28 · 40.
    static let separatorHeight: CGFloat = 22
    static let separatorGap = HelmSpace.s2
    private static let dividerWidth: CGFloat = 1
    /// Between one cell and the next, the mockup's 2 pt: the divider's air is its own and comes on top of it.
    static let gap = HelmSpace.s1

    /// The capsule's width for a number of cells, the ✕ counted: a gap between each two cells (the divider stands in
    /// the gap before the ✕ and is not a cell). Computed from the numbers the capsule is laid out by.
    static func width(cellCount: Int) -> CGFloat {
        CGFloat(cellCount) * HelmSpace.s7 + CGFloat(max(0, cellCount - 1)) * gap + dividerWidth + 2 * separatorGap + 2 * inset
    }

    /// The widest the capsule can be while the picture is not wider: the room the window keeps for it.
    static var widest: CGFloat { width(cellCount: cells(hasFile: true, canEdit: true).count) }

    /// How far the capsule stands up from the picture's lower edge, and how far its top is from that edge: a cell
    /// with the inset above and below it, on the rise.
    static let rise = HelmSpace.s4
    static var reach: CGFloat { rise + HelmSpace.s7 + 2 * inset }
}

/// A transparent AppKit view behind the capsule's cells that answers a press anywhere in the capsule's shape and
/// does nothing with it. SwiftUI's own hit test leaves the rim and the divider to what lies below.
final class ShotCapsuleView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let radius = bounds.height / 2
        return NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).contains(convert(point, from: superview)) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

struct ShotCapsuleShield: NSViewRepresentable {
    func makeNSView(context: Context) -> ShotCapsuleView { ShotCapsuleView() }
    func updateNSView(_ view: ShotCapsuleView, context: Context) {}
}
