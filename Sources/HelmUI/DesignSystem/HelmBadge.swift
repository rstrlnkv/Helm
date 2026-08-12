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

    /// How much the badge is asking for.
    ///
    /// `quiet` is the pill in a list row: it labels a thing among other things
    /// and must not out-shout the row it sits in. `prominent` is for the one
    /// badge on a page that is itself a statement — the wordmark in About —
    /// where a flat 20% wash beside 34 pt type reads as an unfinished
    /// placeholder rather than a mark.
    ///
    /// Two styles of one component rather than a second badge: the house has
    /// one pill, and the difference between these is emphasis, not kind.
    public enum Emphasis: Sendable { case quiet, prominent }

    private let text: String
    private let tint: Color
    private let emphasis: Emphasis

    public init(_ text: String, tint: Color = .secondary, emphasis: Emphasis = .quiet) {
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
            // **Off the ladder on purpose, and measured rather than rounded.**
            // A capsule's padding is not a gap between two things; it is half
            // of the pill's own silhouette, solved against the rows this
            // badge sits in. The ladder's neighbours are 4/6 and 0/2, and any
            // of the four takes the pill 2 pt out of the row it was fitted to.
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
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(.white)
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
