import SwiftUI

/// A row of controls that starts a new line instead of running off the edge.
///
/// An `HStack` cannot do this. It is not a matter of a modifier: an `HStack`
/// places every child on one line by construction, and when the line is too
/// narrow it *compresses* the children — buttons truncate their titles to
/// «Unbegre…» rather than moving down. The hero's preset row is five buttons
/// whose widths are translated text, and German and French already reach the
/// pane's edge at the default window size, so one more preset or one longer
/// translation is the difference between a row and a row of ellipses.
///
/// `Layout` is the protocol that answers this: `sizeThatFits` reports the
/// height the wrapped lines need for a proposed width, and `placeSubviews` puts
/// them there. Both walk the same `lines(...)` function, so the size reported
/// and the arrangement drawn cannot disagree — the classic defect in a
/// hand-rolled flow layout, where the two are written twice and drift.
public struct HelmWrappingRow: Layout {
    private let spacing: CGFloat
    private let lineSpacing: CGFloat
    private let alignment: HorizontalAlignment

    public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8,
                alignment: HorizontalAlignment = .center) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.alignment = alignment
    }

    /// One line: the sizes on it, and how wide they come to with the gaps.
    private struct Line {
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Every child at its ideal size, broken into lines that fit `width`.
    ///
    /// The proposal handed down is `.unspecified`, never the remaining width: a
    /// button asked to fit a narrow remainder answers with its *truncated*
    /// width, which would let it stay on a line it does not fit and defeat the
    /// wrap. A child wider than the whole row still gets a line of its own —
    /// the `line.sizes.isEmpty` test — rather than an empty line above it.
    private func lines(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var result: [Line] = []
        var line = Line()
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let advance = line.sizes.isEmpty ? size.width : line.width + spacing + size.width
            if !line.sizes.isEmpty, advance > width {
                result.append(line)
                line = Line()
            }
            line.width = line.sizes.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.sizes.append(size)
        }
        if !line.sizes.isEmpty { result.append(line) }
        return result
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                             cache: inout ()) -> CGSize {
        // A nil width is «how wide would you like to be», and the honest answer
        // for a wrapping row is one line: it is what the row costs when nothing
        // forces it to fold, and it is what a scroll view asks before deciding
        // whether the content is wider than the port.
        let width = proposal.width ?? .infinity
        let laid = lines(subviews, width: width)
        let height = laid.map(\.height).reduce(0, +)
            + lineSpacing * CGFloat(max(0, laid.count - 1))
        return CGSize(width: laid.map(\.width).max() ?? 0, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                              subviews: Subviews, cache: inout ()) {
        let laid = lines(subviews, width: bounds.width)
        var index = 0
        var y = bounds.minY
        for line in laid {
            var x: CGFloat
            switch alignment {
            case .leading: x = bounds.minX
            case .trailing: x = bounds.maxX - line.width
            default: x = bounds.minX + (bounds.width - line.width) / 2
            }
            for size in line.sizes {
                // Centred within the line, so a taller control does not drag
                // the baseline of the ones beside it.
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                                      anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
                index += 1
            }
            y += line.height + lineSpacing
        }
    }
}
