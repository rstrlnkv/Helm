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
    private let action: Action

    public init(_ text: String, symbol: String = "exclamationmark.triangle.fill",
                tone: Tone = .warning,
                @ViewBuilder action: () -> Action = { EmptyView() }) {
        self.text = text
        self.symbol = symbol
        self.tone = tone
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
                .font(.callout)
                // Literal, and deliberately not the ink: a whole sentence in a
                // signal colour is a shout. The mark carries the signal; the
                // words carry the meaning.
                .foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
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
