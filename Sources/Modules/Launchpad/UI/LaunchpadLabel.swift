import AppKit
import CoreGraphics
import HelmUI

/// Whether a tile's name is cut, and how far the hover scroll has to go to show all of it: one place, pure computation from the name and the room, no view asked. The tile draws a name in the room its width leaves (`room(width:scale:)`, the tile's width less its side padding on both sides; a large block's
/// is two cells wide): two lines when it has a place to break, one that shrinks when it has not (`LaunchpadMetrics.unbreakableShrink`), and a name that still does not fit is cut with an ellipsis.
enum LaunchpadLabel {
    /// The tile's side padding at `scale`: the one place the tile's padding and the label's room read.
    static func sidePadding(scale: CGFloat) -> CGFloat { HelmSpace.s2 * scale }

    /// The room a label has in a tile `width` wide (`LaunchpadTile.glowSize.width`: a cell's, or a large block's two cells).
    static func room(width: CGFloat, scale: CGFloat) -> CGFloat { width - 2 * sidePadding(scale: scale) }

    /// Whether the name has a place to wrap at: a space, a hyphen, a soft hyphen (the built German and Portuguese names carry U+00AD, "Festplatten\u{AD}dienstprogramm": read from Disk Utility's built `InfoPlist.loctable` (de) with `plutil -convert xml1`, 2026-11-22), or
    /// a character of a script that breaks anywhere (Han, Hiragana, Katakana, Hangul: Japanese "VoiceOverユーティリティ" has no space).
    static func canBreak(_ name: String) -> Bool {
        name.unicodeScalars.contains { $0 == " " || $0 == "-" || $0 == "\u{AD}" || breaksAnywhere($0) }
    }

    private static func breaksAnywhere(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF, 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF: return true
        default: return false
        }
    }

    /// How far the tile lets the name shrink before it is cut: a name that breaks 0.85, one that does not `LaunchpadMetrics.unbreakableShrink`.
    static func shrink(_ name: String) -> CGFloat { canBreak(name) ? 0.85 : LaunchpadMetrics.unbreakableShrink }

    /// The label's size: the kit's detail size, larger on a screen that scales up and never smaller; the tile's font is this size too (`LaunchpadTile.labelFont`).
    static func fontSize(scale: CGFloat) -> CGFloat { HelmText.rowDetailNSFont.pointSize * max(1, scale) }

    /// What `allowsTightening` gives back on top of the shrink: a name is called cut only when it is wider than the room by more than this share.
    static let tightening: CGFloat = 0.02
    /// The width of the fade at each end of the scrolling line, and how far past the last letter the scroll goes: the name's end stops where the fade begins, clear of it.
    static let fade: CGFloat = 8

    /// 0 where the whole name is drawn; where it is cut, the distance in points its one line, drawn at the shrunk size, has to move left to show its end clear of the fade. A name that breaks
    /// is cut when it needs more than two lines at the shrunk size (or one, when `oneLine`); one that does not, when its line at the shrunk size is wider than `room`.
    static func overflow(name: String, room: CGFloat, scale: CGFloat, oneLine: Bool) -> CGFloat {
        guard room.isFinite, room > 2 * fade, !name.isEmpty else { return 0 }
        let size = fontSize(scale: scale) * shrink(name)
        let font = NSFont.systemFont(ofSize: size)
        let line = (name as NSString).size(withAttributes: [.font: font]).width
        let limit = room * (1 + tightening)
        if canBreak(name), !oneLine {
            let height = (name as NSString).boundingRect(with: CGSize(width: limit, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin,
                                                         attributes: [.font: font]).height
            let lines = height / (font.ascender - font.descender + font.leading)
            guard lines > 2.5 else { return 0 }
        } else {
            guard line > limit else { return 0 }
        }
        return max(0, line - room + fade)
    }
}
