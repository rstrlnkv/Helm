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

            // Always occupied, never inserted: this is what keeps the four
            // states one height. It says the estimate's assumption while the
            // figure is time, and when counting began while it is words.
            if watching {
                controls.padding(.top, HelmSpace.s6)
                // **Under the verbs, the way `KeepAwakeHero.stopNote` is.**
                // Between the caption and the buttons it made this hero's
                // rhythm 38.5 pt where both finished heroes are 26 — measured,
                // constant across all eight languages and every width. The
                // always-drawn line is what keeps every state one height; where
                // it stands is what keeps the app one rhythm.
                Text(note.isEmpty ? LyStr.notSpentTypingAgain : note)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, HelmSpace.s3)
                    .opacity(note.isEmpty ? 0 : 1)
                    .accessibilityHidden(note.isEmpty)
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

    private var caption: String {
        guard watching else { return LyStr.heroNotWatchingWhy }
        guard hasFigure else { return LyStr.nothingYetNote }
        if suspended { return LyStr.suspended }
        return LyStr.wordsIn(period, count: figures.words)
    }

    /// The line that never leaves: what the count came to in typing time.
    ///
    /// **Both numbers at once, which is what the panel tile always did.** They
    /// used to be one at a time behind a two-glyph switch in the *window
    /// header* — so the 744 pt page showed one and a 280 pt tile showed both,
    /// two surfaces disagreeing about what the figure is. The switch also left
    /// the bottom 19 pt of this hero blank in the state it ships in: measured
    /// 0 ink in the band 118–137 pt with the figure on words, because the line
    /// was reserved at `.opacity(0)` so pressing a glyph would not move the
    /// form. Reserved is right when a switch exists; the answer was to drop the
    /// switch.
    ///
    /// Empty before the first word, so the hero says nothing it has not
    /// measured — and drawn either way, which is what keeps every state one
    /// height.
    private var note: String {
        guard watching, hasFigure, !suspended else { return "" }
        let spelled = HelmDuration.string(seconds)
        guard !spelled.isEmpty else { return "" }
        return "≈ " + spelled + " " + LyStr.notSpentTypingAgain
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
