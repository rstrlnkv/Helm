import SwiftUI

/// The one pill. A short word tinted by meaning, next to the thing it is about.
///
/// The tint colours the fill and nothing else: text in the tint on its own
/// wash is unreadable, and contrast is not something a caller should be able
/// to get wrong.
public struct HelmBadge: View {

    /// How much the badge is asking for.
    ///
    /// `quiet` is the pill in a list row: it labels a thing among other things
    /// and must not out-shout the row it sits in. `prominent` is for the one
    /// badge on a page that is itself a statement — the wordmark in About —
    /// where a flat 20% wash beside 34 pt type reads as an unfinished
    /// placeholder rather than a mark.
    ///
    /// Two styles of one component: the difference is emphasis, not kind.
    public enum Emphasis: Sendable { case quiet, prominent }

    /// The tint of a badge that says nothing by colour.
    public static let neutralTint = Color.secondary

    private let text: String
    private let tint: Color
    private let emphasis: Emphasis

    public init(_ text: String, tint: Color = HelmBadge.neutralTint, emphasis: Emphasis = .quiet) {
        self.text = text
        self.tint = tint
        self.emphasis = emphasis
    }

    public var body: some View {
        switch emphasis {
        case .quiet: quiet
        case .prominent: prominent
        }
    }

    private var quiet: some View {
        Text(text)
            .font(.caption2)
            // Literal rather than `.primary`: badges appear inside rows that
            // animate in, where hierarchical styles re-resolve.
            .foregroundStyle(Color.primary.opacity(0.85))
            // Off the ladder on purpose: a capsule's padding is half of the
            // pill's silhouette, solved against the rows it sits in, and each
            // ladder neighbour takes it 2 pt out of the row.
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.20)))
    }

    /// The tint carries the badge instead of tinting it: saturated fill, the
    /// lettering knocked out in white, and the small-caps tracking that makes
    /// four letters at 10 pt read as a mark rather than a shrunken word.
    ///
    /// The gradient runs top-light to bottom-dark by a few percent — enough to
    /// give the capsule a direction under the same light the icon plate is lit
    /// by, not enough to look like a button. The shadow is the tint's own, at
    /// low opacity: a neutral drop under a coloured object reads as dirt.
    private var prominent: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(HelmText.onFill)
            // 2.5, for the same reason as `quiet`'s 1: the silhouette, not a gap.
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.95), tint],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        // A hairline of the light source along the top edge,
                        // fading out by the middle. Inside the capsule so it
                        // cannot show as a rim on the outside.
                        Capsule()
                            .strokeBorder(LinearGradient(
                                colors: [.white.opacity(0.45), .white.opacity(0)],
                                startPoint: .top, endPoint: .center), lineWidth: 0.7)
                    }
            }
            .shadow(color: tint.opacity(0.35), radius: 2, y: 1)
    }
}
