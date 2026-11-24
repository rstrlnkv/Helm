import SwiftUI

/// A statement the page has to make, with at most one verb beside it.
///
/// A signal-tinted field, a mark, a sentence, and the action that answers it on
/// the right, drawn as one thing rather than three pieces beside each other.
/// `HelmPermissionNote` and the panel's permissions notice draw this type.
///
/// The fill is 13 % of the signal, which makes it a field rather than a row.
/// Ink on it is measured against that fill, not against the card: a tone that
/// passes on a card can fail here.
public struct HelmBanner<Action: View>: View {
    @Environment(\.helmTraits) private var traits

    /// Which signal, and therefore which fill and which ink.
    ///
    /// One case: nothing in this app announces that something went right with
    /// a verb beside it.
    public enum Tone: Sendable { case warning }

    private let text: String
    private let symbol: String
    private let tone: Tone
    private let fillsWidth: Bool
    private let compact: Bool
    private let action: Action

    /// - Parameter fillsWidth: true for a notice that belongs to a card or a
    ///   column and should share its edges; false for one that belongs to a
    ///   *centred* block, where a full-width field lines up with nothing.
    ///
    ///   Sized to its own content and centred, it is plainly part of the block
    ///   it sits in; at full width it would match neither edge around it.
    /// - Parameter compact: the panel's scale rather than a page's. In the
    ///   320 pt panel the body step wraps a short notice in some languages, and
    ///   11 pt gives every language a line to itself.
    public init(_ text: String, symbol: String = "exclamationmark.triangle.fill",
                tone: Tone = .warning, fillsWidth: Bool = true, compact: Bool = false,
                @ViewBuilder action: () -> Action) {
        self.text = text
        self.symbol = symbol
        self.tone = tone
        self.fillsWidth = fillsWidth
        self.compact = compact
        self.action = action()
    }

    private var ink: Color {
        switch tone {
        case .warning: return HelmSignal.warning(increased: traits.increasedContrast)
        }
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(compact ? HelmText.rowDetail : nil)
                .foregroundStyle(ink)
                .accessibilityHidden(true)
            Text(text)
                // The scale's body step, or `rowDetail` at the panel's scale.
                .font(compact ? HelmText.rowDetail : HelmText.rowTitle)
                // Not the ink: a whole sentence in a signal colour is a shout.
                // The mark carries the signal, the words the meaning.
                .foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                // The words take their width before the spacer does: both are
                // flexible here, and without the priority SwiftUI splits the
                // space and wraps a short sentence in a wide plate. It still
                // wraps when a language needs two lines.
                .layoutPriority(1)
            // Filling the width, the spacer is what pushes the verb to the
            // far edge; hugging, there is nothing to push against and the two
            // would sit 8 pt apart, which reads as one run-on control.
            if fillsWidth { Spacer(minLength: 8) } else { Spacer().frame(width: 6) }
            // The verb keeps its words; the sentence is what wraps, or a long
            // sentence takes its width out of the button.
            action
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? HelmSpace.s3 : 8)
        .background(
            RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                .fill(ink.opacity(0.13))
        )
    }
}

/// A banner with nothing to press.
///
/// A separate initialiser rather than `action: () -> Action = { EmptyView() }`:
/// a default expression cannot stand in for a generic parameter the other
/// arguments infer, which Swift warns about and a future language mode
/// rejects. The constraint pins `Action` to `EmptyView` instead.
extension HelmBanner where Action == EmptyView {
    public init(_ text: String, symbol: String = "exclamationmark.triangle.fill",
                tone: Tone = .warning, fillsWidth: Bool = true) {
        self.init(text, symbol: symbol, tone: tone, fillsWidth: fillsWidth) { EmptyView() }
    }
}
