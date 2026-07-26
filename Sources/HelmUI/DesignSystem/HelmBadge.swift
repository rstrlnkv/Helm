import SwiftUI

/// The one pill. A short word tinted by meaning, next to the thing it is about.
///
/// There were seven of these, with four different fill opacities and two sets
/// of padding, and — worse — two different rules for the text: some drew it in
/// the tint (orange on orange, about 1.7:1 at 11 pt, which is not readable) and
/// some left it at the default. Two of them sat in the same row, 30 px apart,
/// looking like different kinds of thing because one was dark and one was not.
///
/// The tint colours the fill and nothing else. Contrast is not something a
/// caller should be able to get wrong.
public struct HelmBadge: View {
    private let text: String
    private let tint: Color

    public init(_ text: String, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .font(.caption2)
            // Literal rather than `.primary`: badges appear inside rows that
            // animate in, where hierarchical styles re-resolve.
            .foregroundStyle(Color.primary.opacity(0.85))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.20)))
    }
}
