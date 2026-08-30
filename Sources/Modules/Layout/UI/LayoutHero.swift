import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

/// The page's one figure: what the module has put right, over a period somebody
/// chooses, and what that came to in time.
///
/// Built to the shape the two finished pages of this app already use — Keep
/// Awake's and VPN's — because those are the ones that have been measured and
/// argued over. Centred like Keep Awake's, which is why it takes no
/// `groupedHeaderOutset`: the 10 pt is for a block that draws a surface, and
/// centred text needs none of it.
///
/// **Every state is the same height.** The figure changes, the caption changes,
/// and the line under them changes what it says rather than coming and going —
/// a hero that grows a line when somebody presses a segment moves the whole
/// form under it on an act that was not about the form.
struct LayoutHero: View {

    let totals: ConversionTotals
    let suspended: Bool
    let watching: Bool
    @Binding var period: ConversionPeriod
    /// Offered only when the grant is missing — the hero carries the verb
    /// rather than repeating itself in a second block below.
    var grant: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            figure
                // A number takes the tabular face and the tracking; a sentence
                // takes neither — «Not watching» lost 10.9 % of its width to
                // `tracking(-2)`, measured, and Spanish 13.9 %. Keep Awake
                // draws the same distinction for the same reason.
                .font(hasFigure ? HelmText.heroFigureFont : HelmText.heroFont)
                .tracking(hasFigure ? -2 : 0)
                // A figure that changes rolls rather than cuts — and the keyed
                // animation is the half that makes the transition an animation
                // rather than an instruction for one.
                .contentTransition(.numericText())
                .animation(HelmMotion.interface, value: figureText)
                .frame(maxWidth: .infinity)

            Text(caption)
                .font(HelmText.rowTitle)
                .foregroundStyle(HelmText.quiet)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, HelmSpace.s4)

            if watching {
                controls.padding(.top, HelmSpace.s6)
            } else if let grant {
                Button(HelmPermissionNote.grantLabel, action: grant)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, HelmSpace.s6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - The figure

    private var figures: LedgerFigures { totals.figures(period) }

    private var seconds: TimeInterval {
        TimeSaved.seconds(words: figures.words, characters: figures.characters)
    }

    /// Nothing put right is not «0». A module that has been watching all day and
    /// had nothing to correct is working perfectly, and a zero reads as a fault
    /// — the state no edition of the redesign ever drew.
    private var hasFigure: Bool { figures.words > 0 }

    private var figureText: String {
        guard hasFigure else { return watching ? LyStr.nothingYet : LyStr.heroNotWatching }
        return Decimal(Double(figures.words), decimals: 0)
    }

    private var figure: some View {
        Text(figureText)
            .foregroundStyle(hasFigure ? Color.primary : HelmText.quiet)
    }

    /// What the figure is, over what, and what it came to in typing.
    ///
    /// **One line, not two.** The estimate had a line of its own under the
    /// period buttons — always drawn, at `.opacity(0)` half the time, so that
    /// pressing a glyph could not move the form. The glyph is gone (§ the
    /// metric switch), so the line was reserved against nothing, and a figure's
    /// scale and a figure's consequence are one thought: «23 · words put right ·
    /// month · ≈ 48 s not spent typing again».
    ///
    /// Every state is still one string and therefore one height, which is what
    /// the reserved line used to buy. `LayoutHeroIsOneHeightTests` measures it
    /// in all eight languages rather than trusting this comment.
    private var caption: String {
        guard watching else { return LyStr.heroNotWatchingWhy }
        guard hasFigure else { return LyStr.nothingYetNote }
        if suspended { return LyStr.suspended }
        let counted = LyStr.wordsIn(period, count: figures.words)
        let spelled = HelmDuration.string(seconds)
        guard !spelled.isEmpty else { return counted }
        return counted + " · ≈ " + spelled + " " + LyStr.notSpentTypingAgain()
    }


    // MARK: - The controls

    /// Every choice on this row is a button, the way Keep Awake's hero is: one
    /// `HelmWrappingRow` of `.large` buttons that folds instead of truncating.
    ///
    /// **Buttons rather than a segmented control, and that is a measurement.**
    /// A segmented picker draws to its intrinsic width and centres inside
    /// whatever it is given, so inside a row that proposes `.unspecified` it has
    /// no headroom at all — measured at 347.5 pt for five words in English,
    /// 52 pt for the glyph pair, drawn exactly equal to wanted in all eight
    /// languages. `LongStringGeometryRatchetTests` counts a control with under
    /// 39 % room as one a longer word breaks, which German and French are.
    /// A row of buttons wraps to a second line instead, which is what
    /// `HelmWrappingRow` exists for.
    ///
    /// The chosen one is `.borderedProminent`; the rest are ordinary. That is
    /// the same «this is the one that is on» the panel uses, and it needs no
    /// second colour of its own.
    private var controls: some View {
        HelmWrappingRow {
            ForEach(ConversionPeriod.allCases, id: \.self) { option in
                periodButton(option)
            }
        }
    }

    private func periodButton(_ option: ConversionPeriod) -> some View {
        chooser(chosen: period == option) { period = option } label: {
            Text(LyStr.periodName(option))
        }
    }

    /// One button, filled when it is the one in force.
    ///
    /// `.borderedProminent` and `.bordered` are two types, so the choice is a
    /// branch rather than a value — SwiftUI has no `AnyButtonStyle`, and hiding
    /// that behind an erased wrapper would cost more than the four lines it
    /// saves.
    @ViewBuilder
    private func chooser<Label: View>(chosen: Bool,
                                      action: @escaping () -> Void,
                                      @ViewBuilder label: () -> Label) -> some View {
        if chosen {
            Button(action: action, label: label)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: action, label: label)
                .controlSize(.large)
                .buttonStyle(.bordered)
        }
    }
}
