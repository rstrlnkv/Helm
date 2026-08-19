import AppKit
import HelmUI
import SwiftUI

/// The narrowest room in which a path is still a path.
///
/// The detail line under a broken login item gives its width to the reason
/// first (it is the strongest evidence the item is dead) and lets the path
/// truncate in the middle. At the 540 pt pane a real reason left the path
/// exactly one glyph: «/», drawn, and read to VoiceOver, saying nothing.
///
/// So the path has a floor: the width of «…» and its own last component at
/// the detail size. Below it no cut — head, middle or tail — can show even
/// *which file* the row is about, so the line drops the path entirely rather
/// than drawing its dead weight. `AnUnreadablePathIsNotDrawnTests` holds the
/// arithmetic and the line that reads it.
enum LeftoverPathFloor {

    /// What the path must be able to say, measured: an ellipsis and the last
    /// component, at `HelmText.rowDetail`'s own size.
    static func width(of path: String) -> CGFloat {
        let least = "…" + (path as NSString).lastPathComponent
        let font = HelmText.rowDetailNSFont
        return (least as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }
}

/// The line under a row's name: where the file is, and what is wrong with it —
/// or, in a room too narrow for both, only what is wrong with it.
///
/// The path is offered at its floor, and `ViewThatFits` judges by *ideal*
/// widths — so the frame pins the path's ideal to the floor, or the first
/// arrangement would demand the whole untruncated path and never be taken.
/// Where even the floor does not fit, the path is not drawn at all, and the
/// fallback holds no path — so the row's combined accessibility element
/// carries none either.
struct LeftoverDetailLine: View {
    let detail: LfStr.Detail

    var body: some View {
        if let clause = detail.clause, let reason = detail.reason {
            let floor = LeftoverPathFloor.width(of: detail.path)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    path.frame(minWidth: floor, idealWidth: floor,
                               alignment: .leading)
                    // The room is taken here first; what is left is the
                    // path's. Its separator travels with it, or the
                    // truncation eats the dot and leaves the sentence
                    // hanging off the end of a path. `fixedSize`, not
                    // `layoutPriority`: a candidate that can truncate is a
                    // candidate that always «fits», and this arrangement
                    // was measured being chosen at 540 with the path at
                    // one glyph — the lesson of the page's own captions.
                    Text(reason)
                        .lineLimit(1)
                        .fixedSize()
                }
                // The clause, not the reason: with no path in front of it
                // the separator would open the line — measured, «· Points
                // at…» — which is the dangling dot one character earlier.
                Text(clause)
                    .lineLimit(1)
            }
        } else {
            path
        }
    }

    private var path: some View {
        Text(detail.path)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
