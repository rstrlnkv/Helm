import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

/// The page's one figure: what the module has put right over a period somebody chooses, and what that
/// came to in time. Centred like Keep Awake's hero, so it takes no `groupedHeaderOutset`.
///
/// Every state with the period row is the same height: the caption changes what it says rather than coming and
/// going, so pressing a period moves nothing under it. The row itself closes when the module is not watching.
struct LayoutHero: View {

    let totals: ConversionTotals
    let suspended: Bool
    let watching: Bool
    @Binding var period: ConversionPeriod
    /// Offered only when the grant is missing; the hero carries the verb.
    var grant: (() -> Void)?

    @State private var controlsHeight: CGFloat?
    @State private var grantHeight: CGFloat?
    /// The drawn copy of `watching`: an engine-published value is not a press, so the swap travels
    /// through this flag written inside `withAnimation` (`helmAccordion`).
    @State private var shownWatching: Bool
    /// The drawn copy of `offersGrant`.
    @State private var shownGrant: Bool

    init(totals: ConversionTotals, suspended: Bool, watching: Bool,
         period: Binding<ConversionPeriod>, grant: (() -> Void)?) {
        self.totals = totals
        self.suspended = suspended
        self.watching = watching
        _period = period
        self.grant = grant
        _shownWatching = State(initialValue: watching)
        _shownGrant = State(initialValue: !watching && grant != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            figure
                // A number takes the tabular face and the tracking; a sentence takes neither, since
                // `tracking(-2)` would squeeze «Not watching» for no reason.
                .font(hasFigure ? HelmText.heroFigureFont : HelmText.heroFont)
                .tracking(hasFigure ? HelmText.heroFigureTracking : 0)
                // A figure that changes rolls; the keyed animation makes the transition animate.
                .contentTransition(.numericText())
                .animation(HelmMotion.interface, value: figureText)
                .helmHeroSentence()
                .frame(maxWidth: .infinity)

            Text(caption)
                .font(HelmText.rowTitle)
                .foregroundStyle(HelmText.quiet)
                .helmHeroSentence()
                .padding(.top, HelmSpace.s4)

            // Both blocks always exist and only their heights change: an `if` would insert one.
            controls
                .padding(.top, HelmSpace.s6)
                .helmAccordion(open: shownWatching, height: $controlsHeight)
            Button(HelmPermissionNote.grantLabel) { grant?() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, HelmSpace.s6)
                .helmAccordion(open: shownGrant, height: $grantHeight)
        }
        .onChange(of: watching) { _, now in
            withAnimation(HelmMotion.disclosure) { shownWatching = now }
        }
        .onChange(of: offersGrant) { _, offered in
            withAnimation(HelmMotion.disclosure) { shownGrant = offered }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - The figure

    private var offersGrant: Bool { !watching && grant != nil }

    private var figures: LedgerFigures { totals.figures(period) }

    private var seconds: TimeInterval {
        TimeSaved.seconds(words: figures.words, characters: figures.characters)
    }

    /// Nothing put right is not «0»: a zero reads as a fault, so that state is drawn as a sentence.
    private var hasFigure: Bool { figures.words > 0 }

    private var state: HeroSentence {
        HeroSentence(watching: watching, suspended: suspended, hasFigure: hasFigure)
    }

    private var figureText: String {
        guard state.showsFigure else {
            switch state {
            case .nothingYet: return LyStr.nothingYet
            default: return LyStr.heroNotWatching
            }
        }
        return Decimal(Double(figures.words), decimals: 0)
    }

    private var figure: some View {
        Text(figureText)
            .foregroundStyle(state.showsFigure ? Color.primary : HelmText.quiet)
    }

    /// What the figure is, over what, and what it came to in typing: one string, so one height in every state.
    private var caption: String {
        switch state {
        case .deaf: return LyStr.heroNotWatchingWhy
        case .paused: return LyStr.suspended
        case .nothingYet: return LyStr.nothingYetNote
        case .counting: break
        }
        let counted = LyStr.wordsIn(period, count: figures.words)
        let spelled = HelmDuration.string(seconds)
        guard !spelled.isEmpty else { return counted }
        return counted + " · ≈ " + spelled + " " + LyStr.notSpentTypingAgain()
    }

    // MARK: - The controls

    /// Five capsule buttons in a row that folds to a second line rather than truncating; the chosen
    /// period shows `helmChosen`, whatever the window's key state.
    private var controls: some View {
        HelmWrappingRow {
            ForEach(ConversionPeriod.allCases, id: \.self) { option in
                Button(LyStr.periodName(option)) { period = option }
                    // The hero is a `Form` section header, whose bold font a button would inherit.
                    .font(HelmText.rowTitle)
                    .helmChosen(period == option)
                    .accessibilityAddTraits(period == option ? [.isSelected] : [])
            }
        }
        .helmCapsuleButtons()
    }
}
