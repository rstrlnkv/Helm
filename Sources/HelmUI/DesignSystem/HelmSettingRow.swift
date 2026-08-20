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
        // Spacing 0, with the mark's own gap inside its frame. An `HStack`
        // spacing is applied whether or not the view beside it has any width,
        // so a column that shrinks to nothing would leave 12 pt of air behind
        // — which is exactly the indent-against-nobody that `.none` exists to
        // prevent. Carried in the frame, the gap goes with the column.
        HStack(spacing: 0) {
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
                        // `.contentTransition`, **not** `.id` plus a
                        // `.transition`. Both cross-fade the words; only this
                        // one leaves the note travelling.
                        //
                        // A transition needs two identities, and two identities
                        // are two views: the outgoing note is removed *where it
                        // stood* and the incoming inserted *where it belongs*,
                        // so neither of them moves. On a press that changes the
                        // words and the indent together — which is every press
                        // on this card — the title glided 26 pt while the note
                        // under it sat still and then appeared at the far end.
                        // Measured, leftmost ink of the note band, twenty
                        // frames: `[2, 2, 2, 2, 2, 2, 53, 54, 54 …]`.
                        //
                        // A content transition changes what one view *draws*
                        // without changing which view it is, so the layout goes
                        // on animating underneath it. Law 1 cuts both ways:
                        // identity is what lets a transition fire, and it is
                        // also what stops anything travelling.
                        .contentTransition(.opacity)
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
            // 12, which is what the stack's own spacing used to contribute
            // here before it went to 0 for the mark column's sake.
            Spacer(minLength: 12)
            HStack(spacing: 8) { trailing }
        }
    }

    /// **One view for all four marks, not a `switch` over them.**
    ///
    /// This was four branches, and SwiftUI interpolates between two states of
    /// one view and never between two views — so `.space` → `.holding` was an
    /// insert and a remove however many transactions surrounded it, and the
    /// green tick simply appeared. The four states are properties of a single
    /// `Image` now: which symbol, what colour, whether it is drawn at all, and
    /// how wide the column it sits in is. Every one of those interpolates.
    ///
    /// `helmSymbolSwap` is what carries clock → tick, which is a *replacement*
    /// of one glyph by another rather than a reveal — the house rule about
    /// growing applies to blocks arriving, not to a 14 pt symbol changing what
    /// it says. This was a bare `.contentTransition(.symbolEffect(.replace))`
    /// until the token existed; the two symbols share a ring, so it is Magic
    /// Replace that carries them now and only the hands inside move.
    private var markView: some View {
        Image(systemName: symbolName)
            .foregroundStyle(markInk)
            .helmSymbolSwap(symbolName)
            // Nothing to say, but the column may still have to hold its width:
            // `.space` is drawn and invisible rather than absent, so the labels
            // of a mixed card keep one left edge.
            .opacity(mark == .holding || mark == .waiting ? 1 : 0)
            // The whole column, gap included. At `.none` it is nothing at all
            // and the labels sit flush; anywhere else it is the mark's width
            // plus the gap the stack no longer contributes.
            .frame(width: mark == .none ? 0 : Self.markWidth + 12, alignment: .leading)
            .accessibilityHidden(true)
    }

    /// `.space` keeps the tick's name rather than an empty string: an `Image`
    /// with no symbol is a different shape, and the swap out of invisibility
    /// would resize the column under the transition that is carrying it.
    private var symbolName: String {
        mark == .waiting ? "clock" : "checkmark.circle.fill"
    }

    private var markInk: Color {
        mark == .waiting ? HelmText.faint : HelmSignal.success
    }

}

/// 14, from `.rspace { flex: 0 0 14px }` — the same column the marks are drawn
/// in, so a card of mixed rows keeps one left edge for its labels.
///
/// Outside the struct because `HelmSettingRow` is generic in its trailing view,
/// and a generic type cannot hold a static stored property. One number for
/// every specialisation is exactly what it has to be.
extension HelmSettingRow { fileprivate static var markWidth: CGFloat { 14 } }
