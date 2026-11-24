import SwiftUI

/// What the left of the row says about right now.
public enum HelmRowMark: Equatable, Sendable {
    /// Nothing to report, and nothing to line up with either — for a card
    /// whose rows carry no marks at all.
    case none
    /// Nothing to report, but hold the width, so that in a card where some rows
    /// are marked every label starts on one line.
    case space
    /// The condition is met — this is why the Mac is awake.
    case holding
    /// Switched on and not met right now. Drawn so that «my rule does
    /// nothing» stops looking like «my rule is off».
    case waiting
    /// Something is wrong and the row has the remedy — a grant macOS withholds. Never returned by `of`: it is a
    /// fact about the world that the caller states, like the grant itself.
    case attention

    /// The three-way answer, decided once for every module rather than in
    /// each page's own `if`.
    ///
    /// A rule switched **off** gets `.space`, not a mark of its own: the mark
    /// reports the world, and the switch beside it already reports the setting.
    /// The width stays, so the labels of a mixed card keep one left edge.
    public static func of(enabled: Bool, satisfied: Bool,
                          inCardWithMarks marksArePossible: Bool = true) -> HelmRowMark {
        guard enabled else { return spacer(inCardWithMarks: marksArePossible) }
        return satisfied ? .holding : .waiting
    }

    /// The width-holder for a row that never carries a mark of its own, or
    /// nothing at all when no row in the card can carry one either: in a card
    /// where nothing is marked, a held column reads as icons that failed to load.
    ///
    /// The question is «can a mark appear here», not «is one here now»: asked
    /// the second way, the labels would jump sideways the moment a condition
    /// came true. Asked the first way, the indent arrives when somebody flips a
    /// switch, the same gesture that puts the first mark on the screen.
    public static func spacer(inCardWithMarks marksArePossible: Bool) -> HelmRowMark {
        marksArePossible ? .space : .none
    }
}

/// One row of a settings card: mark, title, note, control.
///
/// The row answers two questions at once. The mark on the left says what is
/// happening right now, a fact from the engine; the control on the right says
/// what is configured, a value from the store. Side by side, so a person who
/// sees that a rule is holding the Mac also sees what to change about it. A
/// rule switched off has no mark: the mark reports the world, not the switch.
///
/// Title and note are one VoiceOver stop (`.accessibilityLabel(spoken)` on the
/// title, not `.combine` on the stack, which would fold the ⓘ in too); the
/// trailing control stays its own, because that is the part a person navigates to.
public struct HelmSettingRow<Trailing: View>: View {
    @Environment(\.helmTraits) private var traits


    private let title: String
    private let note: String?
    private let explainer: HelmExplainer.Content?
    private let mark: HelmRowMark
    private let markSpoken: String?
    private let trailing: Trailing

    /// - Parameter explainer: what an ⓘ beside the row's name opens, for a
    ///   setting whose full story does not fit a caption (see `HelmExplainer`):
    ///   the note answers «should I switch this on», the explainer «what
    ///   happens if I do».
    /// - Parameter markSpoken: what the mark says, for VoiceOver, which does not
    ///   see the mark itself. Read as the title's value. `nil` for a mark whose
    ///   meaning the row's own words or control already carry: the value is then
    ///   the row's spoken text.
    public init(_ title: String, note: String? = nil,
                explainer: HelmExplainer.Content? = nil, mark: HelmRowMark = .none, markSpoken: String? = nil,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.note = note
        self.explainer = explainer
        self.mark = mark
        self.markSpoken = markSpoken
        self.trailing = trailing()
    }

    public var body: some View {
        // Spacing 0, with the mark's gap inside its frame: an `HStack` spacing
        // applies even beside a view of no width, so a collapsed column would
        // leave 12 pt of air, the indent `.none` exists to prevent.
        HStack(spacing: 0) {
            markView
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s2) {
                    Text(title)
                        // One stop for title and note: see the type's doc comment.
                        .accessibilityLabel(spoken)
                        .accessibilityValue(markSpoken ?? spoken)
                    if let explainer { HelmExplainer(explainer) }
                }
                if let note {
                    Text(note)
                        // The line under a row's name: a text style, so it
                        // grows with the title when the system text size does.
                        .font(HelmText.rowDetail)
                        // Literal, not `.secondary`: these rows sit in blocks
                        // that animate, where hierarchical styles re-resolve.
                        .foregroundStyle(HelmText.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                        // `.contentTransition`, not `.id` plus a `.transition`.
                        // A transition needs two identities, and two views do
                        // not travel: on a press that changes the words and the
                        // indent together, the title would glide while the note
                        // sat still and then appeared at the far end. A content
                        // transition changes what one view draws, so the layout
                        // goes on animating underneath it
                        // (Architecture/DesignSystem.md § Motion).
                        .contentTransition(.opacity)
                        // The words are already in the title's label above, so
                        // they would be read twice.
                        .accessibilityHidden(true)
                }
            }
            // The label is the subject of the row and gives way last: without
            // a floor, a fixed-width control on the right squeezes it to one
            // character per line.
            .layoutPriority(1)
            // 12, the gap the stack's spacing would give.
            Spacer(minLength: 12)
            HStack(spacing: 8) { trailing }
        }
    }

    /// The row as one sentence: the name, then what it is doing. A full stop
    /// between them, because two clauses run together are read as one.
    private var spoken: String {
        guard let note, !note.isEmpty else { return title }
        return "\(title). \(note)"
    }

    /// **One view for every mark, not a `switch` over them.** SwiftUI
    /// interpolates between two states of one view, never between two views, so
    /// the states are properties of a single `Image`: which symbol, what colour,
    /// whether it is drawn, and how wide its column is. Every one interpolates.
    ///
    /// `helmSymbolSwap` carries clock → tick; the two symbols share a ring, so
    /// Magic Replace moves only the hands inside.
    private var markView: some View {
        Image(systemName: symbolName)
            .foregroundStyle(markInk)
            .helmSymbolSwap(symbolName)
            // Nothing to say, but the column may still have to hold its width:
            // `.space` is drawn and invisible rather than absent, so the labels
            // of a mixed card keep one left edge.
            .opacity(mark == .holding || mark == .waiting || mark == .attention ? 1 : 0)
            // The whole column, gap included: nothing at all at `.none`,
            // otherwise the mark's width plus the gap.
            .frame(width: mark == .none ? 0 : HelmLayout.markColumn + 12, alignment: .leading)
            .accessibilityHidden(true)
    }

    /// `.space` keeps the tick's name rather than an empty string: an `Image`
    /// with no symbol is a different shape, and the swap out of invisibility
    /// would resize the column under the transition that is carrying it.
    private var symbolName: String {
        switch mark {
        case .waiting: "clock"
        case .attention: "exclamationmark.circle.fill"
        case .none, .space, .holding: "checkmark.circle.fill"
        }
    }

    private var markInk: Color {
        switch mark {
        case .waiting: HelmText.faint
        case .attention: HelmSignal.warning(increased: traits.increasedContrast)
        case .none, .space, .holding: HelmSignal.success(increased: traits.increasedContrast)
        }
    }

}
