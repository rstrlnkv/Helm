import SwiftUI

/// A statement the page has to make, with at most one verb beside it.
///
/// v3's `.banner`: a signal-tinted field, a mark, a sentence, and the action
/// that answers it on the right. The panel already draws this shape for the
/// permissions notice, and Keep Awake's suppression row was drawing it by hand
/// — a bare `HStack` of an icon, some quiet text and a button, floating on the
/// page with nothing to say it was one thing. Beside a centred 40 pt hero that
/// read as three unrelated pieces of furniture rather than a notice.
///
/// The fill is 13 % of the signal, which is what makes it a field rather than a
/// row; the ink is the signal's *ink* variant, measured against that fill and
/// not against the card — the same tone gives 6–7 on a card and 4.8–5.1 here,
/// so the card's number is the one that would ship unreadable.
public struct HelmBanner<Action: View>: View {
    /// Which signal, and therefore which fill and which ink.
    public enum Tone: Sendable { case warning, success }

    private let text: String
    private let symbol: String
    private let tone: Tone
    private let fillsWidth: Bool
    private let action: Action

    /// - Parameter fillsWidth: true for a notice that belongs to a card or a
    ///   column and should share its edges; false for one that belongs to a
    ///   *centred* block, where a full-width field lines up with nothing.
    ///
    ///   Measured: in the hero it took the section header's inset, which is
    ///   9 pt inside the card below it and 20 pt outside the buttons above —
    ///   so it matched neither, and read as a third thing wedged between two.
    ///   Sized to its own content and centred, it is plainly part of the block
    ///   it sits in.
    public init(_ text: String, symbol: String = "exclamationmark.triangle.fill",
                tone: Tone = .warning, fillsWidth: Bool = true,
                @ViewBuilder action: () -> Action) {
        self.text = text
        self.symbol = symbol
        self.tone = tone
        self.fillsWidth = fillsWidth
        self.action = action()
    }

    private var ink: Color {
        switch tone {
        case .warning: return HelmSignal.warning
        case .success: return HelmSignal.success
        }
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(ink)
                .accessibilityHidden(true)
            Text(text)
                // 13, the ladder's body step. `.callout` is 12 on macOS and
                // 12 is not one of the six sizes this house has.
                .font(.system(size: 13))
                // Literal, and deliberately not the ink: a whole sentence in a
                // signal colour is a shout. The mark carries the signal; the
                // words carry the meaning.
                .foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            // Filling the width, the spacer is what pushes the verb to the
            // far edge; hugging, there is nothing to push against and the two
            // would sit 8 pt apart, which reads as one run-on control.
            if fillsWidth { Spacer(minLength: 8) } else { Spacer().frame(width: 6) }
            action
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: HelmSurface.cardRadius, style: .continuous)
                .fill(ink.opacity(0.13))
        )
    }
}

/// A banner with nothing to press.
///
/// A separate initialiser rather than `action: () -> Action = { EmptyView() }`,
/// which Swift warns about today and rejects outright in a future language
/// mode: a default expression cannot stand in for a generic parameter the other
/// arguments already infer. The constraint says the same thing in a form the
/// compiler is happy with — this initialiser exists only when `Action` is
/// `EmptyView`, so the type is pinned rather than guessed.
extension HelmBanner where Action == EmptyView {
    public init(_ text: String, symbol: String = "exclamationmark.triangle.fill",
                tone: Tone = .warning, fillsWidth: Bool = true) {
        self.init(text, symbol: symbol, tone: tone, fillsWidth: fillsWidth) { EmptyView() }
    }
}
