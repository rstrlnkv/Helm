import SwiftUI

/// One row of a settings card, in the shape v3 gives every module.
///
/// **The row answers two questions at once**, and that is the whole idea of the
/// third redesign. The mark on the left says what is happening right now — a
/// fact from the engine. The control on the right says what is configured — a
/// value from the store. The second edition put those two in different columns,
/// 268 pt apart, so a person reading the page top to bottom saw that a rule was
/// holding the Mac and could not see what to change about it. One row, two
/// jobs, and nothing between them.
///
/// The mark is drawn only when there is something happening. A rule that is
/// switched off has no mark at all: the mark reports the world, not the
/// position of the switch beside it, and a grey dot for «off» would be the row
/// saying the same thing twice in two alphabets.
/// What the left of the row says about right now.
public enum HelmRowMark: Equatable, Sendable {
    /// Nothing to report, and nothing to line up with either — for a card
    /// whose rows carry no marks at all.
    case none
    /// Nothing to report, but hold the width. A card where some rows are
    /// marked and some are not needs every label to start on one line;
    /// without this the unmarked ones step 26 pt to the left and the card
    /// reads as two lists.
    case space
    /// The condition is met — this is why the Mac is awake.
    case holding
    /// Switched on and not met right now. Drawn so that «my rule does
    /// nothing» stops looking like «my rule is off».
    case waiting

    /// The three-way answer, decided once for every module rather than in
    /// each page's own `if`.
    ///
    /// The half that is easy to get wrong is the third: a rule that is
    /// switched **off** gets `.space`, not a mark of its own. The mark
    /// reports the world; the switch beside it already reports the setting,
    /// and a grey dot for «off» is the row saying one thing twice. The
    /// width stays, so the labels of a mixed card keep one left edge.
    public static func of(enabled: Bool, satisfied: Bool,
                          inCardWithMarks marksArePossible: Bool = true) -> HelmRowMark {
        guard enabled else { return spacer(inCardWithMarks: marksArePossible) }
        return satisfied ? .holding : .waiting
    }

    /// The width-holder for a row that never carries a mark of its own — or
    /// nothing at all, when no row in the card can carry one either.
    ///
    /// `.space` exists so a card of mixed rows keeps one left edge for its
    /// labels. In a card where **nothing** is marked it holds that edge against
    /// nobody: every label steps 26 pt right, and the column of air down the
    /// left reads as icons that failed to load. Which is exactly what it looked
    /// like on a Mac with no rule switched on — the common case on a fresh
    /// install, and the first thing anybody sees.
    ///
    /// The question is «can a mark appear here», not «is one here now»: asked
    /// the second way the labels would jump sideways the moment a condition
    /// came true. Asked the first way the indent arrives when somebody flips a
    /// switch — their own doing, and the same gesture that puts the first mark
    /// on the screen.
    public static func spacer(inCardWithMarks marksArePossible: Bool) -> HelmRowMark {
        marksArePossible ? .space : .none
    }
}

public struct HelmSettingRow<Trailing: View>: View {

    private let title: String
    private let note: String?
    private let mark: HelmRowMark
    private let trailing: Trailing

    public init(_ title: String, note: String? = nil, mark: HelmRowMark = .none,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.note = note
        self.mark = mark
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 12) {
            markView
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note {
                    Text(note)
                        .font(.system(size: 11))
                        // Literal, not `.secondary`: these rows sit in blocks
                        // that animate, where hierarchical styles re-resolve.
                        .foregroundStyle(HelmText.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The label is the subject of the row and gives way last. Without a
            // floor it is the part a fixed-width control on the right squeezes
            // to nothing — measured once already, at one character per line.
            .layoutPriority(1)
            // Title and note are one thought, and VoiceOver stopped on each of
            // them separately: «External display» — next — «Applies right now»
            // — next — the switch. Three stops for one row, over a page of
            // them. Combined here rather than across the whole row: `.combine`
            // on an element containing a control folds the control's own
            // announcement into the sentence too, and the switch is the part a
            // person navigates *to*.
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            HStack(spacing: 8) { trailing }
        }
    }

    @ViewBuilder private var markView: some View {
        switch mark {
        case .none:
            EmptyView()
        case .space:
            // `.rspace` — the width of a mark and nothing in it.
            Color.clear.frame(width: Self.markWidth, height: 1)
        case .holding:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(HelmSignal.success)
                .frame(width: Self.markWidth)
                .accessibilityHidden(true)
        case .waiting:
            Image(systemName: "clock")
                .foregroundStyle(HelmText.faint)
                .frame(width: Self.markWidth)
                .accessibilityHidden(true)
        }
    }

}

/// 14, from `.rspace { flex: 0 0 14px }` — the same column the marks are drawn
/// in, so a card of mixed rows keeps one left edge for its labels.
///
/// Outside the struct because `HelmSettingRow` is generic in its trailing view,
/// and a generic type cannot hold a static stored property. One number for
/// every specialisation is exactly what it has to be.
extension HelmSettingRow { fileprivate static var markWidth: CGFloat { 14 } }
